import Toybox.Activity;
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
// Strategy (cheapest source first):
//   * Body Battery, recovery time: Complications push updates, so nothing is
//     polled. Direct APIs are the fallback when a complication is missing or
//     has no value. (Heart rate is deliberately NOT subscribed: it changes
//     every few seconds and would wake the app all day while the face sleeps.)
//   * Battery, steps, weather: plain cached reads, once a minute at most.
//   * Live heart rate: one field read per awake second.
class Telemetry {

    var hr as Number? = null;
    var bodyBattery as Number? = null;
    var recoveryMin as Number? = null;      // minutes until fully recovered
    var battery as Number = 0;              // percent
    var charging as Boolean = false;
    var steps as Number? = null;
    var stepGoal as Number? = null;
    var temperature as Number? = null;      // already in the user's unit
    var condition as String? = null;

    // Set when a complication pushed a new value; the view clears it after it
    // has rebuilt its cached strings.
    var dirty as Boolean = false;

    // Last values pushed by the complication system.
    private var mCompBody as Number? = null;
    private var mCompRecovery as Number? = null;
    private var mHistHr as Number? = null;

    // Capability flags, resolved once: `has` is a runtime symbol lookup.
    private var mHasComplications as Boolean;
    private var mHasBodyHistory as Boolean;
    private var mHasWeather as Boolean;
    private var mHasHrHistory as Boolean;

    function initialize() {
        mHasComplications = (Toybox has :Complications);
        mHasBodyHistory = (Toybox has :SensorHistory) && (Toybox.SensorHistory has :getBodyBatteryHistory);
        mHasWeather = (Toybox has :Weather) && (Weather has :getCurrentConditions);
        mHasHrHistory = (ActivityMonitor has :getHeartRateHistory);
        if (mHasComplications) {
            subscribe();
        }
    }

    private function subscribe() as Void {
        Complications.registerComplicationChangeCallback(method(:onComplication));
        var types = [
            Complications.COMPLICATION_TYPE_BODY_BATTERY,
            Complications.COMPLICATION_TYPE_RECOVERY_TIME
        ];
        for (var i = 0; i < types.size(); i++) {
            var id = new Complications.Id(types[i]);
            try {
                Complications.subscribeToUpdates(id);
                onComplication(id);     // prime the cache with the current value
            } catch (e) {
                // Complication not offered by this device, or too many
                // subscriptions: the direct-API fallback covers it.
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
        var t = id.getType();
        if (t == Complications.COMPLICATION_TYPE_BODY_BATTERY) {
            mCompBody = n;
            dirty = true;
        } else if (t == Complications.COMPLICATION_TYPE_RECOVERY_TIME) {
            mCompRecovery = n;
            dirty = true;
        }
    }

    // Cheap; called every awake second. Returns true when the value changed.
    function refreshHeartRate() as Boolean {
        var v = null;
        var info = Activity.getActivityInfo();
        if (info != null) {
            v = info.currentHeartRate;
        }
        if (v == null) {
            v = mHistHr;
        }
        var changed = (v != hr);
        hr = v;
        return changed;
    }

    // Slow path: once per minute while awake, and on wake.
    function refreshSlow() as Void {
        dirty = false;
        var stats = System.getSystemStats();
        battery = (stats.battery + 0.5).toNumber();
        charging = (stats has :charging) && stats.charging;

        var am = ActivityMonitor.getInfo();
        steps = am.steps;
        stepGoal = am.stepGoal;

        // Recovery: complication (minutes) first, ActivityMonitor (hours) second.
        var rec = mCompRecovery;
        if (rec == null && (am has :timeToRecovery)) {
            var h = am.timeToRecovery;
            if (h != null) {
                rec = h * 60;
            }
        }
        recoveryMin = rec;

        // Body Battery: complication first, newest on-device history sample second.
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

        // Heart-rate history only matters when nothing live is available.
        mHistHr = null;
        if (mHasHrHistory) {
            var hs = ActivityMonitor.getHeartRateHistory(1, true).next();
            if (hs != null) {
                var hv = hs.heartRate;
                if (hv != null && hv != ActivityMonitor.INVALID_HR_SAMPLE) {
                    mHistHr = hv;
                }
            }
        }

        // Weather: a cached system object, so reading it is cheap. Observations
        // older than six hours (phone out of range) are treated as missing
        // rather than shown as current.
        temperature = null;
        condition = null;
        if (mHasWeather) {
            var c = Weather.getCurrentConditions();
            if (c != null) {
                var at = c.observationTime;
                if (at == null || Time.now().value() - at.value() < 6 * 3600) {
                    var t = c.temperature;
                    if (t != null) {
                        if (System.getDeviceSettings().temperatureUnits == System.UNIT_STATUTE) {
                            t = t * 9.0 / 5.0 + 32.0;
                        }
                        temperature = Math.round(t).toNumber();
                    }
                    condition = WeatherText.label(c.condition);
                }
            }
        }
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
