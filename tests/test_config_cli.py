import os

from vrpn_mqtt_bridge.cli import parse_config
from vrpn_mqtt_bridge.config import config_from_env, parse_vrpn_endpoint, validate_config
from vrpn_mqtt_bridge.env import load_env_file


def test_generic_defaults_are_not_site_specific():
    config = config_from_env({})
    assert config.vrpn_host == "127.0.0.1"
    assert config.vrpn_port == 3883
    assert config.tracker_name == "tracker"
    assert config.mqtt_host == "localhost"
    assert config.mqtt_username == ""
    assert config.pose_topic == "vrpn/pose"


def test_legacy_slam_env_is_still_accepted():
    config = config_from_env(
        {
            "SLAM_MQTT_HOST": "broker",
            "SLAM_MQTT_USERNAME": "user",
            "SLAM_POSE_TOPIC": "slam/position",
        }
    )
    assert config.mqtt_host == "broker"
    assert config.mqtt_username == "user"
    assert config.pose_topic == "slam/position"


def test_cli_overrides_env(monkeypatch):
    monkeypatch.setenv("VRPN_HOST", "env-host")
    config = parse_config(["--vrpn-host", "cli-host", "--dry-run", "--quiet"])
    assert config.vrpn_host == "cli-host"
    assert config.dry_run is True
    assert config.quiet is True


def test_vrpn_endpoint_overrides_tracker_host_port():
    config = parse_config(["--vrpn-endpoint", "rigidbody@192.0.2.10:4000", "--dry-run"])
    assert config.vrpn_endpoint == "rigidbody@192.0.2.10:4000"
    assert config.tracker_name == "rigidbody"
    assert config.vrpn_host == "192.0.2.10"
    assert config.vrpn_port == 4000


def test_native_vrpn_compat_defaults():
    config = parse_config(["--compat", "native-vrpn", "--dry-run"])
    assert config.tracker_name == "tracker0"
    assert config.vrpn_host == "127.0.0.1"
    assert config.vrpn_port == 3883
    assert config.vrpn_source == "native"


def test_native_source_is_accepted():
    config = config_from_env({"VRPN_SOURCE": "native"})
    validate_config(config)
    assert config.vrpn_source == "native"


def test_native_reader_bin_from_env():
    config = config_from_env({"VRPN_NATIVE_READER_BIN": "/tmp/vrpn_pose_reader"})
    assert config.vrpn_native_reader_bin == "/tmp/vrpn_pose_reader"


def test_native_vrpn_env_defaults():
    config = config_from_env({"VRPN_COMPAT": "native-vrpn"})
    assert config.tracker_name == "tracker0"
    assert config.vrpn_port == 3883
    assert config.vrpn_source == "native"


def test_parse_vrpn_endpoint():
    parts = parse_vrpn_endpoint("tracker@127.0.0.1:3883")
    assert parts.tracker == "tracker"
    assert parts.host == "127.0.0.1"
    assert parts.port == 3883


def test_env_file_loader(tmp_path, monkeypatch):
    env_file = tmp_path / "bridge.env"
    env_file.write_text("VRPN_HOST=file-host\nVRPN_MQTT_PORT=2883\n", encoding="utf-8")
    monkeypatch.delenv("VRPN_HOST", raising=False)
    monkeypatch.delenv("VRPN_MQTT_PORT", raising=False)
    load_env_file(env_file)
    assert os.environ["VRPN_HOST"] == "file-host"
    assert os.environ["VRPN_MQTT_PORT"] == "2883"


def test_parse_config_reads_env_file(tmp_path, monkeypatch):
    env_file = tmp_path / "bridge.env"
    env_file.write_text("VRPN_HOST=file-host\nVRPN_TRACKER=rigidbody\n", encoding="utf-8")
    monkeypatch.delenv("VRPN_HOST", raising=False)
    monkeypatch.delenv("VRPN_TRACKER", raising=False)
    config = parse_config(["--env-file", str(env_file), "--dry-run"])
    assert config.vrpn_host == "file-host"
    assert config.tracker_name == "rigidbody"
    assert config.dry_run is True


def test_validate_rejects_invalid_source():
    config = config_from_env({"VRPN_SOURCE": "bad"})
    try:
        validate_config(config)
    except ValueError as exc:
        assert "vrpn_source" in str(exc)
    else:
        raise AssertionError("validate_config should reject invalid source")
