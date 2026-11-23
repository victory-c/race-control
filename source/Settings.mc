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
