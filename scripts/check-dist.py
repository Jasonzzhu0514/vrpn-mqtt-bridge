#!/usr/bin/env python3
"""Check source and wheel archives for stale site-specific values."""

from __future__ import annotations

import argparse
import tarfile
import zipfile
from pathlib import Path


DEFAULT_FORBIDDEN = (
    "dji",
    "DJI",
    "Drone3Plot",
    "drone3plot",
    "yundrone",
    "10.168.",
    "192.168.",
    "uav",
    "UAV",
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("archives", nargs="+", type=Path)
    parser.add_argument("--forbid", action="append", default=[])
    args = parser.parse_args()

    forbidden = tuple(DEFAULT_FORBIDDEN) + tuple(args.forbid)
    hits: list[str] = []
    for archive in args.archives:
        for name, data in iter_archive_text(archive):
            if name.endswith("scripts/check-dist.py"):
                continue
            for pattern in forbidden:
                if pattern in name or pattern in data:
                    hits.append(f"{archive}:{name}: {pattern}")

    if hits:
        print("forbidden archive content found:")
        for hit in hits:
            print(f"  {hit}")
        return 1
    return 0


def iter_archive_text(path: Path):
    if path.suffix == ".whl":
        with zipfile.ZipFile(path) as archive:
            for name in archive.namelist():
                if name.endswith("/"):
                    continue
                yield name, archive.read(name).decode("utf-8", errors="ignore")
        return

    if path.name.endswith(".tar.gz"):
        with tarfile.open(path, "r:gz") as archive:
            for member in archive.getmembers():
                if not member.isfile():
                    continue
                file_obj = archive.extractfile(member)
                if file_obj is None:
                    continue
                yield member.name, file_obj.read().decode("utf-8", errors="ignore")
        return

    raise ValueError(f"unsupported archive type: {path}")


if __name__ == "__main__":
    raise SystemExit(main())
