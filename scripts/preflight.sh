#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_DIR}/examples/native-vrpn.env"
COMMAND_PATH="${REPO_DIR}/native/vrpn_mqtt_bridge/build/vrpn-mqtt-bridge"

usage() {
  cat <<'USAGE'
Usage: scripts/preflight.sh [options]

Check runtime config and the C++ bridge binary.

Options:
  --env-file FILE       Env file to inspect
  --command PATH        vrpn-mqtt-bridge command to test
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

VRPN_TRACKER="${VRPN_TRACKER:-tracker0}"
VRPN_HOST="${VRPN_HOST:-127.0.0.1}"
VRPN_PORT="${VRPN_PORT:-3883}"
VRPN_ENDPOINT="${VRPN_ENDPOINT:-${VRPN_TRACKER}@${VRPN_HOST}:${VRPN_PORT}}"
VRPN_MQTT_HOST="${VRPN_MQTT_HOST:-localhost}"
VRPN_MQTT_PORT="${VRPN_MQTT_PORT:-1883}"

if [[ "${VRPN_ENDPOINT}" == *"@"* ]]; then
  VRPN_TRACKER="${VRPN_ENDPOINT%@*}"
  VRPN_SERVER="${VRPN_ENDPOINT#*@}"
  if [[ "${VRPN_SERVER}" == *":"* ]]; then
    VRPN_HOST="${VRPN_SERVER%:*}"
    VRPN_PORT="${VRPN_SERVER##*:}"
  else
    VRPN_HOST="${VRPN_SERVER}"
  fi
fi

echo "Preflight"
echo "  env: ${ENV_FILE}"
echo "  command: ${COMMAND_PATH}"
echo "  vrpn_tracker: ${VRPN_TRACKER}"
echo "  vrpn_server: ${VRPN_HOST}:${VRPN_PORT}"
echo "  mqtt: ${VRPN_MQTT_HOST}:${VRPN_MQTT_PORT}"

if [[ ! -x "${COMMAND_PATH}" ]]; then
  echo "command is not executable: ${COMMAND_PATH}" >&2
  exit 1
fi

"${COMMAND_PATH}" --env-file "${ENV_FILE}" --dry-run --quiet --help >/dev/null
echo "  command: ok"
