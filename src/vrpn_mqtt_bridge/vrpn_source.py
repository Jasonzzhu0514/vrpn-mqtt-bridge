"""VRPN input adapters."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import threading
import time
from typing import Any, Callable, Dict, Optional, Protocol

from vrpn_mqtt_bridge.config import BridgeConfig


PoseCallback = Callable[[Optional[object], Dict[str, Any]], None]


class TrackerSource(Protocol):
    def register_change_handler(
        self,
        userdata: object | None,
        callback: PoseCallback,
        change_type: str,
    ) -> None:
        ...

    def mainloop(self) -> None:
        ...


VRPN_PRINT_POSE_RE = re.compile(
    r"pos\s+\(\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)\s*,"
    r"\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)\s*,"
    r"\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)\s*\)\s*;"
    r"\s*quat\s+\(\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)\s*,"
    r"\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)\s*,"
    r"\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)\s*,"
    r"\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)\s*\)"
)


class VrpnPrintDevicesTracker:
    """Adapter that exposes ``vrpn_print_devices`` like a Python VRPN tracker."""

    def __init__(self, config: BridgeConfig) -> None:
        self.config = config
        self.endpoint = build_vrpn_endpoint(config)
        self._callback: PoseCallback | None = None
        self._userdata: object | None = None
        self._process: subprocess.Popen[str] | None = None
        self._reader_thread: threading.Thread | None = None
        self._stop = threading.Event()

    def register_change_handler(
        self,
        userdata: object | None,
        callback: PoseCallback,
        change_type: str,
    ) -> None:
        if change_type != "position":
            raise ValueError("vrpn_print_devices fallback only supports position messages")
        self._userdata = userdata
        self._callback = callback
        self._start()

    def mainloop(self) -> None:
        if self._process is None:
            return
        returncode = self._process.poll()
        if returncode is not None and not self._stop.is_set():
            raise RuntimeError(f"vrpn_print_devices exited with status {returncode}")

    def close(self) -> None:
        self._stop.set()
        process = self._process
        if process is None:
            return
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=2.0)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2.0)
        self._process = None

    def _start(self) -> None:
        if self._process is not None:
            return
        binary = self.config.vrpn_print_devices_bin
        if not binary_available(binary):
            raise RuntimeError(
                "missing vrpn_print_devices. Install VRPN/ROS packages or set "
                "VRPN_PRINT_DEVICES_BIN=/path/to/vrpn_print_devices"
            )
        self._process = subprocess.Popen(
            [
                binary,
                "-nobutton",
                "-noanalog",
                "-nodial",
                "-notext",
                self.endpoint,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        self._reader_thread = threading.Thread(
            target=self._read_stdout,
            name="vrpn-print-devices-reader",
            daemon=True,
        )
        self._reader_thread.start()

    def _read_stdout(self) -> None:
        process = self._process
        if process is None or process.stdout is None:
            return
        for line in process.stdout:
            if self._stop.is_set():
                return
            message = parse_vrpn_print_devices_line(line)
            if message is None or self._callback is None:
                continue
            self._callback(self._userdata, message)


class NativeVrpnPoseReaderTracker:
    """Adapter for the native ``vrpn_pose_reader`` JSON Lines helper."""

    def __init__(self, config: BridgeConfig) -> None:
        self.config = config
        self.endpoint = build_vrpn_endpoint(config)
        self._callback: PoseCallback | None = None
        self._userdata: object | None = None
        self._process: subprocess.Popen[str] | None = None
        self._reader_thread: threading.Thread | None = None
        self._stop = threading.Event()

    def register_change_handler(
        self,
        userdata: object | None,
        callback: PoseCallback,
        change_type: str,
    ) -> None:
        if change_type != "position":
            raise ValueError("native VRPN reader only supports position messages")
        self._userdata = userdata
        self._callback = callback
        self._start()

    def mainloop(self) -> None:
        if self._process is None:
            return
        returncode = self._process.poll()
        if returncode is not None and not self._stop.is_set():
            raise RuntimeError(f"vrpn_pose_reader exited with status {returncode}")

    def close(self) -> None:
        self._stop.set()
        process = self._process
        if process is None:
            return
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=2.0)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2.0)
        self._process = None

    def _start(self) -> None:
        if self._process is not None:
            return
        binary = self.config.vrpn_native_reader_bin
        if not binary_available(binary):
            raise RuntimeError(
                "missing vrpn_pose_reader. Run scripts/build.sh, install the native helper, "
                "or set VRPN_NATIVE_READER_BIN=/path/to/vrpn_pose_reader"
            )
        self._process = subprocess.Popen(
            [
                binary,
                "--endpoint",
                self.endpoint,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        self._reader_thread = threading.Thread(
            target=self._read_stdout,
            name="vrpn-pose-reader",
            daemon=True,
        )
        self._reader_thread.start()

    def _read_stdout(self) -> None:
        process = self._process
        if process is None or process.stdout is None:
            return
        for line in process.stdout:
            if self._stop.is_set():
                return
            message = parse_native_vrpn_pose_reader_line(line)
            if message is None or self._callback is None:
                continue
            self._callback(self._userdata, message)


def parse_vrpn_print_devices_line(line: str) -> dict[str, Any] | None:
    match = VRPN_PRINT_POSE_RE.search(line)
    if match is None:
        return None
    values = [float(value) for value in match.groups()]
    return {
        "time": time.time(),
        "position": tuple(values[:3]),
        "quaternion": tuple(values[3:]),
    }


def parse_native_vrpn_pose_reader_line(line: str) -> dict[str, Any] | None:
    try:
        payload = json.loads(line)
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, dict):
        return None
    position = payload.get("position")
    quaternion = payload.get("quaternion")
    if not isinstance(position, list) or not isinstance(quaternion, list):
        return None
    if len(position) < 3 or len(quaternion) < 4:
        return None
    try:
        parsed: dict[str, Any] = {
            "time": float(payload.get("time", time.time())),
            "position": tuple(float(value) for value in position[:3]),
            "quaternion": tuple(float(value) for value in quaternion[:4]),
        }
    except (TypeError, ValueError):
        return None
    endpoint = payload.get("endpoint")
    if isinstance(endpoint, str):
        parsed["endpoint"] = endpoint
    return parsed


def build_tracker(config: BridgeConfig) -> TrackerSource:
    if config.vrpn_source in {"auto", "native"} and binary_available(config.vrpn_native_reader_bin):
        return NativeVrpnPoseReaderTracker(config)
    if config.vrpn_source == "native":
        raise RuntimeError(
            "missing vrpn_pose_reader. Run scripts/build.sh, use --vrpn-source=cli, "
            "or set VRPN_NATIVE_READER_BIN=/path/to/vrpn_pose_reader."
        )

    vrpn_module = _import_vrpn()
    if config.vrpn_source in {"auto", "python"} and vrpn_module is not None:
        endpoint = build_vrpn_endpoint(config)
        return vrpn_module.receiver.Tracker(endpoint)
    if config.vrpn_source == "python":
        raise RuntimeError(
            "missing dependency: Python VRPN bindings. Use --vrpn-source=cli "
            "or install a VRPN Python binding available for this environment."
        )
    if config.vrpn_source in {"auto", "cli"}:
        return VrpnPrintDevicesTracker(config)
    raise RuntimeError(f"unsupported VRPN source: {config.vrpn_source}")


def build_vrpn_endpoint(config: BridgeConfig) -> str:
    if config.vrpn_endpoint:
        return config.vrpn_endpoint
    host = config.vrpn_host or "127.0.0.1"
    if _host_has_port(host):
        return f"{config.tracker_name}@{host}"
    return f"{config.tracker_name}@{host}:{config.vrpn_port}"


def _host_has_port(host: str) -> bool:
    if host.startswith("["):
        bracket = host.find("]")
        return bracket >= 0 and host[bracket + 1 :].startswith(":")
    possible_host, separator, possible_port = host.rpartition(":")
    return bool(separator and possible_host and possible_port.isdigit())


def binary_available(binary: str) -> bool:
    return bool(shutil.which(binary) or os.path.exists(binary))


def _import_vrpn() -> Any | None:
    try:
        import vrpn.receiver  # type: ignore[import-not-found]
    except ModuleNotFoundError:
        return None
    import vrpn  # type: ignore[import-not-found]

    return vrpn
