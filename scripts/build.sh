#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${REPO_DIR}/native/vrpn_mqtt_bridge/build"

usage() {
  cat <<'USAGE'
Usage: scripts/build.sh [options]

Build the C++ VRPN-to-MQTT bridge.

Options:
  --build-dir DIR   CMake build directory (default: native/vrpn_mqtt_bridge/build)
  -h, --help        Show this help

Environment:
  BUILD_JOBS        Parallel build jobs (default: 2)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-dir)
      BUILD_DIR="$2"
      shift 2
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

if ! command -v cmake >/dev/null 2>&1; then
  echo "cmake not found" >&2
  exit 1
fi

cmake -S "${REPO_DIR}/native/vrpn_mqtt_bridge" -B "${BUILD_DIR}" -DCMAKE_BUILD_TYPE=Release
cmake --build "${BUILD_DIR}" --parallel "${BUILD_JOBS:-2}"

echo "Built:"
echo "  ${BUILD_DIR}/vrpn-mqtt-bridge"
