# Hourly stats archive — permanent sensor data for analysis

Status: spec drafted 2026-08-20 (incl. HVAC operational addition), awaiting
review; scripts drafted but NOT deployed.
Goal: an append-only, never-deleted archive of hourly sensor data (energy, power,
temperature, humidity — everything HA tracks statistics for), stored outside the
VM so it survives HA purges, backup rotation, and VM loss. Consumed later for
analysis (pandas/DuckDB read the CSVs directly).

## Why this design

- HA already computes exactly the dataset we want: **long-term statistics** — one
  row per sensor per hour (mean/min/max for measurements, state/sum for energy
  counters) in the `statistics` table of `home-assistant_v2.db`. 81 sensors
  tracked, 7,569 rows as of 2026-08-20. HA never purges this table, but it lives
  inside one SQLite file on the VM: a db corruption, botched HA migration, or VM
  loss takes all history with it. The nightly backup tarballs rotate at 14 days,
  so a problem noticed late loses everything older.
- Therefore: export new hourly rows out of the db every hour to flat CSVs on the
  mini. Flat files, append-only, no database dependency, trivially analyzable.
- No HA API token exists in this stack (see docs/../README + memory), so the
  export reads the SQLite db directly, read-only (`mode=ro` URI — safe against
  concurrent HA writes).

## Architecture

```
VM (home-ops.local)                          Mac mini host (soupnasty)
┌──────────────────────────────┐             ┌─────────────────────────────────┐
│ home-assistant_v2.db         │  ssh+sudo   │ launchd com.homeops.stats-pull  │
│  statistics (hourly, forever)│◄────────────│  hourly at :10                  │
│ scripts/export_stats.py      │──CSV stdout►│ scripts/stats-pull.sh           │
│  (read-only query)           │             │  → ~/Backups/home-ops-analytics/│
└──────────────────────────────┘             │     stats-YYYY-MM.csv (append)  │
                                             │     .last_ts (high-water mark)  │
                                             └─────────────────────────────────┘
```

- **`scripts/export_stats.py`** (runs in VM via `sudo`, same pattern as
  backup.sh): queries `statistics ⋈ statistics_meta` for rows with
  `start_ts > <since>`, emits CSV to stdout. Read-only db open.
- **`scripts/stats-pull.sh`** (runs on mini via launchd, mirrors
  backup-pull.sh): reads `.last_ts`, ssh-runs the exporter, appends rows to
  monthly files `stats-YYYY-MM.csv` (bucketed by **row** timestamp, UTC), writes
  the new high-water mark only after all rows are safely appended.
- **`com.homeops.stats-pull.plist`**: StartCalendarInterval Minute=10 (hourly;
  HA finalizes each hour's row within ~5 min of the hour). Log:
  /tmp/homeops-stats-pull.log. Andrew bootstraps it (classifier blocks Claude
  from launchctl bootstrap).

## Data format

CSV columns: `statistic_id,unit,start_ts,mean,min,max,state,sum`

- `statistic_id` — e.g. `sensor.hvac_living_room_energy`; `start_ts` — epoch
  seconds (UTC) of the hour start; `mean/min/max` — measurement sensors (temps,
  power); `state/sum` — energy counters (sum is the Energy-dashboard
  monotonic total; diff consecutive sums for kWh/hour).
- Nulls stay empty fields. One header line per file.
- Volume: ~81 ids × 24 h ≈ 2k rows/day, ~5 MB/month. Never rotated, never
  deleted — a decade is small.

## Failure modes & properties

- **Mini asleep / VM down / ssh fails at :10** → run fails, log shows it; next
  hourly run catches up automatically (query is "everything since high-water
  mark", not "last hour"). Gaps self-heal as long as the db retains the rows
  (it retains them forever).
- **`.last_ts` lost** → next run re-exports everything → duplicate rows in that
  month's file. Analysis side dedupes on (statistic_id, start_ts). Never loses
  data.
- **Partial append then crash** → high-water mark not advanced, rows re-fetched
  next run → duplicates possible, loss not.
- **VM dies permanently** → archive already on the mini; also independent of
  the nightly state tarballs.
- Off-site: same TODO as backups — `~/Backups/` (both dirs) should sync
  off-machine eventually.

## HVAC operational sensors (spec addition 2026-08-20)

Coverage audit of the 81 tracked statistics found temp/humidity/power/energy
fully covered, but no HVAC *operational* data: setpoint, mode, and
heating/cooling action live as attributes on the `climate.*` entities, and HA
only computes long-term statistics for numeric **sensor** entities with a
`state_class`. Room temperature is already fully covered for the 5 live heads
(living room + nursery via Zigbee sensors; kitchen / master / bedroom 1 via the
existing `current_temperature` template sensors in configuration.yaml).

Fix: extend that same template block with 3 sensors per head × 5 heads
(`climate.bedroom_1_hvac`, `kitchen_hvac`, `living_room_hvac`,
`master_bedroom_hvac`, `nursery_hvac`; dining added when the cassette is
installed):

- **`<room> HVAC Setpoint`** — `state_attr(x, 'temperature')`, °F,
  `state_class: measurement`, `availability` guarded like the existing temp
  templates. Hourly mean/min/max shows the target the unit was chasing.
- **`<room> HVAC Heating`** — `1` when the climate **mode** is `heat` else
  `0`, `state_class: measurement`, no unit. Hourly mean = fraction of the hour
  the head was in heat mode.
- **`<room> HVAC Cooling`** — same for mode `cool`.

DEVIATION (found at deploy 2026-08-20): the spec originally called for
`hvac_action` (actively heating/cooling), but the core-ESPHome
`mitsubishi_cn105` firmware on the heads doesn't publish an action trait —
the attribute doesn't exist on the climate entities. Reflashing 6 nodes
mid-debug wasn't worth it, so heating/cooling are **mode-based**: they
measure demand-enabled fraction, not compressor duty. True electrical duty
comes from the Vue `heat_pump_power` / `hvac_indoor_units_power` channels.
`heat_cool` (auto) mode sets neither flag. If per-head action is ever
wanted, the upgrade path is firmware-side (check whether the component
gained action support, then OTA all heads) — the archive picks it up with
no pipeline change.

Mode (heat/cool/off) is deliberately not encoded: an hourly mean of a
categorical encoding isn't analyzable, and actual behavior is captured better
by the two duty-cycle sensors (mode ≈ which duty is nonzero + season).

HA rolls these into hourly statistics automatically; the archive pipeline
needs zero changes (row count grows 81 → 96 ids). History starts at deploy
time — climate attributes are only recoverable from the 10-day `states`
purge window, so no meaningful backfill exists. Deploy = edit
`homeassistant/configuration.yaml`, scp to VM, `docker restart homeassistant`
(template sensors need no storage surgery).

## Explicitly out of scope

- Raw sub-hourly states (the `states` table, 10-day purge) — hourly was the
  requirement; revisit `statistics_short_term` (5-min, ~10-day retention) if
  finer grain is ever wanted.
- InfluxDB/TimescaleDB — heavier moving part, another service to babysit; CSVs
  meet the analysis need.
- Backfill of pre-archive history: first run exports the entire `statistics`
  table (since=0), so everything HA has ever aggregated (back to first boot) is
  captured automatically.

## Deployment steps (after spec approval)

0. HVAC operational sensors: add the 15 template sensors to
   `homeassistant/configuration.yaml`, scp, `docker restart homeassistant`,
   confirm the new `sensor.*_hvac_*` entities appear and gain statistics
   within ~an hour.
1. `scp scripts/export_stats.py andrew@home-ops.local:~/home-ops/scripts/`
2. Manual end-to-end test on mini: `bash scripts/stats-pull.sh` → verify
   `~/Backups/home-ops-analytics/stats-2026-*.csv` rows look right, run again →
   "no new rows".
3. Andrew: `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.homeops.stats-pull.plist`
4. Next day: check /tmp/homeops-stats-pull.log shows hourly appends.
