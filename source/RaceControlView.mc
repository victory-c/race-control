import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// RACE CONTROL: an everyday watch face built around one very large clock.
//
//   date            MON 23 NOV
//   weather         46°  CLOUD  8 MPH  (sun) 16:53   <- sunset
//   clock           HH:MM, as large as the round screen allows, dead centre
//   four values     HR / BODY (Body Battery) / STEPS / BATT, value over label
//   second zone     HKG TUE 19:46   (label and UTC offset are settings)
//
// Nothing on the face is smaller than the label font (30 px on the 454-px
// screen, about 1.7 mm cap height on the watch).
//
// Everything is laid out in a 454-px design space and scaled by px(), so the
// 390-px model uses the same code with its own smaller bitmap fonts.
//
// Always-on (low power): thin HH:MM in the same place, plus the date.
class RaceControlView extends WatchUi.WatchFace {

    private const DESIGN = 454;
    private const BODY_ALERT = 20;
    private const BATTERY_ALERT = 15;

    private var mData as Telemetry;
    private var mReady as Boolean = false;
    private var mSleep as Boolean = false;
    private var mDirty as Boolean = true;
    private var mStamp as Number = -1;
    private var mHasDisplayMode as Boolean;

    // second time zone (settings; default Hong Kong, UTC+8)
    private var mZoneShow as Boolean = true;
    private var mZoneName as String = "HKG";
    private var mZoneOffsetSec as Number = 8 * 3600;

    // theme
    private var mAccent as Number = 0xE10600;
    private var mFg as Number = 0xF2EFE8;
    private var mDim as Number = 0x8A8A8E;
    private var mAod as Number = 0xA4A4A8;

    // fonts (bitmap fonts rasterised from OFL sources, see tools/fonts.sh)
    private var mFClock as Graphics.FontType = Graphics.FONT_NUMBER_THAI_HOT;
    private var mFThin as Graphics.FontType = Graphics.FONT_NUMBER_THAI_HOT;
    private var mFVal as Graphics.FontType = Graphics.FONT_MEDIUM;
    private var mFLab as Graphics.FontType = Graphics.FONT_TINY;
    // text is positioned by baseline: y = baseline - ascent
    private var mAClock as Number = 0;
    private var mAVal as Number = 0;
    private var mALab as Number = 0;

    // layout, device pixels
    private var mCx as Number = 0;
    private var mScale as Number = DESIGN;
    private var mCell as Number = 0;        // clock digit cell width
    private var mColonW as Number = 0;
    private var mClockX as Number = 0;      // left edge of HH:MM
    private var mCapClock as Number = 0;    // cap height of the clock numerals
    private var mSq as Number = 0;          // colon square
    private var mYDate as Number = 0;
    private var mYWeather as Number = 0;
    private var mYClock as Number = 0;
    private var mYValue as Number = 0;
    private var mYLabel as Number = 0;
    private var mYZone as Number = 0;
    private var mColGap as Number = 0;      // space between the four columns
    private var mRowMax as Number = 0;      // widest the row may get
    private var mLineMax as Number = 0;     // widest the weather line may get
    private var mColX as Array<Number> = [0, 0, 0, 0];  // column centres
    private var mSunW as Number = 0;        // sunset icon width
    private var mGap as Number = 0;

    // cached strings, rebuilt at most once a minute
    private var mH1 as String = "0";
    private var mH2 as String = "0";
    private var mM1 as String = "0";
    private var mM2 as String = "0";
    private var mDate as String = "";
    private var mZoneLabel as String = "";  // "HKG TUE "
    private var mZoneTime as String = "";   // "19:46"
    private var mZoneX as Number = 0;
    private var mZoneLabelW as Number = 0;
    private var mHr as String = "--";
    private var mBody as String = "--";
    private var mBodyAlert as Boolean = false;
    private var mSteps as String = "--";
    private var mStepsDone as Boolean = false;
    private var mBat as String = "--";
    private var mBatLabel as String = "BATT";
    private var mBatAlert as Boolean = false;
    private var mTemp as String = "--°";
    private var mWeather as String = "";    // condition and wind, after the temperature
    private var mWeatherX as Number = 0;    // left edge of the weather line
    private var mTempW as Number = 0;
    private var mSunset as String = "";     // "16:53", empty when unknown
    private var mSunX as Number = 0;        // left edge of the sunset icon

    function initialize() {
        WatchFace.initialize();
        mData = new Telemetry();
        mHasDisplayMode = (System has :getDisplayMode);
        loadTheme();
    }

    function loadTheme() as Void {
        var c = Themes.colors(Themes.current());
        mAccent = c[0];
        mFg = c[1];
        mDim = c[2];
        mAod = c[4];
        mZoneShow = Zone2.shown();
        mZoneName = Zone2.label();
        mZoneOffsetSec = Zone2.offsetSec();
        mDirty = true;
        mStamp = -1;        // rebuild the cached zone line
    }

    function stop() as Void {
        mData.stop();
    }

    private function px(n as Number) as Number {
        return (n * mScale + DESIGN / 2) / DESIGN;
    }

    private function maxDigitWidth(dc as Dc, font as Graphics.FontType) as Number {
        var w = 0;
        for (var i = 0; i < 10; i++) {
            var cw = dc.getTextWidthInPixels(i.toString(), font);
            if (cw > w) {
                w = cw;
            }
        }
        return w;
    }

    function onLayout(dc as Dc) as Void {
        mScale = dc.getWidth();
        mCx = mScale / 2;

        mFClock = WatchUi.loadResource(Rez.Fonts.Clock) as Graphics.FontType;
        mFThin = WatchUi.loadResource(Rez.Fonts.Thin) as Graphics.FontType;
        mFVal = WatchUi.loadResource(Rez.Fonts.Val) as Graphics.FontType;
        mFLab = WatchUi.loadResource(Rez.Fonts.Lab) as Graphics.FontType;
        mAClock = Graphics.getFontAscent(mFClock);
        mAVal = Graphics.getFontAscent(mFVal);
        mALab = Graphics.getFontAscent(mFLab);

        mGap = px(10);
        mCell = maxDigitWidth(dc, mFClock) - px(5);
        mColonW = px(34);
        mSq = px(15);
        mCapClock = px(120);
        mClockX = mCx - (4 * mCell + mColonW) / 2;

        // The clock's cap height is centred on the screen centre.
        mYClock = mScale / 2 + mCapClock / 2;
        mYDate = px(76);
        mYWeather = px(130);
        mYValue = px(340);
        mYLabel = px(374);
        mYZone = px(420);
        mColGap = px(14);
        mRowMax = px(332);
        mLineMax = px(366);
        mSunW = px(24);

        mReady = true;
    }

    function onShow() as Void {
        // Returning from a widget / activity / the settings menu: nothing cached
        // can be trusted, and an on-device theme change may not have fired
        // onSettingsChanged().
        loadTheme();
        mSleep = false;
        mDirty = true;
        mStamp = -1;
    }

    function onEnterSleep() as Void {
        mSleep = true;
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        mSleep = false;
        mDirty = true;      // telemetry was not refreshed while asleep
        mStamp = -1;        // the display may have been off for hours
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        if (!mReady) {
            onLayout(dc);
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var low = mSleep;
        if (mHasDisplayMode) {
            var mode = System.getDisplayMode();
            if (mode == System.DISPLAY_MODE_OFF) {
                mStamp = -1;    // whatever is cached will be stale when the panel relights
                return;
            }
            low = low || (mode == System.DISPLAY_MODE_LOW_POWER);
        }

        var clock = System.getClockTime();
        var stamp = clock.hour * 60 + clock.min;
        var minuteChanged = (stamp != mStamp);
        if (minuteChanged) {
            mStamp = stamp;
            // Always 24-hour, whatever the watch's 12/24 h setting says.
            mH1 = (clock.hour / 10).toString();
            mH2 = (clock.hour % 10).toString();
            mM1 = (clock.min / 10).toString();
            mM2 = (clock.min % 10).toString();
            var now = Time.now();
            var d = Gregorian.info(now, Time.FORMAT_SHORT);
            mDate = Fmt.date(d.day_of_week as Number, d.day as Number, d.month as Number);
            // Second zone: shift the instant, then read it as UTC.
            var z = Gregorian.utcInfo(new Time.Moment(now.value() + mZoneOffsetSec), Time.FORMAT_SHORT);
            mZoneLabel = mZoneName + " " + Fmt.dow(z.day_of_week as Number) + " ";
            mZoneTime = Fmt.hm(z.hour, z.min);
            mZoneLabelW = dc.getTextWidthInPixels(mZoneLabel, mFLab);
            mZoneX = mCx - (mZoneLabelW + dc.getTextWidthInPixels(mZoneTime, mFLab)) / 2;
        }

        if (low) {
            drawAlwaysOn(dc, clock.min);
            return;
        }

        if (minuteChanged || mDirty) {
            mDirty = false;
            refreshTelemetry(dc);
        } else if (mData.dirty) {
            mData.refreshPushed();      // a complication pushed Body Battery
            refreshBody();
            layoutRow(dc);
        } else if (mData.refreshHeart()) {
            mHr = Fmt.number(mData.heartRate);
            layoutRow(dc);
        }
        drawFull(dc);
    }

    // At most once a minute: pull slow data and rebuild the cached strings.
    private function refreshTelemetry(dc as Dc) as Void {
        var t = mData;
        t.refreshSlow();
        refreshBody();

        mHr = Fmt.number(t.heartRate);
        var steps = t.steps;
        var goal = t.stepGoal;
        mStepsDone = (steps != null && goal != null && goal > 0 && steps >= goal);

        mBat = t.battery.toString() + "%";
        mBatLabel = t.charging ? "CHG" : "BATT";
        mBatAlert = (t.battery <= BATTERY_ALERT) && !t.charging;

        var temp = t.temperature;
        mTemp = (temp != null) ? temp.toString() + "°" : "--°";
        mTempW = dc.getTextWidthInPixels(mTemp, mFVal);
        var set = t.sunset;
        if (set != null) {
            var si = Gregorian.info(set, Time.FORMAT_SHORT);
            mSunset = Fmt.hm(si.hour, si.min);
        } else {
            mSunset = "";
        }
        var sunW = (mSunset.length() > 0)
            ? mGap + mSunW + px(6) + dc.getTextWidthInPixels(mSunset, mFLab) : 0;

        // Condition and wind; the wind unit is dropped if the line gets too wide.
        var cond = t.condition;
        var wind = t.windSpeed;
        var total = 0;
        var textW = 0;
        for (var pass = 0; pass < 2; pass++) {
            var w = (cond != null) ? cond : "";
            if (wind != null) {
                if (w.length() > 0) {
                    w = w + "  ";
                }
                w = w + wind + ((pass == 0) ? " " + t.windUnit : "");
            }
            mWeather = w;
            textW = (w.length() > 0) ? mGap + dc.getTextWidthInPixels(w, mFLab) : 0;
            total = mTempW + textW + sunW;
            if (total <= mLineMax) {
                break;
            }
        }
        mWeatherX = mCx - total / 2;
        mSunX = mWeatherX + mTempW + textW + mGap;

        layoutRow(dc);
    }

    // Four columns, each as wide as its value or label, spread evenly around
    // the centre. Steps are shortened ("12,345" > "12.3K" > "12K") until the
    // row fits the round screen.
    private function layoutRow(dc as Dc) as Void {
        var labels = ["HR", "BODY", "STEPS", mBatLabel];
        var w = [0, 0, 0, 0];
        var total = 0;
        for (var level = 0; level < 3; level++) {
            mSteps = Fmt.steps(mData.steps, level);
            var values = [mHr, mBody, mSteps, mBat];
            total = 3 * mColGap;
            for (var i = 0; i < 4; i++) {
                var vw = dc.getTextWidthInPixels(values[i], mFVal);
                var lw = dc.getTextWidthInPixels(labels[i], mFLab);
                w[i] = (vw > lw) ? vw : lw;
                total += w[i];
            }
            if (total <= mRowMax) {
                break;
            }
        }
        var x = mCx - total / 2;
        for (var i = 0; i < 4; i++) {
            mColX[i] = x + w[i] / 2;
            x += w[i] + mColGap;
        }
    }

    private function refreshBody() as Void {
        var bb = mData.bodyBattery;
        mBody = Fmt.number(bb);
        mBodyAlert = (bb != null && bb <= BODY_ALERT);
    }

    // ---- awake -----------------------------------------------------------

    private function drawFull(dc as Dc) as Void {
        var L = Graphics.TEXT_JUSTIFY_LEFT;
        var C = Graphics.TEXT_JUSTIFY_CENTER;
        var T = Graphics.COLOR_TRANSPARENT;

        // date
        dc.setColor(mDim, T);
        dc.drawText(mCx, mYDate - mALab, mFLab, mDate, C);

        // weather: temperature, then condition and wind speed
        dc.setColor(mFg, T);
        dc.drawText(mWeatherX, mYWeather - mAVal, mFVal, mTemp, L);
        dc.setColor(mDim, T);
        dc.drawText(mWeatherX + mTempW + mGap, mYWeather - mALab, mFLab, mWeather, L);
        if (mSunset.length() > 0) {
            drawSunset(dc, mSunX, mYWeather);
            dc.setColor(mFg, T);
            dc.drawText(mSunX + mSunW + px(6), mYWeather - mALab, mFLab, mSunset, L);
        }

        // clock: each digit centred in a fixed cell so nothing shifts as digits change
        drawClock(dc, mFClock, mClockX, mYClock, mFg, mAccent, mSq);

        // four values, value over label
        drawColumn(dc, mColX[0], "HR", mHr, mFg);
        drawColumn(dc, mColX[1], "BODY", mBody, mBodyAlert ? mAccent : mFg);
        drawColumn(dc, mColX[2], "STEPS", mSteps, mStepsDone ? mAccent : mFg);
        drawColumn(dc, mColX[3], mBatLabel, mBat, mBatAlert ? mAccent : mFg);

        // second time zone
        if (!mZoneShow) {
            return;
        }
        dc.setColor(mDim, T);
        dc.drawText(mZoneX, mYZone - mALab, mFLab, mZoneLabel, L);
        dc.setColor(mFg, T);
        dc.drawText(mZoneX + mZoneLabelW, mYZone - mALab, mFLab, mZoneTime, L);
    }

    private function drawClock(dc as Dc, font as Graphics.FontType, x as Number, base as Number,
                               color as Number, colonColor as Number, sq as Number) as Void {
        var C = Graphics.TEXT_JUSTIFY_CENTER;
        var T = Graphics.COLOR_TRANSPARENT;
        var y = base - mAClock;
        var half = mCell / 2;
        dc.setColor(color, T);
        dc.drawText(x + half, y, font, mH1, C);
        dc.drawText(x + mCell + half, y, font, mH2, C);
        dc.drawText(x + 2 * mCell + mColonW + half, y, font, mM1, C);
        dc.drawText(x + 3 * mCell + mColonW + half, y, font, mM2, C);
        var cxColon = x + 2 * mCell + (mColonW - sq) / 2;
        dc.setColor(colonColor, T);
        dc.fillRectangle(cxColon, base - mCapClock * 3 / 4 - sq / 2, sq, sq);
        dc.fillRectangle(cxColon, base - mCapClock / 4 - sq / 2, sq, sq);
    }

    // Sunset mark: half a sun sitting on a horizon line, on the text baseline.
    private function drawSunset(dc as Dc, x as Number, base as Number) as Void {
        var r = px(9);
        var bar = px(3);
        var yh = base - bar;
        dc.setColor(mDim, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x + mSunW / 2, yh - px(2), r);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(x, yh - px(2), mSunW, r + px(2));
        dc.setColor(mDim, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x, yh, mSunW, bar);
    }

    private function drawColumn(dc as Dc, x as Number, label as String, value as String, color as Number) as Void {
        var C = Graphics.TEXT_JUSTIFY_CENTER;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, mYValue - mAVal, mFVal, value, C);
        dc.setColor(mDim, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, mYLabel - mALab, mFLab, label, C);
    }

    // ---- always-on ---------------------------------------------------------

    // Thin grey time in the same place as the awake clock, plus the date.
    // Shifted every minute on both axes so no pixel is lit permanently; the
    // date is static all day, so it travels further than the clock.
    private function drawAlwaysOn(dc as Dc, min as Number) as Void {
        var dx = (min % 5 - 2) * 3;
        var dy = (min % 7 - 3) * 2;
        drawClock(dc, mFThin, mClockX + dx, mYClock + dy, mAod, mAod, px(7));

        var dyDate = (min % 7 - 3) * 5;
        var dxDate = (min % 9 - 4) * 2;
        dc.setColor(mDim, Graphics.COLOR_TRANSPARENT);
        dc.drawText(mCx + dxDate, mYClock + px(62) + dyDate - mALab, mFLab, mDate, Graphics.TEXT_JUSTIFY_CENTER);
    }
}
