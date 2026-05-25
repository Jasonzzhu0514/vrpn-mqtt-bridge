from vrpn_mqtt_bridge.config import config_from_env
from vrpn_mqtt_bridge.vrpn_source import (
    NativeVrpnPoseReaderTracker,
    VrpnPrintDevicesTracker,
    build_tracker,
    build_vrpn_endpoint,
    parse_native_vrpn_pose_reader_line,
    parse_vrpn_print_devices_line,
)


def test_parse_vrpn_print_devices_line():
    message = parse_vrpn_print_devices_line(
        "Tracker tracker@host: pos (1.0, -2.5, 3.25); quat (0, 0, 0.7071068, 0.7071068)"
    )
    assert message is not None
    assert message["position"] == (1.0, -2.5, 3.25)
    assert message["quaternion"] == (0.0, 0.0, 0.7071068, 0.7071068)


def test_parse_vrpn_print_devices_line_ignores_non_pose():
    assert parse_vrpn_print_devices_line("analog channel noise") is None


def test_parse_native_vrpn_pose_reader_line():
    message = parse_native_vrpn_pose_reader_line(
        '{"time":1.25,"endpoint":"tracker0@127.0.0.1:3883",'
        '"position":[1,-2,3.5],"quaternion":[0,0,0.7071068,0.7071068]}'
    )
    assert message is not None
    assert message["time"] == 1.25
    assert message["endpoint"] == "tracker0@127.0.0.1:3883"
    assert message["position"] == (1.0, -2.0, 3.5)
    assert message["quaternion"] == (0.0, 0.0, 0.7071068, 0.7071068)


def test_parse_native_vrpn_pose_reader_line_ignores_non_pose():
    assert parse_native_vrpn_pose_reader_line("status: connected") is None
    assert parse_native_vrpn_pose_reader_line('{"position":[1],"quaternion":[0,0,0,1]}') is None


def test_build_vrpn_endpoint_uses_port():
    config = config_from_env({"VRPN_TRACKER": "tracker", "VRPN_HOST": "127.0.0.1", "VRPN_PORT": "3883"})
    assert build_vrpn_endpoint(config) == "tracker@127.0.0.1:3883"


def test_build_vrpn_endpoint_preserves_explicit_endpoint():
    config = config_from_env({"VRPN_ENDPOINT": "tracker@127.0.0.1:4000"})
    assert build_vrpn_endpoint(config) == "tracker@127.0.0.1:4000"


def test_build_tracker_auto_prefers_native_when_available(tmp_path):
    helper = tmp_path / "vrpn_pose_reader"
    helper.write_text("#!/bin/sh\n", encoding="utf-8")
    config = config_from_env({"VRPN_NATIVE_READER_BIN": str(helper)})
    tracker = build_tracker(config)
    assert isinstance(tracker, NativeVrpnPoseReaderTracker)


def test_build_tracker_cli_uses_print_devices(tmp_path):
    helper = tmp_path / "vrpn_print_devices"
    helper.write_text("#!/bin/sh\n", encoding="utf-8")
    config = config_from_env({"VRPN_SOURCE": "cli", "VRPN_PRINT_DEVICES_BIN": str(helper)})
    tracker = build_tracker(config)
    assert isinstance(tracker, VrpnPrintDevicesTracker)
