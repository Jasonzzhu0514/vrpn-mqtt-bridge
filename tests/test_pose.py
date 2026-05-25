import math

from vrpn_mqtt_bridge.config import config_from_env
from vrpn_mqtt_bridge.pose import normalize_yaw, pose_from_components, pose_from_vrpn_message, yaw_from_quaternion


def test_yaw_from_identity_quaternion():
    assert yaw_from_quaternion((0.0, 0.0, 0.0, 1.0)) == 0.0


def test_yaw_from_quaternion_90_deg():
    half = math.sqrt(0.5)
    assert round(yaw_from_quaternion((0.0, 0.0, half, half)), 3) == 90.0


def test_pose_applies_z_offset_and_invert_yaw():
    config = config_from_env({"VRPN_Z_OFFSET": "1.25", "VRPN_INVERT_YAW": "true"})
    half = math.sqrt(0.5)
    pose = pose_from_components((1.2345, 2.3456, 3.4567), (0.0, 0.0, half, half), config, timestamp_ms=123)
    assert pose.timestamp_ms == 123
    assert pose.x == 1.234
    assert pose.y == 2.346
    assert pose.z == 4.707
    assert pose.yaw == -90.0


def test_pose_from_vrpn_message_uses_vrpn_timestamp_dict():
    config = config_from_env({})
    pose = pose_from_vrpn_message(
        {
            "time": {"tv_sec": 10, "tv_usec": 250000},
            "position": (1, 2, 3),
            "quaternion": (0, 0, 0, 1),
        },
        config,
    )
    assert pose.timestamp_ms == 10250


def test_normalize_yaw_range():
    assert normalize_yaw(181) == -179
    assert normalize_yaw(-181) == 179
    assert normalize_yaw(540) == 180
