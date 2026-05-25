"""Runtime configuration for the bridge."""

from __future__ import annotations

import os
import shutil
from dataclasses import dataclass
from typing import Mapping, NamedTuple, Optional


ENV_PREFIX = "VRPN_"


@dataclass(frozen=True)
class BridgeConfig:
    vrpn_endpoint: str
    vrpn_host: str
    vrpn_port: int
    tracker_name: str
    mqtt_host: str
    mqtt_port: int
    mqtt_username: str
    mqtt_password: str
    pose_topic: str
    yaw_topic: str
    status_topic: str
    frequency_topic: str
    max_mqtt_rate_hz: float
    display_rate_hz: float
    status_interval_sec: float
    timeout_sec: float
    client_id: str
    z_offset: float
    invert_yaw: bool
    vrpn_source: str
    vrpn_native_reader_bin: str
    vrpn_print_devices_bin: str
    dry_run: bool
    quiet: bool
    log_format: str
    reconnect_interval_sec: float
    fail_on_mqtt_error: bool


class VrpnEndpointParts(NamedTuple):
    tracker: str
    host: str
    port: Optional[int]


def env_str(env: Mapping[str, str], names: tuple[str, ...], default: str) -> str:
    for name in names:
        value = env.get(name)
        if value not in (None, ""):
            return str(value)
    return default


def env_int(env: Mapping[str, str], names: tuple[str, ...], default: int) -> int:
    raw = env_str(env, names, "")
    if raw == "":
        return default
    try:
        return int(raw)
    except ValueError:
        return default


def env_float(env: Mapping[str, str], names: tuple[str, ...], default: float) -> float:
    raw = env_str(env, names, "")
    if raw == "":
        return default
    try:
        return float(raw)
    except ValueError:
        return default


def env_bool(env: Mapping[str, str], names: tuple[str, ...], default: bool) -> bool:
    raw = env_str(env, names, "")
    if raw == "":
        return default
    normalized = raw.strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    return default


def default_vrpn_print_devices_bin() -> str:
    candidates = (
        shutil.which("vrpn_print_devices"),
        "/opt/ros/noetic/bin/vrpn_print_devices",
        "/opt/ros/humble/bin/vrpn_print_devices",
        "/opt/ros/iron/bin/vrpn_print_devices",
        "/opt/ros/jazzy/bin/vrpn_print_devices",
    )
    for candidate in candidates:
        if candidate:
            return candidate
    return "vrpn_print_devices"


def default_vrpn_native_reader_bin() -> str:
    repo_reader = os.path.abspath(
        os.path.join(
            os.path.dirname(__file__),
            "..",
            "..",
            "native",
            "vrpn_pose_reader",
            "build",
            "vrpn_pose_reader",
        )
    )
    candidates = (
        repo_reader,
        shutil.which("vrpn_pose_reader"),
        "/usr/local/bin/vrpn_pose_reader",
    )
    for candidate in candidates:
        if candidate and (shutil.which(candidate) or os.path.exists(candidate)):
            return candidate
    return "vrpn_pose_reader"


def parse_vrpn_endpoint(endpoint: str) -> VrpnEndpointParts:
    """Parse ``tracker@host:port`` into reusable pieces.

    VRPN accepts endpoint strings such as ``tracker@127.0.0.1:3883``. This
    parser keeps the rules intentionally small: the tracker part is optional
    for parsing, and the port is recognized only when the final host segment is
    numeric.
    """

    value = endpoint.strip()
    if not value:
        return VrpnEndpointParts("", "", None)

    tracker = ""
    target = value
    if "@" in value:
        tracker, target = value.split("@", 1)

    target = target.strip()
    if target.startswith("vrpn:"):
        target = target[len("vrpn:") :]

    host = target
    port: Optional[int] = None
    if target.startswith("["):
        bracket = target.find("]")
        if bracket >= 0:
            host = target[: bracket + 1]
            suffix = target[bracket + 1 :]
            if suffix.startswith(":") and suffix[1:].isdigit():
                port = int(suffix[1:])
    else:
        possible_host, separator, possible_port = target.rpartition(":")
        if separator and possible_host and possible_port.isdigit():
            host = possible_host
            port = int(possible_port)

    return VrpnEndpointParts(tracker.strip(), host.strip(), port)


def config_from_env(env: Mapping[str, str] | None = None) -> BridgeConfig:
    env = os.environ if env is None else env
    endpoint = env_str(env, ("VRPN_ENDPOINT",), "")
    endpoint_parts = parse_vrpn_endpoint(endpoint)
    compat = env_str(env, ("VRPN_COMPAT",), "generic")
    compat_tracker = "tracker0" if compat == "native-vrpn" else "tracker"
    compat_source = "native" if compat == "native-vrpn" else "auto"
    default_tracker = endpoint_parts.tracker or compat_tracker
    default_host = endpoint_parts.host or "127.0.0.1"
    default_port = endpoint_parts.port or 3883
    return BridgeConfig(
        vrpn_endpoint=endpoint,
        vrpn_host=env_str(env, ("VRPN_HOST", "VRPN_IP"), default_host),
        vrpn_port=env_int(env, ("VRPN_PORT",), default_port),
        tracker_name=env_str(env, ("VRPN_TRACKER",), default_tracker),
        mqtt_host=env_str(env, ("VRPN_MQTT_HOST", "SLAM_MQTT_HOST"), "localhost"),
        mqtt_port=env_int(env, ("VRPN_MQTT_PORT", "SLAM_MQTT_PORT"), 1883),
        mqtt_username=env_str(env, ("VRPN_MQTT_USERNAME", "SLAM_MQTT_USERNAME"), ""),
        mqtt_password=env_str(env, ("VRPN_MQTT_PASSWORD", "SLAM_MQTT_PASSWORD"), ""),
        pose_topic=env_str(env, ("VRPN_MQTT_POSE_TOPIC", "SLAM_POSE_TOPIC"), "vrpn/pose"),
        yaw_topic=env_str(env, ("VRPN_MQTT_YAW_TOPIC", "SLAM_YAW_TOPIC"), "vrpn/yaw"),
        status_topic=env_str(env, ("VRPN_MQTT_STATUS_TOPIC", "SLAM_STATUS_TOPIC"), "vrpn/status"),
        frequency_topic=env_str(
            env,
            ("VRPN_MQTT_FREQUENCY_TOPIC", "SLAM_FREQUENCY_TOPIC"),
            "vrpn/frequency",
        ),
        max_mqtt_rate_hz=env_float(env, ("VRPN_MAX_MQTT_RATE", "SLAM_MAX_MQTT_RATE"), 30.0),
        display_rate_hz=env_float(env, ("VRPN_DISPLAY_RATE",), 10.0),
        status_interval_sec=env_float(env, ("VRPN_STATUS_INTERVAL_SEC",), 1.0),
        timeout_sec=env_float(env, ("VRPN_TIMEOUT_SEC", "SLAM_TIMEOUT_SEC"), 5.0),
        client_id=env_str(env, ("VRPN_MQTT_CLIENT_ID",), f"vrpn-mqtt-bridge-{os.getpid()}"),
        z_offset=env_float(env, ("VRPN_Z_OFFSET",), 0.0),
        invert_yaw=env_bool(env, ("VRPN_INVERT_YAW",), False),
        vrpn_source=env_str(env, ("VRPN_SOURCE",), compat_source),
        vrpn_native_reader_bin=env_str(
            env,
            ("VRPN_NATIVE_READER_BIN",),
            default_vrpn_native_reader_bin(),
        ),
        vrpn_print_devices_bin=env_str(
            env,
            ("VRPN_PRINT_DEVICES_BIN",),
            default_vrpn_print_devices_bin(),
        ),
        dry_run=env_bool(env, ("VRPN_DRY_RUN",), False),
        quiet=env_bool(env, ("VRPN_QUIET",), False),
        log_format=env_str(env, ("VRPN_LOG_FORMAT",), "table"),
        reconnect_interval_sec=env_float(env, ("VRPN_MQTT_RECONNECT_INTERVAL_SEC",), 2.0),
        fail_on_mqtt_error=env_bool(env, ("VRPN_FAIL_ON_MQTT_ERROR",), False),
    )


def validate_config(config: BridgeConfig) -> None:
    positive_values = {
        "mqtt_port": float(config.mqtt_port),
        "vrpn_port": float(config.vrpn_port),
        "max_mqtt_rate_hz": config.max_mqtt_rate_hz,
        "display_rate_hz": config.display_rate_hz,
        "status_interval_sec": config.status_interval_sec,
        "timeout_sec": config.timeout_sec,
        "reconnect_interval_sec": config.reconnect_interval_sec,
    }
    for name, value in positive_values.items():
        if value <= 0:
            raise ValueError(f"{name} must be greater than 0")
    if config.vrpn_source not in {"auto", "native", "python", "cli"}:
        raise ValueError("vrpn_source must be auto, native, python, or cli")
    if config.log_format not in {"table", "json"}:
        raise ValueError("log_format must be table or json")
