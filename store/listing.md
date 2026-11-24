# Connect IQ Store listing

Upload `bin/RaceControl.iq` (built with `./build.sh package`).
Icon: `store/store_icon.png` (500×500). Screenshot: `store/screenshot-1.png`.

## App name

RACE CONTROL

## Category

Watch face

## Description (English)

An everyday watch face built around one very large clock, sized to be read on
the wrist rather than in a screenshot. Nothing on it is smaller than 30 px.

On screen, top to bottom:
- Date
- Weather: temperature, condition, wind speed, and today's sunset time
- HH:MM, as large as the round screen allows, dead centre (24-hour)
- Heart rate, Body Battery, steps, watch battery
- A second time zone with the weekday (default: Hong Kong)

Details:
- AMOLED always-on mode: a thin clock and the date, about 6% of screen
  luminance, shifted every minute to protect the panel.
- Three accent colours (red, amber, cyan), on the watch or in the app.
- Second time zone: turn it off, or set your own label and UTC offset in
  minutes in the settings (Hong Kong 480, London 0, New York -300). Daylight
  saving is not applied automatically.
- Values turn the accent colour when Body Battery or the watch battery is low
  and when the step goal is reached.
- Weather and sunset need a forecast synced from your phone. Sunset uses the
  forecast's location.

Forerunner 570 (42 mm and 47 mm).

## What's new (1.0.0)

First release.

## Permissions shown to users

- Complication Subscriber: Body Battery updates.
- Sensor History: Body Battery fallback when the complication has no value.
