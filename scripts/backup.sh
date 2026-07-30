#!/usr/bin/env bash
# Nightly backup of runtime state that git can't capture:
# HA .storage (HomeKit pairings, registries), the HA database, and the
# Zigbee2MQTT data dir (network key, device table, coordinator backup).
# Run from cron inside the VM; sync $DEST off-box.
#   usage: backup.sh /path/to/backup/dir
set -euo pipefail

cd "$(dirname "$0")/.."
DEST="${1:?usage: backup.sh <dest-dir>}"
STAMP="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$DEST"
tar czf "$DEST/home-ops-state-$STAMP.tgz" \
  homeassistant/.storage \
  homeassistant/home-assistant_v2.db \
  zigbee2mqtt

# keep the newest 14
ls -t "$DEST"/home-ops-state-*.tgz | tail -n +15 | xargs rm -f --
echo "wrote $DEST/home-ops-state-$STAMP.tgz"
