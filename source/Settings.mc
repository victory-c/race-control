import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Three colour themes. Each row: [accent, foreground, dim, grid, AOD clock].
// Background is always true black: on AMOLED a black pixel is an unpowered pixel.
module Themes {
    const COUNT = 3;

    function colors(theme as Number) as Array<Number> {
        switch (theme) {
            case 1: // Sector Amber
                return [0xFFAA00, 0xF4F1E8, 0x8C8A84, 0x34322E, 0xA8A49A];
            case 2: // Telemetry Cyan
                return [0x00D2BE, 0xEEF3F2, 0x848C8B, 0x2C3433, 0x9AA6A4];
            default: // Pit Wall Red
                return [0xE10600, 0xF2EFE8, 0x8A8A8E, 0x323236, 0xA4A4A8];
        }
    }

    // Stores a theme picked on the watch. Anything that is not a valid theme
    // index is ignored. Returns true when the value was stored.
    function select(id as Object?) as Boolean {
        if (id instanceof Number && id >= 0 && id < COUNT) {
            Application.Properties.setValue("Theme", id);
            return true;
        }
        return false;
    }

    function current() as Number {
        var v = null;
        try {
            v = Application.Properties.getValue("Theme");
        } catch (e) {
            // Property missing (corrupt/old settings): fall through to default.
        }
        if (v instanceof Number && v >= 0 && v < COUNT) {
            return v;
        }
        return 0;
    }
}

// Second time zone shown under the clock. Set from Garmin Connect / the
// Connect IQ app: on/off, a short label, and a fixed offset from UTC in
// minutes (daylight saving is not applied).
module Zone2 {
    const DEFAULT_LABEL = "HKG";
    const DEFAULT_OFFSET_MIN = 480;

    // Upper-case, at most four characters; anything unusable gives the default.
    function cleanLabel(v as Object?) as String {
        if (v instanceof String) {
            var s = v.toUpper();
            if (s.length() > 4) {
                s = s.substring(0, 4) as String;
            }
            if (s.length() > 0) {
                return s;
            }
        }
        return DEFAULT_LABEL;
    }

    // UTC-12:00 .. UTC+14:00, in minutes.
    function cleanOffset(v as Object?) as Number {
        if (v instanceof Number && v >= -720 && v <= 840) {
            return v;
        }
        return DEFAULT_OFFSET_MIN;
    }

    function read(key as String) as Object? {
        try {
            return Application.Properties.getValue(key);
        } catch (e) {
            return null;    // property missing: caller falls back to the default
        }
    }

    function shown() as Boolean {
        var v = read("Zone2Show");
        return !(v instanceof Boolean) || v;
    }

    function label() as String {
        return cleanLabel(read("Zone2Label"));
    }

    function offsetSec() as Number {
        return cleanOffset(read("Zone2Offset")) * 60;
    }
}

class ThemeMenu extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({ :title => WatchUi.loadResource(Rez.Strings.ThemeTitle) as String });
        var cur = Themes.current();
        var names = [Rez.Strings.ThemeRed, Rez.Strings.ThemeAmber, Rez.Strings.ThemeCyan];
        for (var i = 0; i < names.size(); i++) {
            addItem(new WatchUi.MenuItem(WatchUi.loadResource(names[i]) as String, null, i, null));
        }
        setFocus(cur);
    }
}

class ThemeMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        Themes.select(item.getId());
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
