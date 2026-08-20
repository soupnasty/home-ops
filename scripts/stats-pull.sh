#!/usr/bin/env bash
# Runs on the Mac mini host (launchd, hourly at :10). Pulls new hourly
# statistics rows from the HA database into an append-only CSV archive
# for analysis. Nothing here ever deletes archive files — rows purged
# from HA (or lost with the VM) remain in ~/Backups/home-ops-analytics.
set -euo pipefail

VM_HOST="${VM_HOST:-andrew@home-ops.local}"
DEST="${DEST:-$HOME/Backups/home-ops-analytics}"
STATE="$DEST/.last_ts"
HEADER="statistic_id,unit,start_ts,mean,min,max,state,sum"

mkdir -p "$DEST"
since="0"
[ -f "$STATE" ] && since="$(cat "$STATE")"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 "$VM_HOST" \
  "sudo python3 ~/home-ops/scripts/export_stats.py $since" > "$tmp"

if [ ! -s "$tmp" ]; then
  echo "$(date '+%F %T') no new rows (since=$since)"
  exit 0
fi

# Append rows to a monthly file (named by row month, UTC), header on create.
python3 - "$tmp" "$DEST" "$HEADER" <<'EOF'
import csv, os, sys, datetime
tmp, dest, header = sys.argv[1], sys.argv[2], sys.argv[3]
files = {}
last_ts = 0.0
with open(tmp, newline="") as f:
    for row in csv.reader(f):
        ts = float(row[2])
        last_ts = max(last_ts, ts)
        month = datetime.datetime.fromtimestamp(ts, datetime.timezone.utc).strftime("%Y-%m")
        path = os.path.join(dest, f"stats-{month}.csv")
        if path not in files:
            new = not os.path.exists(path)
            files[path] = open(path, "a", newline="")
            if new:
                files[path].write(header + "\n")
        csv.writer(files[path]).writerow(row)
for fh in files.values():
    fh.close()
# Record high-water mark only after all rows are safely appended.
with open(os.path.join(dest, ".last_ts"), "w") as f:
    f.write(repr(last_ts))
print(f"appended rows through ts={last_ts} into {sorted(os.path.basename(p) for p in files)}")
EOF

echo "$(date '+%F %T') stats pulled (since=$since)"
