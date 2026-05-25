"""Small environment-file loader used by the CLI and deploy script."""

from __future__ import annotations

import os
from pathlib import Path


def load_env_file(path: str | os.PathLike[str], *, override: bool = False) -> None:
    """Load KEY=VALUE pairs from a dotenv-like file into ``os.environ``.

    The parser intentionally supports only the simple format needed for
    deployment files: comments, blank lines, optional ``export``, and quoted or
    unquoted scalar values.
    """

    env_path = Path(path).expanduser()
    if not env_path.exists():
        raise FileNotFoundError(f"env file not found: {env_path}")

    for line_number, raw_line in enumerate(env_path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export ") :].strip()
        key, separator, value = line.partition("=")
        if not separator:
            raise ValueError(f"{env_path}:{line_number}: expected KEY=VALUE")
        key = key.strip()
        if not key:
            raise ValueError(f"{env_path}:{line_number}: empty environment key")
        if not override and key in os.environ:
            continue
        os.environ[key] = _strip_env_value(value.strip())


def _strip_env_value(value: str) -> str:
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1]
    return value
