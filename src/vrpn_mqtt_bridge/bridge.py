"""Bridge loop joining VRPN input to MQTT output."""

from __future__ import annotations

import json
import sys
import time
from typing import Any

from vrpn_mqtt_bridge.config import BridgeConfig
from vrpn_mqtt_bridge.formatting import format_local_time, format_signed_float, truncate_text
from vrpn_mqtt_bridge.mqtt_publisher import MqttPublisher
from vrpn_mqtt_bridge.pose import TrackerPose, pose_from_vrpn_message
from vrpn_mqtt_bridge.vrpn_source import TrackerSource, build_tracker
from vrpn_mqtt_bridge.vrpn_source import build_vrpn_endpoint


class VrpnMqttBridge:
    def __init__(
        self,
        config: BridgeConfig,
        *,
        tracker: TrackerSource | None = None,
        publisher: MqttPublisher | None = None,
    ) -> None:
        self.config = config
        self.running = True
        self.latest_pose: TrackerPose | None = None
        self.last_vrpn_at = 0.0
        self.last_publish_at = 0.0
        self.last_display_at = 0.0
        self.last_status_at = 0.0
        self.last_mqtt_connect_attempt_at = 0.0
        self.last_mqtt_error_print_at = 0.0
        self.stat_at = time.time()
        self.vrpn_count = 0
        self.mqtt_count = 0
        self.last_frequency: dict[str, float] = {"vrpn": 0.0, "mqtt": 0.0}
        self.print_header_written = False
        self.realtime_line_active = False

        self.publisher = publisher or MqttPublisher(config)
        self.tracker = tracker or build_tracker(config)
        self.tracker.register_change_handler(None, self._on_tracker_pose, "position")

    def connect(self) -> None:
        if self.config.dry_run:
            print(
                "dry-run VRPN "
                f"{build_vrpn_endpoint(self.config)} "
                f"display<={self.config.display_rate_hz:g}Hz"
            )
            return
        self.publisher.start()
        self._connect_mqtt(time.time(), force=True)
        print(
            "bridging VRPN "
            f"{build_vrpn_endpoint(self.config)} -> "
            f"{self.config.mqtt_host}:{self.config.mqtt_port} "
            f"pose={self.config.pose_topic} yaw={self.config.yaw_topic} "
            f"mqtt<={self.config.max_mqtt_rate_hz:g}Hz "
            f"display<={self.config.display_rate_hz:g}Hz"
        )

    def close(self) -> None:
        if self.realtime_line_active:
            print(flush=True)
            self.realtime_line_active = False
        close_tracker = getattr(self.tracker, "close", None)
        if callable(close_tracker):
            close_tracker()
        if not self.config.dry_run and self.publisher.connected:
            stamp_ms = int(time.time() * 1000)
            try:
                self.publisher.publish_json(
                    self.config.status_topic,
                    {"timestamp": stamp_ms, "source": "vrpn", "tracker": self.config.tracker_name, "status": "idle"},
                    retain=True,
                )
            except Exception:
                pass
        self.publisher.stop()

    def stop(self) -> None:
        self.running = False

    def run(self) -> None:
        self.connect()
        try:
            while self.running:
                self.tracker.mainloop()
                now = time.time()
                self._connect_mqtt(now)
                self._display_latest_if_due(now)
                self._publish_latest_if_due(now)
                self._publish_status_if_due(now)
                time.sleep(0.001)
        finally:
            self.close()

    def _connect_mqtt(self, now: float, *, force: bool = False) -> None:
        if self.config.dry_run or self.publisher.connected:
            return
        if not force and now - self.last_mqtt_connect_attempt_at < self.config.reconnect_interval_sec:
            return
        self.last_mqtt_connect_attempt_at = now
        try:
            self.publisher.connect()
        except Exception as exc:
            self.publisher.last_error = str(exc)
            if self.config.fail_on_mqtt_error:
                raise
            if not self.config.quiet and now - self.last_mqtt_error_print_at >= 5.0:
                self._print_status_line(
                    f"MQTT down: {self.config.mqtt_host}:{self.config.mqtt_port} ({exc}); "
                    "showing VRPN only"
                )
                self.last_mqtt_error_print_at = now
            return
        if not self.config.quiet:
            self._print_status_line(f"MQTT connected: {self.config.mqtt_host}:{self.config.mqtt_port}")
        self._safe_publish_status("waiting", retain=True)

    def _mark_mqtt_down(self, exc: Exception) -> None:
        self.publisher.disconnect_after_error(exc)
        if self.config.fail_on_mqtt_error:
            raise exc
        now = time.time()
        if not self.config.quiet and now - self.last_mqtt_error_print_at >= 5.0:
            self._print_status_line(
                f"MQTT down: {self.config.mqtt_host}:{self.config.mqtt_port} ({exc}); "
                "showing VRPN only"
            )
            self.last_mqtt_error_print_at = now

    def _print_status_line(self, message: str) -> None:
        if self.realtime_line_active:
            print(flush=True)
            self.realtime_line_active = False
        print(message, flush=True)

    def _on_tracker_pose(self, _userdata: object | None, message: dict[str, Any]) -> None:
        try:
            pose = pose_from_vrpn_message(message, self.config)
        except (TypeError, ValueError) as exc:
            print(f"ignored malformed VRPN pose: {exc}", file=sys.stderr)
            return
        self.latest_pose = pose
        self.last_vrpn_at = time.time()
        self.vrpn_count += 1

    def _pose_log_payload(self, pose: TrackerPose) -> dict[str, Any]:
        return {
            "timestamp": pose.timestamp_ms,
            "source": "vrpn",
            "tracker": self.config.tracker_name,
            "x": pose.x,
            "y": pose.y,
            "z": pose.z,
            "yaw": pose.yaw,
            "mqtt_status": "dry" if self.config.dry_run else ("up" if self.publisher.connected else "down"),
        }

    def _display_latest_if_due(self, now: float) -> None:
        if self.latest_pose is None:
            return
        if now - self.last_display_at < 1.0 / self.config.display_rate_hz:
            return
        self._print_realtime_pose(self._pose_log_payload(self.latest_pose))
        self.last_display_at = now

    def _publish_latest_if_due(self, now: float) -> None:
        if self.latest_pose is None:
            return
        if now - self.last_publish_at < 1.0 / self.config.max_mqtt_rate_hz:
            return
        pose = self.latest_pose
        base = {
            "timestamp": pose.timestamp_ms,
            "source": "vrpn",
            "tracker": self.config.tracker_name,
        }
        if self.config.dry_run:
            self.last_publish_at = now
            return
        if self.publisher.connected:
            try:
                self.publisher.publish_json(
                    self.config.pose_topic,
                    {**base, "x": pose.x, "y": pose.y, "z": pose.z},
                )
                self.publisher.publish_json(self.config.yaw_topic, {**base, "yaw": pose.yaw})
            except Exception as exc:
                self._mark_mqtt_down(exc)
            else:
                self.mqtt_count += 1
        self.last_publish_at = now

    def _print_realtime_pose(self, payload: dict[str, Any]) -> None:
        if self.config.quiet:
            return
        if self.config.log_format == "json":
            print(json.dumps(payload, separators=(",", ":")), flush=True)
            return

        if not self.print_header_written:
            print(
                "time         tracker        x(m)      y(m)      z(m)   yaw(deg)  "
                "vrpn_hz  mqtt_hz  mqtt",
                flush=True,
            )
            print(
                "-----------  -------  --------- --------- --------- ---------  "
                "-------  -------  ----",
                flush=True,
            )
            self.print_header_written = True

        timestamp_ms = int(payload.get("timestamp") or time.time() * 1000)
        tracker = truncate_text(str(payload.get("tracker", self.config.tracker_name)), 7)
        line = (
            f"{format_local_time(timestamp_ms):<11}  "
            f"{tracker:<7}  "
            f"{format_signed_float(payload.get('x'))} "
            f"{format_signed_float(payload.get('y'))} "
            f"{format_signed_float(payload.get('z'))} "
            f"{format_signed_float(payload.get('yaw'))}  "
            f"{self.last_frequency['vrpn']:>7.2f}  "
            f"{self.last_frequency['mqtt']:>7.2f}  "
            f"{str(payload.get('mqtt_status', 'dry')).lower():<4}"
        )
        print(f"\r\033[K{line}", end="", flush=True)
        self.realtime_line_active = True

    def _publish_status_if_due(self, now: float) -> None:
        if now - self.last_status_at < self.config.status_interval_sec:
            return
        age = None if self.last_vrpn_at <= 0 else now - self.last_vrpn_at
        status = "running" if age is not None and age <= self.config.timeout_sec else "waiting"
        if age is not None and age > self.config.timeout_sec:
            status = "stalled"
        self._safe_publish_status(status, age=age)
        self._publish_frequency(now)
        self.last_status_at = now

    def _safe_publish_status(self, status: str, *, age: float | None = None, retain: bool = False) -> None:
        if self.config.dry_run or not self.publisher.connected:
            return
        payload: dict[str, Any] = {
            "timestamp": int(time.time() * 1000),
            "source": "vrpn",
            "tracker": self.config.tracker_name,
            "status": status,
            "last_pose_age_sec": None if age is None else round(age, 3),
        }
        try:
            self.publisher.publish_json(self.config.status_topic, payload, retain=retain)
        except Exception as exc:
            self._mark_mqtt_down(exc)

    def _publish_frequency(self, now: float) -> None:
        dt = now - self.stat_at
        if dt <= 0:
            return
        self.last_frequency = {
            "vrpn": round(self.vrpn_count / dt, 2),
            "mqtt": round(self.mqtt_count / dt, 2),
        }
        if self.config.dry_run or not self.publisher.connected:
            self.vrpn_count = 0
            self.mqtt_count = 0
            self.stat_at = now
            return
        try:
            self.publisher.publish_json(
                self.config.frequency_topic,
                {
                    "timestamp": int(now * 1000),
                    "source": "vrpn",
                    "tracker": self.config.tracker_name,
                    "vrpn": self.last_frequency["vrpn"],
                    "mqtt": self.last_frequency["mqtt"],
                },
            )
        except Exception as exc:
            self._mark_mqtt_down(exc)
        self.vrpn_count = 0
        self.mqtt_count = 0
        self.stat_at = now
