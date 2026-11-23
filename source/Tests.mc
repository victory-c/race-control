import Toybox.Lang;
import Toybox.Test;
import Toybox.Weather;

(:test)
function testDate(logger as Logger) as Boolean {
    return Fmt.date(2, 23, 11).equals("MON 23 NOV")
        && Fmt.date(1, 1, 1).equals("SUN 1 JAN")
        && Fmt.date(7, 31, 12).equals("SAT 31 DEC")
        && Fmt.date(0, 5, 13).equals(" 5 ");        // out-of-range input must not crash
}

(:test)
function testMissingValues(logger as Logger) as Boolean {
    return Fmt.number(null).equals("--")
        && Fmt.number(0).equals("0")
        && Fmt.recoveryValue(null).equals("--")
        && Fmt.recoveryValue(-1).equals("--")
        && Fmt.recoveryUnit(null).equals("H")
        && Fmt.segments(null, 10000, 15) == 0
        && Fmt.segments(5000, null, 15) == 0
        && Fmt.segments(5000, 0, 15) == 0
        && Fmt.bar(null, 100, 88) == 0;
}

(:test)
function testRecovery(logger as Logger) as Boolean {
    return Fmt.recoveryValue(0).equals("0") && Fmt.recoveryUnit(0).equals("MIN")
        && Fmt.recoveryValue(59).equals("59") && Fmt.recoveryUnit(59).equals("MIN")
        && Fmt.recoveryValue(60).equals("1") && Fmt.recoveryUnit(60).equals("H")
        && Fmt.recoveryValue(89).equals("1")
        && Fmt.recoveryValue(90).equals("2")
        && Fmt.recoveryValue(4320).equals("72");
}

(:test)
function testSegments(logger as Logger) as Boolean {
    return Fmt.segments(0, 10000, 15) == 0
        && Fmt.segments(1, 10000, 15) == 1           // any progress shows
        && Fmt.segments(5000, 10000, 15) == 7
        && Fmt.segments(9999, 10000, 15) == 14       // full bar only at goal
        && Fmt.segments(10000, 10000, 15) == 15
        && Fmt.segments(250000, 10000, 15) == 15
        && Fmt.segments(2000000000, 2100000000, 15) == 14   // no 32-bit overflow
        && Fmt.segments(50, 100, 10) == 5
        && Fmt.segments(100, 100, 10) == 10;
}

(:test)
function testBar(logger as Logger) as Boolean {
    return Fmt.bar(0, 100, 88) == 0
        && Fmt.bar(50, 100, 88) == 44
        && Fmt.bar(100, 100, 88) == 88
        && Fmt.bar(9000, 4320, 88) == 88;
}

(:test)
function testWeatherLabels(logger as Logger) as Boolean {
    // Every documented condition 0..52 maps to a short code; UNKNOWN, null and
    // values from future firmware map to null (no label drawn).
    for (var c = 0; c <= 52; c++) {
        var s = WeatherText.label(c);
        if (s == null || s.length() > 7) {
            logger.debug("no label for condition " + c);
            return false;
        }
    }
    return WeatherText.label(Weather.CONDITION_UNKNOWN) == null
        && WeatherText.label(null) == null
        && WeatherText.label(999) == null
        && (WeatherText.label(Weather.CONDITION_CLEAR) as String).equals("CLEAR");
}

(:test)
function testThemeSelection(logger as Logger) as Boolean {
    var ok = Themes.select(1) && Themes.current() == 1
        && Themes.select(2) && Themes.current() == 2
        && !Themes.select(3) && Themes.current() == 2      // out of range ignored
        && !Themes.select(-1) && !Themes.select(null) && !Themes.select("1")
        && Themes.current() == 2;
    for (var i = 0; i < Themes.COUNT; i++) {
        ok = ok && Themes.colors(i).size() == 5;
    }
    ok = ok && Themes.colors(99)[0] == Themes.colors(0)[0];  // unknown -> default palette
    Themes.select(0);
    return ok && Themes.current() == 0;
}
