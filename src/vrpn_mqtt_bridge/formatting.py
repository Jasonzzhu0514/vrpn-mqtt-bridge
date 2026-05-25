"""Terminal formatting helpers."""

from __future__ import annotations

import time
from typing import Any


def format_local_time(timestamp_ms: int) -> str:
    seconds = timestamp_ms / 1000.0
    return time.strftime("%H:%M:%S", time.localtime(seconds)) + f".{timestamp_ms % 1000:03d}"


def format_signed_float(value: Any, *, width: int = 9, precision: int = 3) -> str:
    try:
        return f"{float(value):+{width}.{precision}f}"
    except (TypeError, ValueError):
        return f"{'nan':>{width}}"


def truncate_text(value: str, width: int) -> str:
    if len(value) <= width:
        return value
    if width <= 3:
        return value[:width]
    return value[: width - 3] + "..."
