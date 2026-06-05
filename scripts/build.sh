#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_DIR="${REPO_DIR}/native/vrpn_mqtt_bridge"
BUILD_DIR="${REPO_DIR}/native/vrpn_mqtt_bridge/build"
CLEAN=0
AUTO_INSTALL_DEPS=1
CMAKE_ONLY=0
EXTRA_CMAKE_ARGS=()

usage() {
  cat <<'USAGE'
Usage: scripts/build.sh [options]

Build the C++ VRPN-to-MQTT bridge.

Options:
  --build-dir DIR   CMake build directory (default: native/vrpn_mqtt_bridge/build)
  --cmake-arg ARG   Extra argument passed to cmake configure; can be repeated
  --cmake-only      Run cmake configure/build directly without dependency handling
  --clean           Remove the build directory before configuring
  --no-install-deps Do not auto-install missing cmake/VRPN dependencies
  -h, --help        Show this help

Environment:
  AUTO_INSTALL_DEPS Set to false/0/no to disable dependency auto-install
  BUILD_JOBS        Parallel build jobs (default: 2)
  CMAKE_ARGS        Extra cmake configure arguments
  VRPN_ROOT         VRPN install prefix used by native/cmake/FindVRPN.cmake
USAGE
}

remove_build_dir() {
  rm -rf "${BUILD_DIR}"
}

require_value() {
  local option="$1"
  local value="${2-}"
  if [[ -z "${value}" || "${value}" == -* ]]; then
    echo "${option} requires a value" >&2
    usage >&2
    exit 2
  fi
}

normalize_abs_path() {
  local path="$1"
  local part keep
  local -a parts normalized

  IFS='/' read -r -a parts <<<"${path}"
  for part in "${parts[@]}"; do
    case "${part}" in
      ""|".")
        ;;
      "..")
        if [[ "${#normalized[@]}" -gt 0 ]]; then
          keep=$((${#normalized[@]} - 1))
          normalized=("${normalized[@]:0:${keep}}")
        fi
        ;;
      *)
        normalized+=("${part}")
        ;;
    esac
  done

  if [[ "${#normalized[@]}" -eq 0 ]]; then
    printf '/'
  else
    printf '/%s' "${normalized[@]}"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-dir)
      require_value "$1" "${2-}"
      BUILD_DIR="$2"
      shift 2
      ;;
    --cmake-arg)
      require_value "$1" "${2-}"
      EXTRA_CMAKE_ARGS+=("$2")
      shift 2
      ;;
    --clean)
      CLEAN=1
      shift
      ;;
    --cmake-only)
      CMAKE_ONLY=1
      AUTO_INSTALL_DEPS=0
      shift
      ;;
    --no-install-deps)
      AUTO_INSTALL_DEPS=0
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

case "${AUTO_INSTALL_DEPS:-1}" in
  0|false|FALSE|no|NO)
    AUTO_INSTALL_DEPS=0
    ;;
  *)
    AUTO_INSTALL_DEPS=1
    ;;
esac

if [[ "${BUILD_DIR}" != /* ]]; then
  BUILD_DIR="${REPO_DIR}/${BUILD_DIR}"
fi

BUILD_DIR="$(normalize_abs_path "${BUILD_DIR}")"

if [[ -z "${BUILD_DIR}" || "${BUILD_DIR}" == "/" || "${BUILD_DIR}" == "${REPO_DIR}" || "${BUILD_DIR}" == "${SOURCE_DIR}" ]]; then
  echo "refusing unsafe build directory: ${BUILD_DIR}" >&2
  exit 1
fi

if ! command -v cmake >/dev/null 2>&1; then
  if [[ "${AUTO_INSTALL_DEPS}" -eq 1 ]]; then
    "${REPO_DIR}/scripts/install-deps.sh"
  fi
  if ! command -v cmake >/dev/null 2>&1; then
    echo "cmake not found; install cmake or rerun with dependency auto-install enabled" >&2
    exit 1
  fi
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

if [[ -n "${CMAKE_ARGS:-}" ]]; then
  read -r -a env_cmake_args <<<"${CMAKE_ARGS}"
  for arg in "${env_cmake_args[@]}"; do
    EXTRA_CMAKE_ARGS+=("${arg}")
  done
fi

mkdir -p "${BUILD_DIR}"
CONFIGURE_LOG="${BUILD_DIR}/cmake-configure.log"

configure() {
  if [[ "${#EXTRA_CMAKE_ARGS[@]}" -gt 0 ]]; then
    cmake -S "${SOURCE_DIR}" -B "${BUILD_DIR}" -DCMAKE_BUILD_TYPE=Release "${EXTRA_CMAKE_ARGS[@]}" 2>&1 | tee "${CONFIGURE_LOG}"
  else
    cmake -S "${SOURCE_DIR}" -B "${BUILD_DIR}" -DCMAKE_BUILD_TYPE=Release 2>&1 | tee "${CONFIGURE_LOG}"
  fi
}

configure_failed_for_dependencies() {
  grep -Eqi 'Could NOT find VRPN|FindVRPN|VRPN.*not found|vrpn_Tracker\.h|libvrpn|libquat|CMAKE_CXX_COMPILER|No CMAKE_CXX_COMPILER|CXX compiler' "${CONFIGURE_LOG}"
}

if [[ "${CMAKE_ONLY}" -eq 1 ]]; then
  configure
elif ! configure; then
  if [[ "${AUTO_INSTALL_DEPS}" -ne 1 ]]; then
    echo "cmake configure failed; install missing dependencies or rerun without --no-install-deps" >&2
    exit 1
  fi
  if ! configure_failed_for_dependencies; then
    echo "cmake configure failed for a reason that does not look like missing dependencies; not running auto-install" >&2
    exit 1
  fi
  echo "cmake configure failed; installing build dependencies and retrying..."
  "${REPO_DIR}/scripts/install-deps.sh"
  configure
fi

cmake --build "${BUILD_DIR}" --parallel "${BUILD_JOBS:-2}"

echo "Built:"
echo "  ${BUILD_DIR}/vrpn-mqtt-bridge"
