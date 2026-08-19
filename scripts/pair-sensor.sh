#!/usr/bin/env bash
# Pair one SNZB-02P and configure its temperature reporting (0.2°C / 30s min / 1h max).
# Usage (from the Mac):  ./scripts/pair-sensor.sh kitchen_sensor
#
# Automates the 2026-08-10 manual procedure: permit_join, wait for interview,
# rename, then loop configure_reporting until the sleepy device acks it
# (the ZDO bind times out in 10s unless the sensor is awake — short-press the
# button at each retry prompt; long-press factory-resets a paired sensor!).
set -euo pipefail
NAME=${1:?usage: pair-sensor.sh <friendly_name>}

ssh -T andrew@home-ops.local bash -s -- "$NAME" <<'REMOTE'
set -euo pipefail
NAME=$1
PUB() { docker exec mosquitto mosquitto_pub -t "$1" -m "$2"; }
SUB() { docker exec mosquitto mosquitto_sub -t "$1" -W "$2" -C 1 2>/dev/null || true; }
JGET() { python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit()
for k in sys.argv[1:]:
    d=d.get(k,{}) if isinstance(d,dict) else {}
print(d if not isinstance(d,dict) or d else "")' "$@"; }

echo ">> Enabling permit_join (250s)."
echo ">> LONG-press the NEW sensor's button (~5s) until its LED starts blinking."
PUB zigbee2mqtt/bridge/request/permit_join '{"time":250}'

ADDR=""
END=$((SECONDS+250))
while [ $SECONDS -lt $END ]; do
  EV=$(SUB zigbee2mqtt/bridge/event 30)
  [ -z "$EV" ] && { echo "   ...still waiting for join..."; continue; }
  TYPE=$(printf '%s' "$EV" | JGET type)
  case "$TYPE" in
    device_joined)
      echo "   Device joined, interviewing (takes ~10-30s)..." ;;
    device_interview)
      STATUS=$(printf '%s' "$EV" | JGET data status)
      if [ "$STATUS" = successful ]; then
        ADDR=$(printf '%s' "$EV" | JGET data ieee_address)
        MODEL=$(printf '%s' "$EV" | JGET data definition model)
        echo "   Interview OK: $ADDR ($MODEL)"
        break
      elif [ "$STATUS" = failed ]; then
        echo "   Interview FAILED — re-press pairing and stay in range."
      fi ;;
  esac
done
[ -n "$ADDR" ] || { echo "!! No device joined within 250s. Aborting."; PUB zigbee2mqtt/bridge/request/permit_join '{"time":0}'; exit 1; }

PUB zigbee2mqtt/bridge/request/permit_join '{"time":0}'
echo ">> Renaming $ADDR -> $NAME"
PUB zigbee2mqtt/bridge/request/device/rename "{\"from\":\"$ADDR\",\"to\":\"$NAME\"}"
sleep 2

echo ">> Configuring reporting (repChange 0.2°C / 30s / 1h)."
echo ">> SHORT-press the sensor button once NOW, and again at each retry line."
OK=""
for i in $(seq 1 12); do
  docker exec mosquitto mosquitto_sub -t zigbee2mqtt/bridge/response/device/configure_reporting -W 13 -C 1 >/tmp/cfg_resp 2>/dev/null &
  SUBPID=$!
  sleep 1
  PUB zigbee2mqtt/bridge/request/device/configure_reporting \
    "{\"id\":\"$NAME\",\"endpoint\":1,\"cluster\":\"msTemperatureMeasurement\",\"attribute\":\"measuredValue\",\"minimum_report_interval\":30,\"maximum_report_interval\":3600,\"reportable_change\":20}"
  wait $SUBPID || true
  STATUS=$(JGET status </tmp/cfg_resp)
  if [ "$STATUS" = ok ]; then OK=1; echo "   configure_reporting: OK"; break; fi
  echo "   attempt $i/12 timed out — SHORT-press the button and hold on..."
done
[ -n "$OK" ] || { echo "!! configure_reporting never acked. Re-run just the reporting part later."; exit 1; }

echo ">> Verifying in database.db (z2m may take a minute to flush; missing here is not fatal):"
python3 - "$ADDR" <<'PY' || true
import json, sys
addr = sys.argv[1]
for line in open('/home/andrew/home-ops/zigbee2mqtt/database.db'):
    try: d = json.loads(line)
    except Exception: continue
    if d.get('ieeeAddr') == addr:
        for ep in d.get('endpoints', {}).values():
            for r in ep.get('configuredReportings', []):
                if r.get('cluster') == 1026:
                    print('   cluster 1026:', r)
PY
echo ">> Done: $NAME paired and configured."
REMOTE
