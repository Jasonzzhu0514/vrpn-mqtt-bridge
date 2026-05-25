#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PREFIX="${HOME}/.local/opt/vrpn-mqtt-bridge"
CONFIG_DIR="${HOME}/.config/vrpn-mqtt-bridge"
CONFIG_FILE="${CONFIG_DIR}/vrpn-mqtt-bridge.env"
SOURCE_ENV_FILE="${REPO_DIR}/examples/native-vrpn.env"
BUILD_FIRST=0
RUN_PREFLIGHT=1
INSTALL_SYSTEMD=0
START_SERVICE=0
BRIDGE_SRC="${REPO_DIR}/native/vrpn_mqtt_bridge/build/vrpn-mqtt-bridge"

usage() {
  cat <<'USAGE'
Usage: scripts/deploy.sh [options]

Install the C++ VRPN-to-MQTT bridge and optionally configure a user-level
systemd service.

Options:
  --prefix DIR          Install location (default: ~/.local/opt/vrpn-mqtt-bridge)
  --config-file FILE    Runtime env file (default: ~/.config/vrpn-mqtt-bridge/vrpn-mqtt-bridge.env)
  --env-file FILE       Env template to copy when config file does not exist
  --build               Run scripts/build.sh before installing
  --bridge-bin FILE     Install this prebuilt vrpn-mqtt-bridge binary
  --no-preflight        Skip runtime prerequisite checks
  --install-systemd     Install ~/.config/systemd/user/vrpn-mqtt-bridge.service
  --start               Enable and start the user service after installing it
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
      CONFIG_DIR="$(dirname "$CONFIG_FILE")"
      shift 2
      ;;
    --env-file)
      SOURCE_ENV_FILE="$2"
      shift 2
      ;;
    --build)
      BUILD_FIRST=1
      shift
      ;;
    --bridge-bin)
      BRIDGE_SRC="$2"
      shift 2
      ;;
    --no-preflight)
      RUN_PREFLIGHT=0
      shift
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

if [[ ! -f "${SOURCE_ENV_FILE}" ]]; then
  echo "env template not found: ${SOURCE_ENV_FILE}" >&2
  exit 2
fi

if [[ "${BUILD_FIRST}" -eq 1 ]]; then
  "${REPO_DIR}/scripts/build.sh"
fi

if [[ ! -x "${BRIDGE_SRC}" ]]; then
  echo "bridge binary not found or not executable: ${BRIDGE_SRC}" >&2
  echo "Run scripts/build.sh first, or pass --bridge-bin FILE." >&2
  exit 1
fi

mkdir -p "${PREFIX}/bin" "${CONFIG_DIR}"
COMMAND_PATH="${PREFIX}/bin/vrpn-mqtt-bridge"
cp "${BRIDGE_SRC}" "${COMMAND_PATH}"
chmod +x "${COMMAND_PATH}"
echo "installed command: ${COMMAND_PATH}"

if [[ ! -f "${CONFIG_FILE}" ]]; then
  cp "${SOURCE_ENV_FILE}" "${CONFIG_FILE}"
  echo "created config: ${CONFIG_FILE}"
else
  echo "kept existing config: ${CONFIG_FILE}"
fi

if [[ "${RUN_PREFLIGHT}" -eq 1 ]]; then
  "${REPO_DIR}/scripts/preflight.sh" --env-file "${CONFIG_FILE}" --command "${COMMAND_PATH}"
fi

if [[ "${INSTALL_SYSTEMD}" -eq 1 ]]; then
  SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
  SERVICE_FILE="${SYSTEMD_USER_DIR}/vrpn-mqtt-bridge.service"
  mkdir -p "${SYSTEMD_USER_DIR}"
  cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=VRPN to MQTT bridge
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=${CONFIG_FILE}
ExecStart=${COMMAND_PATH}
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload
  echo "installed user service: ${SERVICE_FILE}"
  if [[ "${START_SERVICE}" -eq 1 ]]; then
    systemctl --user enable --now vrpn-mqtt-bridge.service
    echo "started user service: vrpn-mqtt-bridge.service"
  fi
fi

cat <<EOF
Installed VRPN MQTT Bridge
  prefix: ${PREFIX}
  command: ${COMMAND_PATH}
  config: ${CONFIG_FILE}

Run:
  ${COMMAND_PATH} --env-file ${CONFIG_FILE}
EOF
