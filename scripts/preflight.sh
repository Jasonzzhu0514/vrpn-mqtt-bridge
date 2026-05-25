#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_DIR}/examples/native-vrpn.env"
PYTHON_BIN="${PYTHON:-python3}"
COMMAND_PATH=""

usage() {
  cat <<'USAGE'
Usage: scripts/preflight.sh [options]

Check runtime prerequisites and print the resolved VRPN endpoint.

Options:
  --env-file FILE       Env file to inspect
  --command PATH        Installed vrpn-mqtt-bridge command to test
  -h, --help            Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    --command)
      COMMAND_PATH="$2"
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

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "env file not found: ${ENV_FILE}" >&2
  exit 2
fi

set -a
# shellcheck disable=SC1090
. "${ENV_FILE}"
set +a

VRPN_SOURCE="${VRPN_SOURCE:-auto}"
VRPN_TRACKER="${VRPN_TRACKER:-tracker}"
VRPN_HOST="${VRPN_HOST:-127.0.0.1}"
VRPN_PORT="${VRPN_PORT:-3883}"
VRPN_ENDPOINT="${VRPN_ENDPOINT:-${VRPN_TRACKER}@${VRPN_HOST}:${VRPN_PORT}}"
VRPN_NATIVE_READER_BIN="${VRPN_NATIVE_READER_BIN:-${REPO_DIR}/native/vrpn_pose_reader/build/vrpn_pose_reader}"
VRPN_PRINT_DEVICES_BIN="${VRPN_PRINT_DEVICES_BIN:-vrpn_print_devices}"

echo "Preflight"
echo "  env: ${ENV_FILE}"
echo "  vrpn_endpoint: ${VRPN_ENDPOINT}"
echo "  vrpn_source: ${VRPN_SOURCE}"
echo "  mqtt: ${VRPN_MQTT_HOST:-localhost}:${VRPN_MQTT_PORT:-1883}"

if [[ "${VRPN_SOURCE}" == "native" || "${VRPN_SOURCE}" == "auto" ]]; then
  if command -v "${VRPN_NATIVE_READER_BIN}" >/dev/null 2>&1 || [[ -x "${VRPN_NATIVE_READER_BIN}" ]]; then
    echo "  vrpn_pose_reader: ok (${VRPN_NATIVE_READER_BIN})"
  elif command -v vrpn_pose_reader >/dev/null 2>&1; then
    echo "  vrpn_pose_reader: ok ($(command -v vrpn_pose_reader))"
  elif [[ "${VRPN_NATIVE_READER_BIN}" == "vrpn_pose_reader" && -x "${REPO_DIR}/native/vrpn_pose_reader/build/vrpn_pose_reader" ]]; then
    echo "  vrpn_pose_reader: ok (${REPO_DIR}/native/vrpn_pose_reader/build/vrpn_pose_reader)"
  else
    echo "  vrpn_pose_reader: missing (${VRPN_NATIVE_READER_BIN})" >&2
    echo "Run scripts/build.sh to build the native VRPN reader, or set VRPN_NATIVE_READER_BIN." >&2
    if [[ "${VRPN_SOURCE}" == "native" ]]; then
      exit 1
    fi
  fi
fi

if [[ "${VRPN_SOURCE}" == "cli" || "${VRPN_SOURCE}" == "auto" ]]; then
  if command -v "${VRPN_PRINT_DEVICES_BIN}" >/dev/null 2>&1 || [[ -x "${VRPN_PRINT_DEVICES_BIN}" ]]; then
    echo "  vrpn_print_devices: ok (${VRPN_PRINT_DEVICES_BIN})"
  else
    echo "  vrpn_print_devices: missing (${VRPN_PRINT_DEVICES_BIN})" >&2
    echo "Install a VRPN/ROS package that provides vrpn_print_devices, or set VRPN_PRINT_DEVICES_BIN." >&2
    if [[ "${VRPN_SOURCE}" == "cli" ]]; then
      exit 1
    fi
  fi
fi

if [[ -n "${COMMAND_PATH}" ]]; then
  if [[ ! -x "${COMMAND_PATH}" ]]; then
    echo "installed command is not executable: ${COMMAND_PATH}" >&2
    exit 1
  fi
  "${COMMAND_PATH}" --env-file "${ENV_FILE}" --dry-run --quiet --help >/dev/null
  echo "  command: ok (${COMMAND_PATH})"
else
  PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="${REPO_DIR}/src" "${PYTHON_BIN}" -m vrpn_mqtt_bridge.cli --env-file "${ENV_FILE}" --dry-run --quiet --help >/dev/null
  echo "  package import: ok"
fi
