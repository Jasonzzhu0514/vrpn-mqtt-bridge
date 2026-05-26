#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/install-deps.sh [options]

Install build dependencies for vrpn-mqtt-bridge on apt-based Linux systems.

Options:
  --no-sudo    Run apt commands without sudo
  -h, --help   Show this help
USAGE
}

USE_SUDO=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-sudo)
      USE_SUDO=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v apt-get >/dev/null 2>&1; then
  cat >&2 <<'MSG'
apt-get not found.
Install these dependencies with your system package manager:
  cmake
  C++17 compiler
  vrpn_Tracker.h
  vrpn_Connection.h
  libvrpn
  libquat
MSG
  exit 1
fi

SUDO=()
if [[ "${USE_SUDO}" -eq 1 && "${EUID}" -ne 0 ]]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo not found; rerun as root or pass --no-sudo if apt is already permitted" >&2
    exit 1
  fi
  SUDO=(sudo)
fi

PACKAGES=(
  build-essential
  cmake
  pkg-config
  libvrpn-dev
)

"${SUDO[@]}" apt-get update
"${SUDO[@]}" apt-get install -y "${PACKAGES[@]}"

missing=0
for header in /usr/include/vrpn_Tracker.h /usr/include/vrpn_Connection.h; do
  if [[ ! -f "${header}" ]]; then
    echo "missing header after install: ${header}" >&2
    missing=1
  fi
done

if ! ldconfig -p 2>/dev/null | grep -q 'libvrpn'; then
  echo "warning: libvrpn was not found in ldconfig cache" >&2
fi

if ! ldconfig -p 2>/dev/null | grep -q 'libquat'; then
  echo "warning: libquat was not found in ldconfig cache" >&2
fi

if [[ "${missing}" -ne 0 ]]; then
  echo "dependency install finished, but required VRPN headers were not found" >&2
  exit 1
fi

echo "Dependencies installed."
