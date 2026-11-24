import Toybox.Lang;
import Toybox.Test;
import Toybox.Weather;

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

(:test)
function testGrouped(logger as Logger) as Boolean {
    return Fmt.grouped(0).equals("0")
        && Fmt.grouped(999).equals("999")
        && Fmt.grouped(1000).equals("1,000")
        && Fmt.grouped(4812).equals("4,812")
        && Fmt.grouped(12005).equals("12,005");
}

(:test)
function testSteps(logger as Logger) as Boolean {
    return Fmt.steps(null, 0).equals("--")
        && Fmt.steps(null, 2).equals("--")
        && Fmt.steps(812, 2).equals("812")
        && Fmt.steps(12345, 0).equals("12,345")
        && Fmt.steps(12345, 1).equals("12.3K")
        && Fmt.steps(12045, 1).equals("12.0K")
        && Fmt.steps(12999, 2).equals("12K");
}

(:test)
function testDate(logger as Logger) as Boolean {
    return Fmt.date(2, 23, 11).equals("MON 23 NOV")
        && Fmt.date(1, 1, 1).equals("SUN 1 JAN")
        && Fmt.date(7, 31, 12).equals("SAT 31 DEC")
        && Fmt.date(0, 5, 13).equals(" 5 ")         // out-of-range input must not crash
        && Fmt.dow(3).equals("TUE")
        && Fmt.dow(9).equals("");
}

(:test)
function testClockText(logger as Logger) as Boolean {
    return Fmt.hm(0, 0).equals("00:00")
        && Fmt.hm(9, 5).equals("09:05")
        && Fmt.hm(23, 59).equals("23:59");
}

(:test)
function testMissingValues(logger as Logger) as Boolean {
    return Fmt.number(null).equals("--")
        && Fmt.number(0).equals("0")
        && Fmt.grouped(null).equals("--")
        && Fmt.steps(null, 1).equals("--");
}


(:test)
function testZone2(logger as Logger) as Boolean {
    return Zone2.cleanLabel("hkg").equals("HKG")
        && Zone2.cleanLabel("london").equals("LOND")
        && Zone2.cleanLabel("").equals("HKG")
        && Zone2.cleanLabel(null).equals("HKG")
        && Zone2.cleanLabel(5).equals("HKG")
        && Zone2.cleanOffset(480) == 480
        && Zone2.cleanOffset(-300) == -300
        && Zone2.cleanOffset(330) == 330
        && Zone2.cleanOffset(900) == 480
        && Zone2.cleanOffset(null) == 480
        && Zone2.cleanOffset("0") == 480;
}
