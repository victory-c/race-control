import Toybox.Activity;
import Toybox.Application;
import Toybox.ActivityMonitor;
import Toybox.Complications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Weather;

// All sensor / system reads live here so the view never touches an API that a
// device might not have. Every metric is nullable: null means "not available
// right now, or not supported on this device" and the view renders it as "--".
//
//   * Body Battery: a Complication pushes updates (a few an hour), so nothing
//     is polled; the on-device history is the fallback.
//   * Battery, steps, weather, sunset: plain cached reads, once a minute at most.
//   * Heart rate: Activity.Info once per awake second (a cached system value),
//     newest history sample as the once-a-minute fallback.
class Telemetry {

    var bodyBattery as Number? = null;
    var battery as Number = 0;              // percent
    var charging as Boolean = false;
    var steps as Number? = null;
    var stepGoal as Number? = null;
    var temperature as Number? = null;      // already in the user's unit
    var condition as String? = null;
    var windSpeed as Number? = null;        // already in the user's unit
    var windUnit as String = "KMH";
    var heartRate as Number? = null;
    var sunset as Time.Moment? = null;      // today's sunset at the weather location

    // Set when a complication pushed a new value; cleared by refreshPushed().
    var dirty as Boolean = false;

    private var mCompBody as Number? = null;

    // Capability flags, resolved once: `has` is a runtime symbol lookup.
    private var mHasComplications as Boolean;
    private var mHasBodyHistory as Boolean;
    private var mHasWeather as Boolean;
    private var mHasSunset as Boolean;
    private var mHasHrHistory as Boolean;
    // Last place a forecast was for, kept across restarts for the sunset.
    private var mLat as Double? = null;
    private var mLon as Double? = null;

    function initialize() {
        mHasComplications = (Toybox has :Complications);
        mHasBodyHistory = (Toybox has :SensorHistory) && (Toybox.SensorHistory has :getBodyBatteryHistory);
        mHasWeather = (Toybox has :Weather) && (Weather has :getCurrentConditions);
        mHasSunset = mHasWeather && (Weather has :getSunset);
        mHasHrHistory = (ActivityMonitor has :getHeartRateHistory);
        try {
            var saved = Application.Storage.getValue("loc");
            if (saved instanceof Array && saved.size() == 2) {
                var la = saved[0];
                var lo = saved[1];
                if (la instanceof Double && lo instanceof Double) {
                    mLat = la;
                    mLon = lo;
                }
            }
        } catch (e) {
            // No stored place: sunset stays hidden until a forecast has one.
        }
        if (mHasComplications) {
            Complications.registerComplicationChangeCallback(method(:onComplication));
            var id = new Complications.Id(Complications.COMPLICATION_TYPE_BODY_BATTERY);
            try {
                Complications.subscribeToUpdates(id);
                onComplication(id);     // prime the cache with the current value
            } catch (e) {
                // Not offered by this device: the history fallback covers it.
            }
        }
    }

    // Called from AppBase.onStop(): leave nothing registered with the system.
    function stop() as Void {
        if (mHasComplications) {
            Complications.unsubscribeFromAllUpdates();
            Complications.registerComplicationChangeCallback(null);
        }
    }

    // Push callback. No requestUpdate(): awake we redraw every second anyway,
    // asleep (always-on) no telemetry is shown.
    function onComplication(id as Complications.Id) as Void {
        if (id.getType() != Complications.COMPLICATION_TYPE_BODY_BATTERY) {
            return;
        }
        var n = null;
        try {
            var v = Complications.getComplication(id).value;
            if (v instanceof Number) {
                n = v;
            } else if (v instanceof Float) {
                n = v.toNumber();
            }
        } catch (e) {
            // Treat as "no value".
        }
        mCompBody = n;
        dirty = true;
    }

    // Slow path: once per minute while awake, and on wake.
    function refreshSlow() as Void {
        var stats = System.getSystemStats();
        battery = (stats.battery + 0.5).toNumber();
        charging = (stats has :charging) && stats.charging;

        var am = ActivityMonitor.getInfo();
        steps = am.steps;
        stepGoal = am.stepGoal;
        refreshPushed();
        refreshWeather();
        refreshHeartSlow();
    }

    // Once per awake second. Returns true when the value changed. A missing
    // live value keeps the last one until the next slow refresh decides.
    function refreshHeart() as Boolean {
        var info = Activity.getActivityInfo();
        if (info != null) {
            var hr = info.currentHeartRate;
            if (hr != null && hr != heartRate) {
                heartRate = hr;
                return true;
            }
        }
        return false;
    }

    // Live value, else the newest history sample if it is under five minutes
    // old (watch off the wrist shows "--", not an old reading).
    private function refreshHeartSlow() as Void {
        var hr = null;
        var info = Activity.getActivityInfo();
        if (info != null) {
            hr = info.currentHeartRate;
        }
        if (hr == null && mHasHrHistory) {
            var s = ActivityMonitor.getHeartRateHistory(1, true).next();
            if (s != null) {
                var v = s.heartRate;
                var at = s.when;
                if (v != null && v != ActivityMonitor.INVALID_HR_SAMPLE && at != null
                        && Time.now().value() - at.value() < 300) {
                    hr = v;
                }
            }
        }
        heartRate = hr;
    }

    // Body Battery: complication first, newest on-device history sample second.
    function refreshPushed() as Void {
        dirty = false;
        var bb = mCompBody;
        if (bb == null && mHasBodyHistory) {
            var it = Toybox.SensorHistory.getBodyBatteryHistory({ :period => 1, :order => Toybox.SensorHistory.ORDER_NEWEST_FIRST });
            var s = it.next();
            if (s != null) {
                var d = s.data;
                if (d != null) {
                    bb = d.toNumber();
                }
            }
        }
        bodyBattery = bb;
    }

    // Weather: a cached system object, so reading it is cheap. Observations
    // older than six hours (phone out of range) are treated as missing rather
    // than shown as current.
    private function refreshWeather() as Void {
        temperature = null;
        condition = null;
        windSpeed = null;
        if (!mHasWeather) {
            return;
        }
        var c = Weather.getCurrentConditions();
        refreshSunset((c != null) ? c.observationLocationPosition : null);
        if (c == null) {
            return;
        }
        var at = c.observationTime;
        if (at != null && Time.now().value() - at.value() >= 6 * 3600) {
            return;
        }
        var settings = System.getDeviceSettings();
        var t = c.temperature;
        if (t != null) {
            if (settings.temperatureUnits == System.UNIT_STATUTE) {
                t = t * 9.0 / 5.0 + 32.0;
            }
            temperature = Math.round(t).toNumber();
        }
        condition = WeatherText.label(c.condition);
        var ws = c.windSpeed;       // metres per second
        if (ws != null) {
            var statute = (settings.distanceUnits == System.UNIT_STATUTE);
            windSpeed = Math.round(ws * (statute ? 2.23694 : 3.6)).toNumber();
            windUnit = statute ? "MPH" : "KMH";
        }
    }

    // Sunset only needs a place, so it survives a stale or missing forecast:
    // the forecast's own location when it has one, else the last one seen.
    private function refreshSunset(loc as Toybox.Position.Location?) as Void {
        if (!mHasSunset) {
            return;
        }
        if (loc != null) {
            var d = loc.toDegrees();
            var la = d[0];
            var lo = d[1];
            var oldLa = mLat;
            var oldLo = mLon;
            // Rewrite storage only after a real move (about 5 km), not on jitter.
            if (oldLa == null || oldLo == null || (la - oldLa).abs() > 0.05 || (lo - oldLo).abs() > 0.05) {
                mLat = la;
                mLon = lo;
                try {
                    Application.Storage.setValue("loc", [la, lo]);
                } catch (e) {
                    // Storage full or unavailable: keep it in memory only.
                }
            }
        } else {
            var la = mLat;
            var lo = mLon;
            if (la != null && lo != null) {
                loc = new Toybox.Position.Location({ :latitude => la, :longitude => lo, :format => :degrees });
            }
        }
        sunset = (loc != null) ? Weather.getSunset(loc, Time.now()) : null;
    }
}

// Collapses Garmin's 54 weather conditions into pit-wall style short codes.
module WeatherText {
    function label(cond as Number?) as String? {
        if (cond == null) {
            return null;
        }
        switch (cond) {
            case Weather.CONDITION_CLEAR:
            case Weather.CONDITION_PARTLY_CLEAR:
            case Weather.CONDITION_MOSTLY_CLEAR:
            case Weather.CONDITION_FAIR:
                return "CLEAR";
            case Weather.CONDITION_PARTLY_CLOUDY:
            case Weather.CONDITION_MOSTLY_CLOUDY:
            case Weather.CONDITION_CLOUDY:
            case Weather.CONDITION_THIN_CLOUDS:
                return "CLOUD";
            case Weather.CONDITION_RAIN:
            case Weather.CONDITION_HEAVY_RAIN:
            case Weather.CONDITION_SCATTERED_SHOWERS:
            case Weather.CONDITION_UNKNOWN_PRECIPITATION:
            case Weather.CONDITION_SHOWERS:
            case Weather.CONDITION_HEAVY_SHOWERS:
            case Weather.CONDITION_CHANCE_OF_SHOWERS:
            case Weather.CONDITION_CLOUDY_CHANCE_OF_RAIN:
                return "RAIN";
            case Weather.CONDITION_LIGHT_RAIN:
            case Weather.CONDITION_LIGHT_SHOWERS:
            case Weather.CONDITION_DRIZZLE:
                return "DRIZZLE";
            case Weather.CONDITION_SNOW:
            case Weather.CONDITION_LIGHT_SNOW:
            case Weather.CONDITION_HEAVY_SNOW:
            case Weather.CONDITION_CHANCE_OF_SNOW:
            case Weather.CONDITION_CLOUDY_CHANCE_OF_SNOW:
            case Weather.CONDITION_FLURRIES:
            case Weather.CONDITION_ICE_SNOW:
                return "SNOW";
            case Weather.CONDITION_WINTRY_MIX:
            case Weather.CONDITION_LIGHT_RAIN_SNOW:
            case Weather.CONDITION_HEAVY_RAIN_SNOW:
            case Weather.CONDITION_RAIN_SNOW:
            case Weather.CONDITION_CHANCE_OF_RAIN_SNOW:
            case Weather.CONDITION_CLOUDY_CHANCE_OF_RAIN_SNOW:
            case Weather.CONDITION_FREEZING_RAIN:
            case Weather.CONDITION_SLEET:
                return "SLEET";
            case Weather.CONDITION_THUNDERSTORMS:
            case Weather.CONDITION_SCATTERED_THUNDERSTORMS:
            case Weather.CONDITION_CHANCE_OF_THUNDERSTORMS:
            case Weather.CONDITION_HURRICANE:
            case Weather.CONDITION_TROPICAL_STORM:
            case Weather.CONDITION_TORNADO:
                return "STORM";
            case Weather.CONDITION_WINDY:
            case Weather.CONDITION_SQUALL:
                return "WIND";
            case Weather.CONDITION_FOG:
            case Weather.CONDITION_MIST:
                return "FOG";
            case Weather.CONDITION_HAZY:
            case Weather.CONDITION_HAZE:
            case Weather.CONDITION_DUST:
            case Weather.CONDITION_SMOKE:
            case Weather.CONDITION_SAND:
            case Weather.CONDITION_SANDSTORM:
            case Weather.CONDITION_VOLCANIC_ASH:
                return "HAZE";
            case Weather.CONDITION_HAIL:
                return "HAIL";
            case Weather.CONDITION_ICE:
                return "ICE";
            default:
                return null;    // CONDITION_UNKNOWN and anything newer
        }
    }
}
