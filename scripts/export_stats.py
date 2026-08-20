#!/usr/bin/env python3
"""Export HA long-term statistics (hourly rows) as CSV to stdout.

Runs inside the VM (needs read access to the HA db, so run via sudo).
Prints every statistics row with start_ts > the given epoch timestamp.
The db is opened read-only so a concurrent HA write can't be corrupted.

usage: export_stats.py <since_epoch_ts>
"""
import csv
import sqlite3
import sys

DB = "/home/andrew/home-ops/homeassistant/home-assistant_v2.db"

since = float(sys.argv[1]) if len(sys.argv) > 1 else 0.0

db = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
rows = db.execute(
    """
    SELECT sm.statistic_id, sm.unit_of_measurement,
           s.start_ts, s.mean, s.min, s.max, s.state, s.sum
    FROM statistics s
    JOIN statistics_meta sm ON s.metadata_id = sm.id
    WHERE s.start_ts > ?
    ORDER BY s.start_ts, sm.statistic_id
    """,
    (since,),
)
w = csv.writer(sys.stdout)
for row in rows:
    w.writerow(row)
