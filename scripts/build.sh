#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PYTHON_BIN="${PYTHON:-python3}"
SKIP_TESTS=0
SKIP_NATIVE=0
REQUIRE_NATIVE=0
OUT_DIR="${REPO_DIR}/dist"
NATIVE_BUILD_DIR="${REPO_DIR}/native/vrpn_pose_reader/build"
BUILD_TOOL_DIR=""
BACKEND_DIR=""

usage() {
  cat <<'USAGE'
Usage: scripts/build.sh [options]

Run tests and build the native VRPN helper, wheel, and source distribution.

Options:
  --skip-tests      Build packages without running pytest first
  --skip-native     Skip the native vrpn_pose_reader build
  --require-native  Fail if the native vrpn_pose_reader cannot be built
  --out-dir DIR     Output directory for packages (default: ./dist)
  -h, --help        Show this help

Environment:
  PYTHON            Python executable to use (default: python3)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-tests)
      SKIP_TESTS=1
      shift
      ;;
    --skip-native)
      SKIP_NATIVE=1
      shift
      ;;
    --require-native)
      REQUIRE_NATIVE=1
      shift
      ;;
    --out-dir)
      OUT_DIR="$2"
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

if ! command -v "${PYTHON_BIN}" >/dev/null 2>&1; then
  echo "python executable not found: ${PYTHON_BIN}" >&2
  exit 1
fi

cleanup() {
  if [[ -n "${BUILD_TOOL_DIR}" ]]; then
    rm -rf "${BUILD_TOOL_DIR}"
  fi
  if [[ -n "${BACKEND_DIR}" ]]; then
    rm -rf "${BACKEND_DIR}"
  fi
}
trap cleanup EXIT

cd "${REPO_DIR}"

if [[ "${SKIP_TESTS}" -eq 0 ]]; then
  PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=src "${PYTHON_BIN}" -m pytest -q -p no:cacheprovider
fi

if [[ "${SKIP_NATIVE}" -eq 0 ]]; then
  if command -v cmake >/dev/null 2>&1; then
    if cmake -S "${REPO_DIR}/native/vrpn_pose_reader" -B "${NATIVE_BUILD_DIR}" -DCMAKE_BUILD_TYPE=Release; then
      cmake --build "${NATIVE_BUILD_DIR}" --parallel "${BUILD_JOBS:-2}"
    else
      echo "native vrpn_pose_reader configure failed; install VRPN development files or use --skip-native" >&2
      if [[ "${REQUIRE_NATIVE}" -eq 1 ]]; then
        exit 1
      fi
    fi
  else
    echo "cmake not found; skipping native vrpn_pose_reader build" >&2
    if [[ "${REQUIRE_NATIVE}" -eq 1 ]]; then
      exit 1
    fi
  fi
fi

BUILD_TOOL_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vrpn-mqtt-build-tool.XXXXXX")"
BACKEND_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vrpn-mqtt-build-backend.XXXXXX")"

"${PYTHON_BIN}" -m pip install --quiet --no-warn-conflicts --target "${BUILD_TOOL_DIR}" build
"${PYTHON_BIN}" -m pip install --quiet --no-warn-conflicts --target "${BACKEND_DIR}" 'setuptools>=61' wheel

rm -rf "${OUT_DIR}" build src/vrpn_mqtt_bridge.egg-info
mkdir -p "${OUT_DIR}"
PYTHONDONTWRITEBYTECODE=1 \
PYTHONPATH="${BUILD_TOOL_DIR}:${BACKEND_DIR}" \
  "${PYTHON_BIN}" -m build --no-isolation --sdist --wheel --outdir "${OUT_DIR}"

rm -rf build src/vrpn_mqtt_bridge.egg-info
find . -name '__pycache__' -type d -prune -exec rm -rf {} +
rm -rf .pytest_cache

echo "Built packages:"
find "${OUT_DIR}" -maxdepth 1 -type f -printf '  %f\n' | sort
if [[ -x "${NATIVE_BUILD_DIR}/vrpn_pose_reader" ]]; then
  echo "Built native helper:"
  echo "  native/vrpn_pose_reader/build/vrpn_pose_reader"
fi
