import Toybox.Lang;

// Pure formatting helpers, kept free of device APIs so they can be unit-tested
// (see Tests.mc).
module Fmt {

    const MISSING = "--";

    // Fixed English abbreviations: the bitmap fonts only carry Latin capitals.
    const DOW = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
    const MONTH = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];

    // dayOfWeek 1..7 (Sunday = 1).
    function dow(dayOfWeek as Number) as String {
        return (dayOfWeek >= 1 && dayOfWeek <= 7) ? DOW[dayOfWeek - 1] : "";
    }

    // month 1..12, as Gregorian FORMAT_SHORT returns.
    function date(dayOfWeek as Number, day as Number, month as Number) as String {
        var mon = (month >= 1 && month <= 12) ? MONTH[month - 1] : "";
        return dow(dayOfWeek) + " " + day + " " + mon;
    }

    // "19:46", always 24-hour.
    function hm(hour as Number, min as Number) as String {
        return hour.format("%02d") + ":" + min.format("%02d");
    }

    function number(v as Number?) as String {
        return (v != null) ? v.toString() : MISSING;
    }

    // Step count at decreasing width: level 0 "12,345", 1 "12.3K", 2 "12K".
    function steps(v as Number?, level as Number) as String {
        if (v == null || level <= 0 || v < 1000) {
            return grouped(v);
        }
        if (level == 1) {
            return (v / 1000).toString() + "." + ((v % 1000) / 100).toString() + "K";
        }
        return (v / 1000).toString() + "K";
    }

    // 4812 -> "4,812"
    function grouped(v as Number?) as String {
        if (v == null) {
            return MISSING;
        }
        if (v < 1000) {
            return v.toString();
        }
        return (v / 1000).toString() + "," + (v % 1000).format("%03d");
    }
}
