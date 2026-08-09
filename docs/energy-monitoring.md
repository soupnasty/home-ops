# Energy monitoring — Emporia Vue Gen 3 spec

Status: research complete 2026-08-09, hardware not yet ordered.
Goal: whole-home + per-circuit energy in HA's Energy dashboard, fully local
(ESPHome-flashed, no Emporia cloud), per-HVAC energy attribution.

## Compatibility verdict: ✅ compatible

- Service: Dominion meter (Aclara I-210+c) nameplate reads **CL 200 / 240V / 3W / FM2S**
  → 200 A-class split-phase 3-wire. Vue 3 supports exactly this (2× 200 A mains CTs,
  max 264 VAC L-N). No Delta/3-phase complications.
- Network: WiFi confirmed usable at the panel; Vue 3 also has built-in 10/100 Ethernet
  as fallback. 2.4 GHz only — fine on Chunky Noodle. The WiFi antenna is external on an
  RP-SMA pigtail and gets routed **through a knockout to outside the panel can** (metal
  enclosure blocks signal; this is the documented install pattern, not a hack).
- ESPHome: Gen 3 support is merged in the `emporia-vue-local` component main `dev`
  branch (`variant: vue3`). Our ESPHome 2026.7.3 (`:stable`) is past the 2026.4.x
  breakage; the fix lives in the component, so pin it by commit at setup time.
  Do NOT use the deprecated `@vue3` branch.
- Internals: ESP32-D0WD-V3, 8 MB flash, no secure boot / no efuse locks — reflashable.
  Caveat: Emporia has shipped silent board revisions with different GPIO pin maps
  (breaks Phase A readings under the standard config); digiblur's fork carries the fix.
  Which revision we get is discovered at flash time — not a blocker, just a fork swap.

## Order list

| Item | Est. | Notes |
|---|---|---|
| Emporia Vue 3, 16-sensor kit | $199.99 | Includes 2× 200 A mains CTs + 16× 50 A branch CTs + voltage harness + antenna |
| 3.3 V USB-TTL adapter | ~$10 | FTDI FT232RL-style preferred — CP2102 boards' weak 3.3 V rail is known to brown out the ESP32 mid-flash |
| (optional) Flash jig print | filament | Printables model 1152988 (fixed-tolerance remix). Soldered wires are the more reliable one-time path |
| 2× Square D QO115 breakers | ~$25 | Power the Vue's voltage harness in the panel's empty bottom spaces (QO series, not Homeline) |
| (optional) RP-SMA M-F extension | ~$8 | Only if antenna placement near the panel needs help |

## CT allocation (from panel photo 2026-08-09 — Square D QO, QOC42UF 42-space)

Mains: 2× 200 A CTs on the service conductors between meter and main breaker.

Branch CTs mapped to the actual circuit directory:

| Breaker(s) | Circuit | CTs | Config notes |
|---|---|---|---|
| 1/3 and 5/7 | HVAC (two 2-pole circuits) | 2 | One CT per circuit + `multiply: 2` (pure 240 V). ⚠️ Directory shows TWO HVAC 2-poles but Andrew reports ONE outdoor unit — verify on install day which breaker(s) actually feed it (flip test); the second may be an abandoned/legacy circuit or a separate feed |
| 2/4 | Dryer | 2 (merged) | Has neutral → CT per leg, summed in config |
| 24/26 | Water heater (electric — confirmed by directory) | 1 | Pure 240 V → single CT ×2 |
| 33 (+pair) | Range | 2 (merged) | Directory ambiguity: 33 "range" but its pair slot is labeled countertop outlets — verify it's a 2-pole electric range and find its second leg |
| 28 | Refrigerator | 1 | |
| 29 | Microwave | 1 | |
| 22 or 25 | Dishwasher | 1 | Labels 22/25 are cross-corrected on the sheet (dishwasher↔disposal swapped) — identify which is actually the dishwasher |
| 30, 35 | Kitchen countertop outlets | 2 | |
| — | Spare | 4 | Headroom for EV/solar/laundry later; mains CTs already bidirectional |

Total: 12 of 16 branch CTs used. CTs clamp the hot leg at each breaker; >50 A branch
circuits (future EV) use a 200 A mains-style CT on a side port with multiplier 4.0.

## Vue power connection (this panel)

Panel has **empty spaces at the bottom** → cleanest option is two new **Square D QO
single-pole 15 A breakers (QO115)** in vertically adjacent spaces (adjacent = opposite
legs, which the voltage harness needs: black→L1 breaker, red→L2 breaker, white+blue→
neutral bar). ~$12–15 each; QO series only — not Homeline. This avoids splicing onto
existing circuits entirely.

## Power / mounting (install day)

- Unit mounts inside the panel (≥2 in from live parts) or DIN-rail outside; CT leads
  are trimmable.
- Powered by the 4-wire voltage harness — **no dedicated 2-pole breaker needed**:
  black L1 + red L2 to two vertically adjacent single-pole breakers (any ampacity,
  or splice onto existing 15 A circuits with included wire nuts), white + blue to
  neutral bus. AFCI/GFCI breakers have a special procedure — check what's adjacent.
- Mains CTs go on live service conductors — the one step where "call an electrician"
  is a fair answer.

## Flash plan (bench, before panel install)

1. Open case (5 screws + antenna nut). Test pads: GND / **3.3 V** / GND / TXD / RXD.
   **3.3 V only — 5 V destroys the board.** A user bricked one feeding 5 V to the
   regulator; that's the only true bricking path.
2. Wiring quirk: pads are silkscreened transposed — wire **straight through**
   (adapter RX→RXD, TX→TXD). If esptool won't sync, swap.
3. Ground GPIO0 before power-up for boot mode.
4. **Backup stock firmware first (mandatory):**
   `esptool read-flash 0 ALL vue3-stock-backup.bin` — this is the factory-restore
   path and makes software bricking fully recoverable. Note: flaky on Apple Silicon;
   if the read stalls, do it from the home-ops VM with USB passthrough.
5. Serial-flash a minimal ESPHome config; everything after is OTA.
6. **Bench soak before panel install:** confirm it survives a reboot plus one full
   OTA cycle on our exact ESPHome version. (The 2026.4.x incident bootlooped
   panel-mounted units into serial-only recovery — bench-validate first.)

## ESPHome config skeleton (esphome/energy-monitor.yaml)

Key elements (full config written at build time):

```yaml
esp32:
  board: esp32dev
  flash_size: 8MB          # omitting this breaks flashing on the 8MB Gen 3
  cpu_frequency: 160MHz    # belt-and-suspenders vs the 240MHz brownout regression
  framework: { type: esp-idf }
preferences:
  flash_write_interval: 48h
external_components:
  - source: github://emporia-vue-local/esphome@<PINNED_COMMIT>   # dev branch, pin at build time
    components: [emporia_vue]
i2c: { sda: 5, scl: 18, scan: false, frequency: 400kHz, timeout: 1ms }  # Gen 3 pins (not 21/22)
sensor:
  - platform: emporia_vue
    variant: vue3
    # phase_a (black) / phase_b (red): calibration: 0.01925  (Vue 3 value; 0.022 is Gen 2)
    # 16 CTs: phase_id + input "1".."16"; expect multiply: -1 sign flips per circuit,
    # multiply: 2 on single-CT 240V circuits; merged pairs summed via template sensor
    # power sensors: throttle_average: 5s
  - platform: total_daily_energy   # per circuit + whole-home; these feed HA Energy
```

Reuses the fleet's `secrets.yaml` (WiFi, API key, OTA password). Name: `energy-monitor`,
mDNS `energy-monitor.local` (no DHCP reservations until router reset).

Calibration: per-phase, not per-CT. Verify voltage against a multimeter at an outlet;
`new = cal × actual / reported`. Expect 2–5% under-read vs the utility meter (line loss).

## HA integration

- Register via the established config-entry injection (same as HVAC nodes).
- Energy dashboard: Grid consumption = whole-home `total_daily_energy` sensor;
  Individual devices = per-circuit energy sensors. Electricity Maps integration for
  carbon (free, account + API key, no hardware).
- Add Dominion's rate to the Energy dashboard cost tracking (flat $/kWh to start).

## Known risks / open items

- Board-revision pin-map lottery → may need digiblur's fork (`digiblur/esphome-vue3`)
  if Phase A reads wrong after flashing. Discovered at flash time; recoverable.
- Unpopulated CT inputs can read 65535 garbage (component patches this; don't panic).
- One unresolved community report of WiFi failing post-flash on an Ethernet-flashed
  unit — if WiFi misbehaves, Ethernet port is the fallback (or the powerline-adapter
  plan B already earmarked for the VM).
- Bench-validate OTA before panel install (see flash plan step 6) — recovery from a
  bad OTA in-panel means pulling the unit back out.
