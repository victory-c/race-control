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
- The always-on frame here is a thin grey `HH MM`, outline colon marks, the date
  and one 1 px rule. The simulator's Screen Burn-In tool (File > View Screen
  Heat Map, in Always-On display mode) reports **2.5-3.2% luminance, burn-in
  state NO** during its 24-hour run on the 47 mm model. The 42 mm model was not
  run through the tool; it draws the same frame scaled down.
- The whole block shifts every minute on both axes (5 x 7 = 35 positions, at
  most 6 px from home). Stroke cores of unchanged digits still overlap between
  neighbouring positions, so this spreads wear rather than eliminating it,
  which is all the luminance rule asks for.
- `System.getDisplayMode()` (API 5.0) is the source of truth for
  high-power / low-power / off; `onEnterSleep` / `onExitSleep` are kept as the
  fallback signal.
- Background is true black in every theme. On AMOLED a black pixel draws no
  power, which is why "near-black" was not used.

## Metrics: source, fallback, and what "unsupported" looks like

| Metric | Primary | Fallback | Shown when missing |
|---|---|---|---|
| Heart rate | `Activity.Info.currentHeartRate` (1 Hz, awake) | newest `ActivityMonitor.getHeartRateHistory` sample | `--`, no live marker |
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
  hardware the cell falls back to the newest history sample, refreshed once a
  minute.
- **Steps complication is unavailable in wheelchair mode**, which is one reason
  steps use `ActivityMonitor` directly.
- Complication subscriptions are dropped when the app stops and are re-made in
  `Telemetry.initialize()`. The subscription limit is undocumented; a failed
  subscribe is caught and the fallback is used.

## Permissions

`ComplicationSubscriber` (Body Battery and recovery push updates) and
`SensorHistory` (Body Battery fallback). Nothing else: no positioning, no
communications, no background service.

## Fonts

- Only four Latin vector faces exist on the FR570: `RobotoCondensedBold`,
  `RobotoCondensedRegular`, `RobotoRegular`, `RobotoItalic`. There is no
  non-condensed bold, so the Swiss feel comes from condensed bold numerals,
  caps labels and the grid.
- `RobotoCondensedBold` digits are tabular, so the clock does not jitter as
  digits change and its width is measured once.
- There is no letter-spacing API; caps labels are untracked.
- CJK / Thai firmware swaps system fonts. The face only uses system fonts as a
  fallback if `getVectorFont` returns null.

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
- The docs tie `onSettingsChanged()` to phone-side edits only, so the view also
  re-reads the theme in `onShow()` after the on-device menu closes.

## Simulator caveats

- The simulator does not enter low power on its own: use
  Settings > Display Mode > Always-On.
- Simulated complication and sensor values are synthetic. Null / unsupported
  paths are covered by the unit tests (`./build.sh test`), not by hardware.
- The simulator's step count could not be driven from scripts, so the step
  gauge's partial and goal-reached states are covered by unit tests of the
  segment maths only.
- The simulator keeps the last stored `Theme` property between loads; use
  File > Reset All App Data to get back to the default.
- Switching the simulated device while the Screen Burn-In window is open hangs
  the load; close that window first.
