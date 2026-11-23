import Toybox.Lang;

// Pure formatting / maths helpers, kept free of device APIs so they can be
// unit-tested (see Tests.mc).
module Fmt {

    const MISSING = "--";

    // Fixed English abbreviations: the face is set in a Latin-only vector font,
    // so system-language day/month names (CJK, Thai, Arabic...) would not render.
    const DOW = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
    const MONTH = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];

    // dayOfWeek 1..7 (Sunday = 1), month 1..12, as Gregorian FORMAT_SHORT returns.
    function date(dayOfWeek as Number, day as Number, month as Number) as String {
        var dow = (dayOfWeek >= 1 && dayOfWeek <= 7) ? DOW[dayOfWeek - 1] : "";
        var mon = (month >= 1 && month <= 12) ? MONTH[month - 1] : "";
        return dow + " " + day + " " + mon;
    }

    function number(v as Number?) as String {
        return (v != null) ? v.toString() : MISSING;
    }

    // Recovery time arrives in minutes. Under an hour is shown in minutes,
    // otherwise in hours rounded to nearest.
    function recoveryValue(min as Number?) as String {
        if (min == null || min < 0) {
            return MISSING;
        }
        return (min < 60) ? min.toString() : ((min + 30) / 60).toString();
    }

    function recoveryUnit(min as Number?) as String {
        return (min != null && min >= 0 && min < 60) ? "MIN" : "H";
    }

    // How many of `count` segments are lit for value/full. Any progress at all
    // lights the first segment; the last only lights when the target is reached.
    function segments(value as Number?, full as Number?, count as Number) as Number {
        if (value == null || full == null || full <= 0 || value <= 0) {
            return 0;
        }
        if (value >= full) {
            return count;
        }
        var lit = (value.toLong() * count / full).toNumber();
        return (lit < 1) ? 1 : lit;
    }

    // Width in pixels of a range bar of `width` for value/full, clamped.
    function bar(value as Number?, full as Number, width as Number) as Number {
        if (value == null || value <= 0 || full <= 0) {
            return 0;
        }
        if (value >= full) {
            return width;
        }
        return (value.toLong() * width / full).toNumber();
    }
}
