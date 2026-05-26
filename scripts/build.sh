#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_DIR="${REPO_DIR}/native/vrpn_mqtt_bridge"
BUILD_DIR="${REPO_DIR}/native/vrpn_mqtt_bridge/build"
CLEAN=0

usage() {
  cat <<'USAGE'
Usage: scripts/build.sh [options]

Build the C++ VRPN-to-MQTT bridge.

Options:
  --build-dir DIR   CMake build directory (default: native/vrpn_mqtt_bridge/build)
  --clean           Remove the build directory before configuring
  -h, --help        Show this help

Environment:
  BUILD_JOBS        Parallel build jobs (default: 2)
USAGE
}

remove_build_dir() {
  rm -rf "${BUILD_DIR}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-dir)
      if [[ $# -lt 2 ]]; then
        echo "--build-dir requires a value" >&2
        usage >&2
        exit 2
      fi
      BUILD_DIR="$2"
      shift 2
      ;;
    --clean)
      CLEAN=1
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

if [[ "${BUILD_DIR}" != /* ]]; then
  BUILD_DIR="${REPO_DIR}/${BUILD_DIR}"
fi

if command -v realpath >/dev/null 2>&1; then
  BUILD_DIR="$(realpath -m "${BUILD_DIR}")"
else
  BUILD_DIR="$(cd "$(dirname "${BUILD_DIR}")" && pwd -P)/$(basename "${BUILD_DIR}")"
fi

if [[ -z "${BUILD_DIR}" || "${BUILD_DIR}" == "/" || "${BUILD_DIR}" == "${REPO_DIR}" || "${BUILD_DIR}" == "${SOURCE_DIR}" ]]; then
  echo "refusing unsafe build directory: ${BUILD_DIR}" >&2
  exit 1
fi

if ! command -v cmake >/dev/null 2>&1; then
  echo "cmake not found" >&2
  exit 1
fi

if [[ "${CLEAN}" -eq 1 ]]; then
  remove_build_dir
elif [[ -f "${BUILD_DIR}/CMakeCache.txt" ]]; then
  cached_source="$(sed -n 's/^vrpn_mqtt_bridge_SOURCE_DIR:STATIC=//p; s/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' "${BUILD_DIR}/CMakeCache.txt" | head -n 1)"
  if [[ -n "${cached_source}" && "${cached_source}" != "${SOURCE_DIR}" ]]; then
    echo "Removing stale CMake build directory:"
    echo "  cached source: ${cached_source}"
    echo "  current source: ${SOURCE_DIR}"
    remove_build_dir
  fi
fi

cmake -S "${SOURCE_DIR}" -B "${BUILD_DIR}" -DCMAKE_BUILD_TYPE=Release
cmake --build "${BUILD_DIR}" --parallel "${BUILD_JOBS:-2}"

echo "Built:"
echo "  ${BUILD_DIR}/vrpn-mqtt-bridge"
