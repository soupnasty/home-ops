# home-ops

House config as code. Runs in a bridged Debian VM (UTM) on soupnasty (Mac mini).
Full context: `artifacts/2026-07-27-home-automation-platform-project-spec.md`
in the home-projects repo.

## Layout

- `docker-compose.yml` — HA, ESPHome, Mosquitto, Zigbee2MQTT (Phase 1); ring-mqtt behind `--profile phase2`
- `esphome/` — six CN105 cassette nodes; shared package in `common/`, per-node files are substitutions only
- `homeassistant/` — HA config (runtime state gitignored; see backups)
- `zigbee2mqtt/`, `mosquitto/` — broker + Zigbee network config
- `scripts/backup.sh` — nightly state backup (`.storage/`, HA db, Z2M data)

## First run (inside the VM)

```sh
cp esphome/secrets.yaml.example esphome/secrets.yaml            # then fill in
cp zigbee2mqtt/configuration.example.yaml zigbee2mqtt/configuration.yaml
# set the SLZB-06's reserved IP in zigbee2mqtt/configuration.yaml
docker compose up -d
docker compose stop zigbee2mqtt   # until the SLZB-06 is on the network
```

Validate ESPHome configs without hardware:

```sh
docker compose run --rm esphome config hvac-living.yaml
```

## Before flashing (checklist)

- [ ] Verify TX/RX pin mapping against the Serin cable pinout (`esphome/common/cn105-cassette.yaml`)
- [ ] Point `remote_sensor_entity` on instrumented nodes at the real Zigbee sensor entity IDs (pair sensors first, check names in HA)
- [ ] Set the Zigbee channel in `zigbee2mqtt/configuration.yaml` based on the router's actual 2.4GHz channel — before pairing anything

## Backups

Runtime state (HomeKit pairings, entity registry, Zigbee network key + device
table) lives outside git. Cron `scripts/backup.sh` nightly inside the VM and
sync the destination off-box. Restoring = clone repo + restore latest tarball.
