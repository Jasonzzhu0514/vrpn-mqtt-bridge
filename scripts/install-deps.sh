#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/install-deps.sh [options]

Install build dependencies for vrpn-mqtt-bridge.

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

if command -v apt-get >/dev/null 2>&1; then
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
elif command -v brew >/dev/null 2>&1; then
  brew install cmake vrpn
else
  cat >&2 <<'MSG'
No supported package manager was found.
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

missing=0
if ! find /usr/include /usr/local/include /opt/homebrew/include /opt/homebrew/opt/vrpn/include /usr/local/opt/vrpn/include /opt/local/include \
    -name vrpn_Tracker.h -print -quit 2>/dev/null | grep -q .; then
  echo "warning: vrpn_Tracker.h was not found in common include paths" >&2
  missing=1
fi

if command -v ldconfig >/dev/null 2>&1 && ! ldconfig -p 2>/dev/null | grep -q 'libvrpn'; then
  echo "warning: libvrpn was not found in ldconfig cache" >&2
fi

if command -v ldconfig >/dev/null 2>&1 && ! ldconfig -p 2>/dev/null | grep -q 'libquat'; then
  echo "warning: libquat was not found in ldconfig cache" >&2
fi

if [[ "${missing}" -ne 0 ]]; then
  echo "dependency install finished, but required VRPN headers were not found" >&2
  exit 1
fi

echo "Dependencies installed."
