# Energy monitoring — Emporia Vue Gen 3 spec

Status: research complete 2026-08-09, verified against primary sources same day; hardware not yet ordered.
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
  The Vue 3's mains CT ports A/C are swapped in the I2C payload vs Gen 2 (this was the
  "Phase A reads wrong" issue that digiblur's fork fixed) — the remap is now merged
  upstream and handled automatically by `variant: vue3`. No fork needed.

## Order list

| Item | Est. | Notes |
|---|---|---|
| Emporia Vue 3, 16-sensor kit | $199.99 | Includes 2× 200 A mains CTs + 16× 50 A branch CTs + voltage harness + antenna |
| 3.3 V USB-TTL adapter | ~$10 | No adapter's 3.3 V rail is really enough (ESP32 draws ~150 mA with radio; CP2102 ≈75 mA, FT232RL ≈50 mA — worse). Plan to power the board separately: external 3.3 V supply with common ground, or adapter 5 V into the LL33 regulator's input pin |
| (optional) Flash jig print | filament | Printables model 1152988 (fixed-tolerance remix), pogo pins + Dupont jumpers. Official docs warn against soldering to the tiny pads (pad-lift risk); jig/pogo is the recommended path. Conformal coating on the pads can block pogo contact — scrape if needed |
| 2× Square D QO115 breakers | ~$35 | ~$17 each at big-box (2026). Power the Vue's voltage harness in the panel's empty bottom spaces (QO series, not Homeline) |
| (optional) RP-SMA M-F extension | ~$8 | Only if antenna placement near the panel needs help |

## CT allocation (from panel photo 2026-08-09 — Square D QO 42-space; cover part QOC42UF)

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

Total: 12 of 16 branch CTs used. CTs clamp the hot leg at each breaker. Branch CTs are
rated 50 A but accurate through 63 A (saturate ~75 A); >63 A circuits (future EV) use a
200 A mains-style CT on a branch port with multiplier 4.0 — on Gen 3 that means
re-terminating the 200 A CT's wires into a 3.81 mm terminal block (the Gen 2 jack-adapter
trick doesn't apply; Gen 3 uses screw terminals throughout).

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

1. Open case (5 screws + loosen antenna SMA nut). Test pads: GND / **3.3 V** / GND /
   TXD / RXD. **Never put 5 V on the 3.3 V pad — that destroys the board.** (Feeding
   5 V into the LL33 regulator's *input* pin is fine — it's the recommended way to
   power the board when the adapter's 3.3 V rail is too weak, which it always is.)
   Use pogo pins / the jig, not solder — the pads lift easily.
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
  flash_size: 8MB          # matches Gen 3 hardware (optional — default 4MB image also works)
  cpu_frequency: 160MHz    # ESPHome 2026.4.0 changed the default to 240MHz → brownouts on the Vue
  framework: { type: esp-idf }
preferences:
  flash_write_interval: 48h
external_components:
  - source: github://emporia-vue-local/esphome@<PINNED_COMMIT>   # dev branch, pin at build time
    components: [emporia_vue]
i2c:  # Gen 3 pins (not 21/22); 400kHz + 1ms timeout fixes Vue3 i2c errors
  sda: 5
  ignore_strapping_warning: true   # GPIO5 is a strapping pin — expected on Vue 3
  scl: 18
  scan: false
  frequency: 400kHz
  timeout: 1ms
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

- Unpopulated CT inputs can read 65535 garbage — the component does NOT patch this;
  clamp it with YAML sensor filters on any input left unclamped (the 400kHz/1ms i2c
  settings above also reduce these malformed reads).
- Ethernet and WiFi are mutually exclusive at compile time (ESPHome won't build with
  both). Pick WiFi for the initial build; switching to Ethernet later is an OTA config
  change (use a static IP when switching). Powerline-adapter plan B still stands.
- Bench-validate OTA before panel install (see flash plan step 6) — recovery from a
  bad OTA in-panel means pulling the unit back out.
