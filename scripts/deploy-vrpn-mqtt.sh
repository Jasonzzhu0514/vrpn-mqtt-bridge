#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PREFIX="${HOME}/.local/opt/vrpn-mqtt-bridge"
CONFIG_FILE="${HOME}/.config/vrpn-mqtt-bridge/vrpn-mqtt-bridge.env"
ENV_FILE="${REPO_DIR}/examples/native-vrpn.env"
INSTALL_SYSTEMD=0
START_SERVICE=0

usage() {
  cat <<'USAGE'
Usage: scripts/deploy-vrpn-mqtt.sh [options]

One-command build + deploy flow for the C++ VRPN-to-MQTT bridge.

Options:
  --prefix DIR          Install location
  --config-file FILE    Runtime env file
  --env-file FILE       Env template to deploy
  --install-systemd     Install user-level systemd service
  --start               Enable and start the user service
  -h, --help            Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      PREFIX="$2"
      shift 2
      ;;
    --config-file)
      CONFIG_FILE="$2"
      shift 2
      ;;
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    --install-systemd)
      INSTALL_SYSTEMD=1
      shift
      ;;
    --start)
      START_SERVICE=1
      INSTALL_SYSTEMD=1
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

"${REPO_DIR}/scripts/build.sh"

DEPLOY_ARGS=(
  --bridge-bin "${REPO_DIR}/native/vrpn_mqtt_bridge/build/vrpn-mqtt-bridge"
  --env-file "${ENV_FILE}"
  --prefix "${PREFIX}"
  --config-file "${CONFIG_FILE}"
)

if [[ "${INSTALL_SYSTEMD}" -eq 1 ]]; then
  DEPLOY_ARGS+=(--install-systemd)
fi
if [[ "${START_SERVICE}" -eq 1 ]]; then
  DEPLOY_ARGS+=(--start)
fi

"${REPO_DIR}/scripts/deploy.sh" "${DEPLOY_ARGS[@]}"

COMMAND_PATH="${PREFIX}/bin/vrpn-mqtt-bridge"
"${REPO_DIR}/scripts/preflight.sh" --env-file "${CONFIG_FILE}" --command "${COMMAND_PATH}"

cat <<EOF

Deployment complete.

Run manually:
  ${COMMAND_PATH} --env-file ${CONFIG_FILE}
EOF
