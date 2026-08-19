#!/usr/bin/env bash
# (Re)configure temperature reporting (0.2°C / 30s min / 1h max) on an
# already-paired SNZB-02P. Usage (from the Mac):
#   ./scripts/configure-sensor.sh kitchen_sensor
# Sleepy device: SHORT-press its button at each prompt (long-press factory-resets!).
set -euo pipefail
NAME=${1:?usage: configure-sensor.sh <friendly_name>}

ssh -T andrew@home-ops.local bash -s -- "$NAME" <<'REMOTE'
set -euo pipefail
NAME=$1
PUB() { docker exec mosquitto mosquitto_pub -t "$1" -m "$2"; }

echo ">> Configuring reporting on $NAME (repChange 0.2°C / 30s / 1h)."
echo ">> SHORT-press the sensor button once NOW, and again at each retry line."
OK=""
for i in $(seq 1 12); do
  docker exec mosquitto mosquitto_sub -t zigbee2mqtt/bridge/response/device/configure_reporting -W 13 -C 1 >/tmp/cfg_resp 2>/dev/null &
  SUBPID=$!
  sleep 1
  PUB zigbee2mqtt/bridge/request/device/configure_reporting \
    "{\"id\":\"$NAME\",\"endpoint\":1,\"cluster\":\"msTemperatureMeasurement\",\"attribute\":\"measuredValue\",\"minimum_report_interval\":30,\"maximum_report_interval\":3600,\"reportable_change\":20}"
  wait $SUBPID || true
  STATUS=$(python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("status",""))
except Exception: pass' </tmp/cfg_resp)
  if [ "$STATUS" = ok ]; then OK=1; echo "   configure_reporting: OK"; break; fi
  echo "   attempt $i/12 timed out — SHORT-press the button and hold on..."
done
[ -n "$OK" ] || { echo "!! configure_reporting never acked — re-run this script."; exit 1; }
echo ">> Done: $NAME configured."
REMOTE
