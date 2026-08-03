#!/usr/bin/env bash
# Runs on the Mac mini host (launchd, nightly). Triggers a state backup
# inside the VM, then pulls the backup dir to the host so VM loss doesn't
# take the backups with it. TODO: sync ~/Backups/home-ops off-machine
# (cloud or another box) for true off-site coverage.
set -euo pipefail

VM_HOST="${VM_HOST:-andrew@192.168.0.225}"
DEST="${DEST:-$HOME/Backups/home-ops}"

ssh -o BatchMode=yes -o ConnectTimeout=15 "$VM_HOST" \
  'cd ~/home-ops && sudo ./scripts/backup.sh /home/andrew/backups'
mkdir -p "$DEST"
rsync -a --delete "$VM_HOST:backups/" "$DEST/"
echo "$(date '+%F %T') backup pulled to $DEST"
