#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PREFIX="${HOME}/.local/opt/vrpn-mqtt-bridge"
CONFIG_DIR="${HOME}/.config/vrpn-mqtt-bridge"
CONFIG_FILE="${CONFIG_DIR}/vrpn-mqtt-bridge.env"
SOURCE_ENV_FILE="${REPO_DIR}/examples/default.env"
INSTALL_SYSTEMD=0
START_SERVICE=0
COMMAND_PATH=""
NATIVE_READER_SRC="${REPO_DIR}/native/vrpn_pose_reader/build/vrpn_pose_reader"
NATIVE_READER_PATH=""
BUILD_FIRST=0
WHEEL_FILE=""
RUN_PREFLIGHT=1

usage() {
  cat <<'USAGE'
Usage: scripts/deploy.sh [options]

Install this repo into a Python virtual environment and optionally configure a
user-level systemd service.

Options:
  --prefix DIR          Install location (default: ~/.local/opt/vrpn-mqtt-bridge)
  --config-file FILE    Runtime env file (default: ~/.config/vrpn-mqtt-bridge/vrpn-mqtt-bridge.env)
  --env-file FILE       Env template to copy when config file does not exist
  --build               Run scripts/build.sh before installing
  --wheel FILE          Install a prebuilt wheel instead of the source tree
  --native-reader FILE  Install this vrpn_pose_reader binary with the bridge
  --no-preflight        Skip runtime prerequisite checks
  --install-systemd     Install ~/.config/systemd/user/vrpn-mqtt-bridge.service
  --start               Enable and start the user service after installing it
  -h, --help            Show this help

Examples:
  scripts/deploy.sh
  scripts/deploy.sh --build
  scripts/deploy.sh --wheel dist/vrpn_mqtt_bridge-0.1.0-py3-none-any.whl
  scripts/deploy.sh --env-file examples/legacy-slam.env
  scripts/deploy.sh --env-file examples/native-vrpn.env
  scripts/deploy.sh --install-systemd --start
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
    --wheel)
      WHEEL_FILE="$2"
      shift 2
      ;;
    --native-reader)
      NATIVE_READER_SRC="$2"
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

if [[ "${RUN_PREFLIGHT}" -eq 1 ]]; then
  "${REPO_DIR}/scripts/preflight.sh" --env-file "${SOURCE_ENV_FILE}"
fi

PYTHON_BIN="${PYTHON:-python3}"
if ! command -v "${PYTHON_BIN}" >/dev/null 2>&1; then
  echo "python executable not found: ${PYTHON_BIN}" >&2
  exit 1
fi

mkdir -p "${PREFIX}" "${CONFIG_DIR}"

if [[ "${BUILD_FIRST}" -eq 1 ]]; then
  "${REPO_DIR}/scripts/build.sh"
  if [[ -z "${WHEEL_FILE}" ]]; then
    WHEEL_FILE="$(find "${REPO_DIR}/dist" -maxdepth 1 -name '*.whl' | sort | tail -n 1)"
  fi
fi

INSTALL_TARGET="${REPO_DIR}"
if [[ -n "${WHEEL_FILE}" ]]; then
  if [[ ! -f "${WHEEL_FILE}" ]]; then
    echo "wheel not found: ${WHEEL_FILE}" >&2
    exit 2
  fi
  INSTALL_TARGET="${WHEEL_FILE}"
fi

if "${PYTHON_BIN}" - <<'PY' >/dev/null 2>&1
import ensurepip  # noqa: F401
import venv  # noqa: F401
PY
then
  "${PYTHON_BIN}" -m venv "${PREFIX}/.venv"
  "${PREFIX}/.venv/bin/python" -m pip install --upgrade pip
  "${PREFIX}/.venv/bin/python" -m pip install "${INSTALL_TARGET}"
  COMMAND_PATH="${PREFIX}/.venv/bin/vrpn-mqtt-bridge"
else
  echo "python venv/ensurepip is unavailable; falling back to --target install" >&2
  if ! "${PYTHON_BIN}" -m pip --version >/dev/null 2>&1; then
    echo "pip is required for fallback install. Install python3-venv or python3-pip first." >&2
    exit 1
  fi
  rm -rf "${PREFIX}/python"
  mkdir -p "${PREFIX}/python" "${PREFIX}/bin"
  "${PYTHON_BIN}" -m pip install --upgrade --target "${PREFIX}/python" "${INSTALL_TARGET}"
  cat > "${PREFIX}/bin/vrpn-mqtt-bridge" <<EOF
#!/usr/bin/env bash
export PYTHONPATH="${PREFIX}/python:\${PYTHONPATH:-}"
exec "${PYTHON_BIN}" -m vrpn_mqtt_bridge.cli "\$@"
EOF
  chmod +x "${PREFIX}/bin/vrpn-mqtt-bridge"
  COMMAND_PATH="${PREFIX}/bin/vrpn-mqtt-bridge"
fi

mkdir -p "${PREFIX}/bin"
if [[ -x "${NATIVE_READER_SRC}" ]]; then
  cp "${NATIVE_READER_SRC}" "${PREFIX}/bin/vrpn_pose_reader"
  chmod +x "${PREFIX}/bin/vrpn_pose_reader"
  NATIVE_READER_PATH="${PREFIX}/bin/vrpn_pose_reader"
  echo "installed native VRPN reader: ${NATIVE_READER_PATH}"
elif command -v vrpn_pose_reader >/dev/null 2>&1; then
  NATIVE_READER_PATH="$(command -v vrpn_pose_reader)"
  echo "using existing native VRPN reader: ${NATIVE_READER_PATH}"
fi

if [[ ! -f "${CONFIG_FILE}" ]]; then
  cp "${SOURCE_ENV_FILE}" "${CONFIG_FILE}"
  if [[ -n "${NATIVE_READER_PATH}" ]] && ! grep -q '^VRPN_NATIVE_READER_BIN=' "${CONFIG_FILE}"; then
    printf '\nVRPN_NATIVE_READER_BIN=%s\n' "${NATIVE_READER_PATH}" >> "${CONFIG_FILE}"
  fi
  if [[ -n "${NATIVE_READER_PATH}" ]]; then
    sed -i "s#^VRPN_NATIVE_READER_BIN=.*#VRPN_NATIVE_READER_BIN=${NATIVE_READER_PATH}#" "${CONFIG_FILE}"
  fi
  echo "created config: ${CONFIG_FILE}"
else
  if [[ -n "${NATIVE_READER_PATH}" ]] && ! grep -q '^VRPN_NATIVE_READER_BIN=' "${CONFIG_FILE}"; then
    printf '\nVRPN_NATIVE_READER_BIN=%s\n' "${NATIVE_READER_PATH}" >> "${CONFIG_FILE}"
    echo "added VRPN_NATIVE_READER_BIN to config: ${NATIVE_READER_PATH}"
  elif [[ -n "${NATIVE_READER_PATH}" ]]; then
    sed -i "s#^VRPN_NATIVE_READER_BIN=.*#VRPN_NATIVE_READER_BIN=${NATIVE_READER_PATH}#" "${CONFIG_FILE}"
    echo "updated VRPN_NATIVE_READER_BIN in config: ${NATIVE_READER_PATH}"
  fi
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

Edit the config file, then run:
  ${COMMAND_PATH} --env-file ${CONFIG_FILE}
EOF
