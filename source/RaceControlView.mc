import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// RACE CONTROL - pit-wall telemetry watch face.
//
// Composition (454 px design space, scaled by px()):
//   r 224..206  lap ring: 60 ticks that fill as the minute elapses, accent head
//   r 204       gauge track: battery arc across the top, steps arc across the bottom
//   x 81..373   one text margin shared by date, weather, clock and rules
//
// Redraw budget:
//   * awake      -> onUpdate() once a second. Layout, trig, fonts and every
//                   string except seconds / heart rate are cached; the frame
//                   path does integer maths and draw calls only.
//   * always-on  -> onUpdate() once a minute. Thin grey time + date, shifted
//                   every minute for AMOLED burn-in protection. No sensor reads.
class RaceControlView extends WatchUi.WatchFace {

    private const DESIGN = 454;
    private const STEP_SEGS = 15;
    private const BAT_SEGS = 10;
    private const RECOVERY_FULL = 4320;     // 72 h in minutes: full scale of the bar
    private const RECOVERY_ALERT = 2880;    // 48 h
    private const BODY_ALERT = 20;
    private const BATTERY_ALERT = 15;

    private var mData as Telemetry;
    private var mHasDisplayMode as Boolean;
    private var mSleep as Boolean = false;
    private var mReady as Boolean = false;
    private var mDirty as Boolean = true;
    private var mStamp as Number = -1;      // hour * 60 + minute of the cached strings

    // ---- geometry, filled once in onLayout --------------------------------
    private var mW as Number = DESIGN;
    private var mCx as Number = DESIGN / 2;
    private var mCy as Number = DESIGN / 2;
    private var mTicks as Array<Number> = [] as Array<Number>;   // 60 x (x1, y1, x2, y2)
    private var mHeads as Array<Number> = [] as Array<Number>;   // 60 x (x, y) inner end of the head
    private var mPenTick as Number = 2;
    private var mPenHead as Number = 5;
    private var mPenGauge as Number = 6;
    private var mGaugeR as Number = 204;
    private var mXL as Number = 81;         // shared left margin
    private var mXR as Number = 373;        // shared right margin
    private var mY1 as Number = 128;        // rules
    private var mY2 as Number = 272;
    private var mY3 as Number = 352;
    private var mRule1 as Number = 164;     // rule half-widths
    private var mRule2 as Number = 187;
    private var mSepX as Number = 62;
    private var mSepPad as Number = 10;
    private var mBatY as Number = 58;
    private var mRowY as Number = 102;
    private var mHalfGap as Number = 18;    // half the HH/MM gap that holds the colon
    private var mClockTop as Number = 0;
    private var mSecX as Number = 0;
    private var mSecTop as Number = 0;
    private var mColonS as Number = 12;
    private var mColonY1 as Number = 176;
    private var mColonY2 as Number = 212;
    private var mCellW as Number = 124;
    private var mCellIn as Number = 54;
    private var mLabelY as Number = 289;
    private var mValueY as Number = 318;
    private var mBarY as Number = 342;
    private var mBarW as Number = 88;
    private var mBarH as Number = 3;
    private var mLive as Number = 7;
    private var mStepsY as Number = 394;
    private var mGap as Number = 6;         // label/value spacing
    private var mStepsLabelW as Number = 0;
    private var mBatLabelW as Number = 0;

    // ---- fonts ------------------------------------------------------------
    private var mFClock as Graphics.FontType = Graphics.FONT_NUMBER_HOT;
    private var mFClockThin as Graphics.FontType = Graphics.FONT_NUMBER_HOT;
    private var mFSec as Graphics.FontType = Graphics.FONT_XTINY;
    private var mFValue as Graphics.FontType = Graphics.FONT_TINY;
    private var mFMid as Graphics.FontType = Graphics.FONT_XTINY;
    private var mFLabel as Graphics.FontType = Graphics.FONT_XTINY;

    // ---- theme ------------------------------------------------------------
    private var mAccent as Number = 0xE10600;
    private var mFg as Number = 0xF2EFE8;
    private var mDim as Number = 0x8A8A8E;
    private var mGrid as Number = 0x323236;
    private var mAod as Number = 0xA4A4A8;

    // ---- cached strings and derived values (rebuilt at most once a minute) -
    private var mHour as String = "";
    private var mMinute as String = "";
    private var mDate as String = "";
    private var mTemp as String = "";
    private var mCond as String = "";
    private var mTempX as Number = 0;
    private var mBat as String = "";
    private var mBatX as Number = 0;
    private var mBatLit as Number = 0;
    private var mBatLow as Boolean = false;
    private var mBody as String = Fmt.MISSING;
    private var mBodyBar as Number = 0;
    private var mBodyAlert as Boolean = false;
    private var mRecovery as String = Fmt.MISSING;
    private var mRecoveryUnit as String = "H";
    private var mRecoveryBar as Number = 0;
    private var mRecoveryAlert as Boolean = false;
    private var mSteps as String = Fmt.MISSING;
    private var mStepsX as Number = 0;
    private var mStepLit as Number = 0;
    private var mHr as String = Fmt.MISSING;
    private var mHrLive as Boolean = false;

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
        mGrid = c[3];
        mAod = c[4];
    }

    function stop() as Void {
        mData.stop();
    }

    // Design pixels -> device pixels.
    private function px(n as Number) as Number {
        return (n * mW + DESIGN / 2) / DESIGN;
    }

    // Vector font at a design size, never smaller than `minPx` device pixels
    // (both FR570 sizes share one pixel density, so the 42 mm model would
    // otherwise get physically smaller labels). System font if unavailable.
    private function vfont(face as String, size as Number, minPx as Number, fallback as Graphics.FontType) as Graphics.FontType {
        if (Graphics has :getVectorFont) {
            var s = px(size);
            if (s < minPx) {
                s = minPx;
            }
            var f = Graphics.getVectorFont({ :face => [face, "RobotoRegular"], :size => s });
            if (f != null) {
                return f;
            }
        }
        return fallback;
    }

    function onLayout(dc as Dc) as Void {
        mW = dc.getWidth();
        mCx = mW / 2;
        mCy = dc.getHeight() / 2;

        // Four sizes only: clock, values, secondary, labels.
        mFClock = vfont("RobotoCondensedBold", 156, 0, Graphics.FONT_NUMBER_HOT);
        mFClockThin = vfont("RobotoCondensedRegular", 156, 0, Graphics.FONT_NUMBER_HOT);
        mFValue = vfont("RobotoCondensedBold", 48, 0, Graphics.FONT_TINY);
        mFMid = vfont("RobotoCondensedBold", 30, 27, Graphics.FONT_XTINY);
        mFSec = vfont("RobotoCondensedRegular", 34, 29, Graphics.FONT_XTINY);
        mFLabel = vfont("RobotoCondensedBold", 23, 22, Graphics.FONT_XTINY);

        mPenTick = px(2);
        mPenHead = px(5);
        mPenGauge = px(6);
        mGaugeR = px(204);
        mXL = mCx - px(146);
        mXR = mCx + px(146);
        mY1 = px(128);
        mY2 = px(272);
        mY3 = px(352);
        mRule1 = px(164);
        mRule2 = px(187);
        mSepX = px(62);
        mSepPad = px(10);
        mBatY = px(58);
        mRowY = px(102);
        mHalfGap = px(18);
        mColonS = px(12);
        mColonY1 = px(176);
        mColonY2 = px(212);
        mCellW = px(124);
        mCellIn = px(54);
        mLabelY = px(289);
        mValueY = px(318);
        mBarY = px(342);
        mBarW = px(88);
        mBarH = px(3);
        mLive = px(7);
        mStepsY = px(394);
        mGap = px(6);
        mStepsLabelW = dc.getTextWidthInPixels("STEPS", mFLabel);
        mBatLabelW = dc.getTextWidthInPixels("BAT", mFLabel);

        // Clock: HH right-justified and MM left-justified about the centre axis,
        // so the colon sits exactly on it. The digit block (cap height) is
        // optically centred on y = 200; seconds share the clock's baseline.
        var ascent = Graphics.getFontAscent(mFClock);
        mClockTop = px(244) - ascent;
        mSecTop = mClockTop + ascent - Graphics.getFontAscent(mFSec);
        mSecX = mCx + mHalfGap + dc.getTextWidthInPixels("00", mFClock) + px(7);

        // Lap ring tables. Trig happens here and never in the frame path.
        // Tick length: 20-second sector marks > 5-second majors > minors.
        var ticks = new Array<Number>[240];
        var heads = new Array<Number>[120];
        var ro = mW / 2 - px(3);
        var rh = ro - px(15);
        for (var i = 0; i < 60; i++) {
            var a = i * Math.PI / 30.0;
            var s = Math.sin(a);
            var c = Math.cos(a);
            var len = px(6);
            if (i % 20 == 0) {
                len = px(18);
            } else if (i % 5 == 0) {
                len = px(10);
            }
            var ri = ro - len;
            ticks[i * 4] = mCx + Math.round(ro * s).toNumber();
            ticks[i * 4 + 1] = mCy - Math.round(ro * c).toNumber();
            ticks[i * 4 + 2] = mCx + Math.round(ri * s).toNumber();
            ticks[i * 4 + 3] = mCy - Math.round(ri * c).toNumber();
            heads[i * 2] = mCx + Math.round(rh * s).toNumber();
            heads[i * 2 + 1] = mCy - Math.round(rh * c).toNumber();
        }
        mTicks = ticks;
        mHeads = heads;
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
            // Always 24-hour, by design ("race control" time), whatever the
            // watch's 12/24 h setting says.
            mHour = clock.hour.format("%02d");
            mMinute = clock.min.format("%02d");
            var d = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
            mDate = Fmt.date(d.day_of_week as Number, d.day as Number, d.month as Number);
        }

        if (low) {
            drawAlwaysOn(dc, clock.min);
            return;
        }

        if (minuteChanged || mDirty || mData.dirty) {
            mDirty = false;
            refreshTelemetry(dc);
        }
        if (mData.refreshHeartRate()) {
            var hr = mData.hr;
            mHr = Fmt.number(hr);
            mHrLive = (hr != null);
        }
        drawFull(dc, clock.sec);
    }

    // At most once a minute: pull slow data, rebuild cached strings, measure
    // the few strings whose width changes.
    private function refreshTelemetry(dc as Dc) as Void {
        var t = mData;
        t.refreshSlow();

        mBat = t.battery.toString() + "%";
        mBatLit = Fmt.segments(t.battery, 100, BAT_SEGS);
        mBatLow = (t.battery <= BATTERY_ALERT) && !t.charging;
        mBatX = mCx - (mBatLabelW + mGap + dc.getTextWidthInPixels(mBat, mFMid)) / 2;

        var bb = t.bodyBattery;
        mBody = Fmt.number(bb);
        mBodyBar = Fmt.bar(bb, 100, mBarW);
        mBodyAlert = (bb != null && bb <= BODY_ALERT);

        var rec = t.recoveryMin;
        mRecovery = Fmt.recoveryValue(rec);
        mRecoveryUnit = Fmt.recoveryUnit(rec);
        mRecoveryBar = Fmt.bar(rec, RECOVERY_FULL, mBarW);
        mRecoveryAlert = (rec != null && rec >= RECOVERY_ALERT);

        mSteps = Fmt.number(t.steps);
        mStepLit = Fmt.segments(t.steps, t.stepGoal, STEP_SEGS);
        mStepsX = mCx - (mStepsLabelW + mGap + dc.getTextWidthInPixels(mSteps, mFMid)) / 2;

        var temp = t.temperature;
        var cond = t.condition;
        mTemp = (temp != null) ? temp.toString() + "°" : ((cond != null) ? "" : "--°");
        mCond = (cond != null) ? cond : "";
        mTempX = mXR;
        if (mCond.length() > 0) {
            mTempX -= dc.getTextWidthInPixels(mCond, mFLabel) + mGap;
        }
    }

    // ---- awake -----------------------------------------------------------

    private function drawFull(dc as Dc, sec as Number) as Void {
        var cx = mCx;
        var cy = mCy;
        var left = Graphics.TEXT_JUSTIFY_LEFT;
        var right = Graphics.TEXT_JUSTIFY_RIGHT;
        var vc = Graphics.TEXT_JUSTIFY_VCENTER;
        var trans = Graphics.COLOR_TRANSPARENT;
        var accent = mAccent;
        var fg = mFg;
        var dim = mDim;
        var grid = mGrid;

        // Lap ring: ticks behind the head are "elapsed" and one step brighter.
        dc.setAntiAlias(true);
        var t = mTicks;
        var split = sec * 4;
        dc.setPenWidth(mPenTick);
        dc.setColor(dim, trans);
        for (var i = 0; i < split; i += 4) {
            if (i % 20 != 0) {
                dc.drawLine(t[i], t[i + 1], t[i + 2], t[i + 3]);
            }
        }
        dc.setColor(grid, trans);
        for (var i = split; i < 240; i += 4) {
            if (i % 20 != 0) {
                dc.drawLine(t[i], t[i + 1], t[i + 2], t[i + 3]);
            }
        }
        dc.setColor(fg, trans);
        var i5 = 0;
        for (; i5 < split; i5 += 20) {
            dc.drawLine(t[i5], t[i5 + 1], t[i5 + 2], t[i5 + 3]);
        }
        dc.setColor(dim, trans);
        for (; i5 < 240; i5 += 20) {
            dc.drawLine(t[i5], t[i5 + 1], t[i5 + 2], t[i5 + 3]);
        }
        dc.setPenWidth(mPenHead);
        dc.setColor(accent, trans);
        dc.drawLine(t[split], t[split + 1], mHeads[sec * 2], mHeads[sec * 2 + 1]);

        // Gauge track. Battery: 10 segments over the top, left to right.
        // Steps: 15 segments under the bottom, left to right; the last one
        // turns accent when the goal is reached.
        var r = mGaugeR;
        dc.setPenWidth(mPenGauge);
        var lit = mBatLit;
        dc.setColor(mBatLow ? accent : fg, trans);
        for (var i = 0; i < BAT_SEGS; i++) {
            if (i == lit) {
                dc.setColor(grid, trans);
            }
            dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, 119 - 6 * i, 115 - 6 * i);
        }
        lit = mStepLit;
        dc.setColor(fg, trans);
        for (var i = 0; i < STEP_SEGS; i++) {
            if (i == lit) {
                dc.setColor(grid, trans);
            } else if (i == STEP_SEGS - 1 && lit == STEP_SEGS) {
                dc.setColor(accent, trans);     // goal reached
            }
            dc.drawArc(cx, cy, r, Graphics.ARC_COUNTER_CLOCKWISE, 226 + 6 * i, 230 + 6 * i);
        }

        // Everything below is axis-aligned: anti-aliasing would only cost time.
        dc.setAntiAlias(false);
        dc.setPenWidth(1);
        dc.setColor(grid, trans);
        dc.drawLine(cx - mRule1, mY1, cx + mRule1, mY1);
        dc.drawLine(cx - mRule2, mY2, cx + mRule2, mY2);
        dc.drawLine(mXL, mY3, mXR, mY3);
        dc.drawLine(cx - mSepX, mY2 + mSepPad, cx - mSepX, mY3 - mSepPad);
        dc.drawLine(cx + mSepX, mY2 + mSepPad, cx + mSepX, mY3 - mSepPad);

        // Battery.
        dc.setColor(dim, trans);
        dc.drawText(mBatX, mBatY, mFLabel, mData.charging ? "CHG" : "BAT", left | vc);
        dc.setColor(mBatLow ? accent : fg, trans);
        dc.drawText(mBatX + mBatLabelW + mGap, mBatY, mFMid, mBat, left | vc);

        // Date on the left margin, weather on the right margin.
        dc.setColor(fg, trans);
        dc.drawText(mXL, mRowY, mFMid, mDate, left | vc);
        if (mTemp.length() > 0) {
            dc.setColor(mTemp.equals("--°") ? dim : fg, trans);
            dc.drawText(mTempX, mRowY, mFMid, mTemp, right | vc);
        }
        if (mCond.length() > 0) {
            dc.setColor(dim, trans);
            dc.drawText(mXR, mRowY, mFLabel, mCond, right | vc);
        }

        // Clock on the centre axis, square colon marks, quiet seconds.
        dc.setColor(fg, trans);
        dc.drawText(cx - mHalfGap, mClockTop, mFClock, mHour, right);
        dc.drawText(cx + mHalfGap, mClockTop, mFClock, mMinute, left);
        dc.setColor(dim, trans);
        dc.drawText(mSecX, mSecTop, mFSec, sec.format("%02d"), left);
        dc.setColor(accent, trans);
        var cs = mColonS;
        dc.fillRectangle(cx - cs / 2, mColonY1, cs, cs);
        dc.fillRectangle(cx - cs / 2, mColonY2, cs, cs);

        // Telemetry cells.
        drawCell(dc, cx - mCellW, "HR", "BPM", mHr, !mHrLive, 0, false, mHrLive);
        drawCell(dc, cx, "BODY", "%", mBody, mBodyBar == 0 && mBody.equals(Fmt.MISSING), mBodyBar, mBodyAlert, false);
        drawCell(dc, cx + mCellW, "RECOV", mRecoveryUnit, mRecovery, mRecovery.equals(Fmt.MISSING), mRecoveryBar, mRecoveryAlert, false);

        // Steps.
        dc.setColor(dim, trans);
        dc.drawText(mStepsX, mStepsY, mFLabel, "STEPS", left | vc);
        dc.setColor(fg, trans);
        dc.drawText(mStepsX + mStepsLabelW + mGap, mStepsY, mFMid, mSteps, left | vc);
    }

    // One channel: name left, unit right, value below, range bar at the foot.
    // `live` puts an accent square at the head of the bar (heart rate has no
    // range to plot, so its bar is just the track plus the live marker).
    private function drawCell(dc as Dc, x as Number, name as String, unit as String, value as String,
            missing as Boolean, bar as Number, alert as Boolean, live as Boolean) as Void {
        var trans = Graphics.COLOR_TRANSPARENT;
        var vc = Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(mDim, trans);
        dc.drawText(x - mCellIn, mLabelY, mFLabel, name, Graphics.TEXT_JUSTIFY_LEFT | vc);
        dc.drawText(x + mCellIn, mLabelY, mFLabel, unit, Graphics.TEXT_JUSTIFY_RIGHT | vc);
        var c = missing ? mDim : (alert ? mAccent : mFg);
        dc.setColor(c, trans);
        dc.drawText(x, mValueY, mFValue, value, Graphics.TEXT_JUSTIFY_CENTER | vc);

        var bx = x - mBarW / 2;
        dc.setColor(mGrid, trans);
        dc.fillRectangle(bx, mBarY, mBarW, mBarH);
        if (bar > 0) {
            dc.setColor(c, trans);
            dc.fillRectangle(bx, mBarY, bar, mBarH);
        }
        if (live) {
            dc.setColor(mAccent, trans);
            dc.fillRectangle(bx, mBarY - (mLive - mBarH) / 2, mLive, mLive);
        }
    }

    // ---- always-on (AMOLED low power) ------------------------------------

    // Same skeleton as the awake face (clock on the axis, date on the left
    // margin, one rule) so nothing jumps on wake, but thin, grey and outline
    // only. The block shifts every minute on both axes (5 x 7 = 35 positions,
    // at most 6 px from home) to spread pixel wear.
    private function drawAlwaysOn(dc as Dc, min as Number) as Void {
        var dx = (min % 5 - 2) * 3;
        var dy = (min % 7 - 3) * 2;
        var cx = mCx + dx;
        var trans = Graphics.COLOR_TRANSPARENT;
        dc.setColor(mAod, trans);
        dc.drawText(cx - mHalfGap, mClockTop + dy, mFClockThin, mHour, Graphics.TEXT_JUSTIFY_RIGHT);
        dc.drawText(cx + mHalfGap, mClockTop + dy, mFClockThin, mMinute, Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(mDim, trans);
        dc.setPenWidth(1);
        var cs = mColonS;
        dc.drawRectangle(cx - cs / 2, mColonY1 + dy, cs, cs);
        dc.drawRectangle(cx - cs / 2, mColonY2 + dy, cs, cs);
        dc.drawText(mXL + dx, mRowY + dy, mFMid, mDate, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(mGrid, trans);
        dc.drawLine(mXL + dx, mY2 + dy, mXR + dx, mY2 + dy);
    }
}
