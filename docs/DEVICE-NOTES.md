> Note: this file was written for earlier designs. The current face shows a plain heart-rate number, Body Battery, steps, battery, weather with sunset, and a configurable second time zone. It has no heart-rate trace, recovery time or threshold settings, uses four bitmap fonts (clock 172 px, thin 172 px, values 44 px, labels 30 px on the 47 mm), and its always-on frame is about 6% luminance worst case. Sections below that mention the removed features are out of date.

# Device and API notes

Target: Garmin Forerunner 570, both sizes.

| | fr57047mm | fr57042mm |
|---|---|---|
| Screen | 454 x 454 round AMOLED | 390 x 390 round AMOLED |
| Connect IQ | 6.0.3 | 6.0.3 |
| Watch-face heap | 131,072 bytes | 131,072 bytes |
| Graphics pool | 3 MB | 3 MB |
| Launcher icon | 65 x 65 | 54 x 54 (auto-scaled from 65) |

Everything below was checked against the SDK 9.3.0 docs and the device API
symbol files (`Devices/fr57047mm/fr57047mm.api.debug.xml`), then exercised in
the simulator. Items marked **sim only** have not been confirmed on a real watch.

## What a watch face is not allowed to do

- **No `Toybox.Sensor`.** Watch faces can only declare `Sensor` together with
  `Background`, so there is no foreground sensor stream. Live heart rate comes
  from `Activity.getActivityInfo().currentHeartRate`, read once per awake
  second.
- **No per-second updates while asleep.** `onPartialUpdate()` is not in the
  FR570 symbol table (AMOLED devices dropped it). Asleep, `onUpdate()` runs once
  a minute, so the always-on frame has no seconds and no live data.
- **No timers or animations in low power.** None are used.
- **`onPowerBudgetExceeded` never fires** on this device (it belongs to
  `onPartialUpdate`), so it is not implemented.

## AMOLED always-on rules

- Burn-in protection on this class of device is a **luminance budget: the
  always-on frame must stay under 10% of full-screen luminance**. If it does
  not, the system blanks the screen until the next wake; there is no callback.
- The always-on frame is a thin grey `HH:MM` (Saira Light), two small colon
  squares, one 1 px rule and the date. **Estimated at 2-3% luminance** from a
  simulator capture and from replaying the frame against the font bitmaps.
  It has not been re-run through the simulator's Screen Burn-In tool
  (File > View Screen Heat Map) since the redesign; the previous design
  measured 2.5-3.2% there.
- The clock block shifts every minute on both axes (5 x 7 = 35 positions, at
  most 6 px from home). The date is static all day, so it moves further
  (up to 15 px vertically, 8 px horizontally, on a different period).
- `System.getDisplayMode()` (API 5.0) is the source of truth for
  high-power / low-power / off; `onEnterSleep` / `onExitSleep` are kept as the
  fallback signal.
- Background is true black in every theme. On AMOLED a black pixel draws no
  power, which is why "near-black" was not used.

## Metrics: source, fallback, and what "unsupported" looks like

| Metric | Primary | Fallback | Shown when missing |
|---|---|---|---|
| Heart rate | `Activity.Info.currentHeartRate` (1 Hz, awake) | newest `ActivityMonitor.getHeartRateHistory` sample, only if under 5 minutes old | `--`, no margin caption |
| Heart-rate trace | `ActivityMonitor.getHeartRateHistory` (4 h 16 min, 64 slots of 4 min, highest sample per slot) | none | dim stubs |
| Wind | `Weather.CurrentConditions.windSpeed` (m/s) and `.windBearing` | none | omitted |
| Body Battery | `COMPLICATION_TYPE_BODY_BATTERY` (push) | `SensorHistory.getBodyBatteryHistory` newest sample | `--` |
| Recovery time | `COMPLICATION_TYPE_RECOVERY_TIME` (**minutes**) | `ActivityMonitor.Info.timeToRecovery` (**hours**) | `--` |
| Battery | `System.getSystemStats().battery`, `.charging` | none needed | always present |
| Weather | `Weather.getCurrentConditions()` | none | `--°` |
| Steps | `ActivityMonitor.getInfo().steps` / `.stepGoal` | none | `--`, empty bar |

- Every optional API is guarded with `has` once at start-up, and every value is
  nullable all the way to the draw call. A device without Body Battery,
  complications, weather or recovery time shows `--` in that cell and nothing
  else changes.
- **Units trap:** the recovery complication is in minutes, `timeToRecovery` is
  in hours. Both are normalised to minutes in `Telemetry`.
- **Body Battery history is on-device data only.** Right after a reboot it can
  be empty until the first sample is recorded.
- **Weather needs the phone** to have synced a forecast; with no data
  `getCurrentConditions()` returns null and each field can be null on its own.
  Observations older than six hours are treated as missing instead of being
  shown as current. Temperature is always Celsius from the API and converted
  for statute users.
- **Heart rate is not subscribed as a complication on purpose.** It changes
  every few seconds, and a subscription would call into the app all day while
  the face is asleep and showing no heart rate. Body Battery and recovery
  change a few times an hour, so those two are push-driven.
- **Whether `currentHeartRate` is populated on a watch face outside an
  activity is not stated in the SDK docs** (sim only: it is). If it is null on
  hardware the row falls back to the newest history sample, refreshed once a
  minute, and shows `--` when that sample is more than 5 minutes old (watch
  off the wrist) rather than presenting an old reading as current.
- **Steps complication is unavailable in wheelchair mode**, which is one reason
  steps use `ActivityMonitor` directly.
- **Recovery time is still a subscribed complication**, and its value is in
  minutes, so it can push about once a minute while it counts down, including
  while the face is asleep. Each push is a few field writes. Reading it
  unsubscribed was not adopted because the docs do not say an unsubscribed
  complication returns a fresh value; worth testing on hardware.
- Complication subscriptions are dropped when the app stops and are re-made in
  `Telemetry.initialize()`. The subscription limit is undocumented; a failed
  subscribe is caught and the fallback is used.

## Permissions

`ComplicationSubscriber` (Body Battery and recovery push updates) and
`SensorHistory` (Body Battery fallback). Nothing else: no positioning, no
communications, no background service.

## Fonts

- The watch only ships four Latin vector faces (Roboto / Roboto Condensed),
  so the face uses its own **bitmap fonts**, rasterised from OFL typefaces in
  `fonts-src/` by `tools/fonts.sh`: Saira Semi Condensed SemiBold (clock,
  heart rate, seconds, values), Saira Light (always-on clock) and Martian Mono
  (labels).
- Bitmap fonts do not scale, so each screen size has its own set:
  `resources-round-454x454/fonts` (104 / 68 / 50 / 34 / 20 px) and
  `resources-round-390x390/fonts` (89 / 58 / 43 / 29 / 17 px).
- Glyph sets are minimal. **A character missing from a set draws nothing**, so
  any new label or unit must be added to the character list in
  `tools/fonts.sh` and the fonts regenerated.
- Decoded sheets total about 155 kB (47 mm) / 114 kB (42 mm). On this device
  font resources live in the 3 MB graphics pool, not the 131 kB app heap; the
  simulator's memory readout stays around 22 kB with all six loaded.
- Clock digits are drawn one per fixed-width cell, so the time does not shift
  as digits change.
- There is no letter-spacing API and no text rotation.

## Clock and date

- The clock is always 24-hour, as specified, and ignores the watch's 12/24 h
  setting. Honouring `DeviceSettings.is24Hour` is a three-line change in
  `RaceControlView.onUpdate` if that is ever wanted.
- Day and month names come from fixed English tables, not the system language:
  the device's vector Latin faces cannot render CJK, Thai, Arabic or Hebrew
  names.

## Settings

- Theme is a `number` property (`Theme`: 0 red, 1 amber, 2 cyan), editable from
  Garmin Connect / Connect IQ and on the watch through `getSettingsView()`
  (Menu2).
- **Sideloaded builds cannot be configured from the phone app**; the defaults
  in `resources/settings/properties.xml` apply until the face is installed
  from the store.
- The docs tie `onSettingsChanged()` to phone-side edits only, so the view also
  re-reads the theme in `onShow()` after the on-device menu closes.

## Simulator caveats

- The simulator does not enter low power on its own: use
  Settings > Display Mode > Always-On.
- Simulated complication and sensor values are synthetic. Null / unsupported
  paths are covered by the unit tests (`./build.sh test`), not by hardware.
- The simulator's step count and heart rate could not be driven from scripts.
  Long step counts are covered by unit tests of the formatting; the
  over-ceiling state was captured with a temporarily lowered ceiling.
- The simulator keeps stored properties between loads, and File > Reset All
  App Data did not reliably clear them; deleting
  `$TMPDIR/com.garmin.connectiq/GARMIN/APPS/SETTINGS/RACECONTROL-*.SET` does.
- Switching the simulated device while the Screen Burn-In window is open hangs
  the load; close that window first.
