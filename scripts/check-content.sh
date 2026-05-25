#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

FORBIDDEN=(
  "dji"
  "DJI"
  "Drone3Plot"
  "drone3plot"
  "yundrone"
  "10.168."
  "192.168."
  "uav"
  "UAV"
)

STATUS=0
for pattern in "${FORBIDDEN[@]}"; do
  if grep -RIn \
    --exclude-dir=.git \
    --exclude-dir=build \
    --exclude-dir=dist \
    --exclude=check-content.sh \
    -- "${pattern}" "${ROOT}" >/tmp/vrpn-mqtt-check-content.$$; then
    cat /tmp/vrpn-mqtt-check-content.$$
    STATUS=1
  fi
done

rm -f /tmp/vrpn-mqtt-check-content.$$
exit "${STATUS}"
