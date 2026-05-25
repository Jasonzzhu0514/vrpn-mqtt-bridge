"""Pose conversion utilities."""

from __future__ import annotations

import math
import time
from dataclasses import dataclass
from typing import Any, Sequence

from vrpn_mqtt_bridge.config import BridgeConfig


@dataclass(frozen=True)
class TrackerPose:
    timestamp_ms: int
    x: float
    y: float
    z: float
    yaw: float


def yaw_from_quaternion(quaternion: Sequence[float]) -> float:
    x, y, z, w = quaternion
    siny_cosp = 2.0 * (w * z + x * y)
    cosy_cosp = 1.0 - 2.0 * (y * y + z * z)
    return math.degrees(math.atan2(siny_cosp, cosy_cosp))


def normalize_yaw(yaw: float) -> float:
    normalized = ((yaw + 180.0) % 360.0) - 180.0
    return 180.0 if normalized == -180.0 else normalized


def vrpn_timestamp_ms(message: dict[str, Any]) -> int:
    raw_time = message.get("time")
    if isinstance(raw_time, dict):
        try:
            tv_sec = float(raw_time.get("tv_sec", 0))
            tv_usec = float(raw_time.get("tv_usec", 0))
        except (TypeError, ValueError):
            return int(time.time() * 1000)
        return int(tv_sec * 1000) + int(tv_usec / 1000)
    if isinstance(raw_time, (int, float)):
        return int(float(raw_time) * 1000)
    return int(time.time() * 1000)


def pose_from_components(
    position: Sequence[float],
    quaternion: Sequence[float],
    config: BridgeConfig,
    *,
    timestamp_ms: int | None = None,
) -> TrackerPose:
    if len(position) < 3:
        raise ValueError("position must contain at least 3 values")
    if len(quaternion) < 4:
        raise ValueError("quaternion must contain at least 4 values")

    yaw = yaw_from_quaternion(
        (
            float(quaternion[0]),
            float(quaternion[1]),
            float(quaternion[2]),
            float(quaternion[3]),
        )
    )
    if config.invert_yaw:
        yaw = -yaw
    return TrackerPose(
        timestamp_ms=timestamp_ms or int(time.time() * 1000),
        x=round(float(position[0]), 3),
        y=round(float(position[1]), 3),
        z=round(float(position[2]) + config.z_offset, 3),
        yaw=round(normalize_yaw(yaw), 3),
    )


def pose_from_vrpn_message(message: dict[str, Any], config: BridgeConfig) -> TrackerPose:
    position = message.get("position")
    quaternion = message.get("quaternion")
    if not isinstance(position, (list, tuple)) or len(position) < 3:
        raise ValueError("VRPN pose message has no position[3]")
    if not isinstance(quaternion, (list, tuple)) or len(quaternion) < 4:
        raise ValueError("VRPN pose message has no quaternion[4]")
    return pose_from_components(
        position,
        quaternion,
        config,
        timestamp_ms=vrpn_timestamp_ms(message),
    )
