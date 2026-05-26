#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PREFIX="${HOME}/.local/opt/vrpn-mqtt-bridge"
CONFIG_FILE="${HOME}/.config/vrpn-mqtt-bridge/vrpn-mqtt-bridge.env"
ENV_FILE="${REPO_DIR}/examples/default.env"
INSTALL_DEPS=0

usage() {
  cat <<'USAGE'
Usage: scripts/deploy-vrpn-mqtt.sh [options]

Build and install the C++ VRPN-to-MQTT bridge.

Options:
  --prefix DIR          Install location
  --config-file FILE    Runtime env file
  --env-file FILE       Env template to deploy
  --install-deps        Install build dependencies with scripts/install-deps.sh
  -h, --help            Show this help
USAGE
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      require_value "$1" "${2-}"
      PREFIX="$2"
      shift 2
      ;;
    --config-file)
      require_value "$1" "${2-}"
      CONFIG_FILE="$2"
      shift 2
      ;;
    --env-file)
      require_value "$1" "${2-}"
      ENV_FILE="$2"
      shift 2
      ;;
    --install-deps)
      INSTALL_DEPS=1
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

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "env template not found: ${ENV_FILE}" >&2
  exit 2
fi

if [[ "${INSTALL_DEPS}" -eq 1 ]]; then
  "${REPO_DIR}/scripts/install-deps.sh"
fi

"${REPO_DIR}/scripts/build.sh"

BRIDGE_BIN="${REPO_DIR}/native/vrpn_mqtt_bridge/build/vrpn-mqtt-bridge"
COMMAND_PATH="${PREFIX}/bin/vrpn-mqtt-bridge"

if [[ ! -x "${BRIDGE_BIN}" ]]; then
  echo "bridge binary not found or not executable: ${BRIDGE_BIN}" >&2
  exit 1
fi

mkdir -p "$(dirname "${COMMAND_PATH}")" "$(dirname "${CONFIG_FILE}")"
cp "${BRIDGE_BIN}" "${COMMAND_PATH}"
chmod +x "${COMMAND_PATH}"

if [[ ! -f "${CONFIG_FILE}" ]]; then
  cp "${ENV_FILE}" "${CONFIG_FILE}"
fi

"${COMMAND_PATH}" --env-file "${CONFIG_FILE}" --vrpn-only --quiet --help >/dev/null

cat <<EOF
Installed VRPN MQTT Bridge
  command: ${COMMAND_PATH}
  config: ${CONFIG_FILE}
  run: ${COMMAND_PATH} --env-file ${CONFIG_FILE}
EOF
