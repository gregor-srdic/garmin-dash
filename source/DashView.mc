import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Activity;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Sensor;
import Toybox.Application;
import Toybox.UserProfile;
import Toybox.Math;

class DashView extends WatchUi.DataField {
    private var mSpeed = 0.0;
    private var mAvgSpeed = 0.0;
    private var mMaxSpeed = 0.0;
    private var mDistance = 0.0;
    private var mElapsedMs = 0;
    private var mHeartRate as Number? = null;
    private var mPower3s = 0;
    private var mTemp = 0.0;
    private var mCadence = 0;
    private var mCalories = 0;
    private var mAvgHeartRate = 0;
    private var mAvgCadence = 0;
    private var mAvgPower = 0;
    private var mMaxPower = 0;
    private var mHasPowerData = false;

    // Header Fields
    private var mGrade = 0.0;
    private var mElevation = 0.0;
    private var mAscent = 0.0;
    private var mGearInfo = "--";

    private var mIsMetric = true;
    private var mIsElevationMetric = true;

    // grade calculation (tracked in raw meters, independent of display units)
    private var mGradeLastAlt = null;
    private var mGradeLastDist = null;
    // Consecutive compute() calls that produced no grade update. Once the window
    // anchor is stranded (or its inputs drop out) nothing else can unstick it,
    // so a long enough run of dead computes forces a re-seed.
    private var mGradeStallCount = 0;
    private const GRADE_STALL_LIMIT = 60;

    // Device-specific layout and font profile, set once in initialize()
    private var mDeviceProfile = null;

    // Band geometry every draw function works from. Depends only on the dc
    // dimensions, the device profile and font heights, so it is computed on the
    // first draw and reused; the width/height guard picks up a data-screen
    // layout change without costing anything on a normal frame.
    // Named ...Cache because WatchUi.View already declares a protected mLayout.
    private var mLayoutCache as Lang.Dictionary? = null;
    private var mLayoutWidth = -1;
    private var mLayoutHeight = -1;

    // Palette for the frame being drawn. Recomputed at the top of every
    // onUpdate because the device's dark/light setting can change at runtime;
    // held in fields so the draw pass itself allocates nothing.
    private var mBgColor = Graphics.COLOR_BLACK;
    private var mValuesColor = 0xffffff;
    private var mLabelsColor = 0xeeeeee;
    private var mTrackColor = 0xeeeeee;

    private const COLOR_SPEED = 0x0066ff;
    private const COLOR_HR = 0xff2200;
    private const COLOR_POWER = 0x9900ff;
    private const COLOR_CADENCE = 0xff8800;

    // Zone boundaries for arc coloring, set once in initialize().
    // HR zones come from the user's Garmin profile; power zones are derived from the FTP app setting.
    private var mHrZoneBoundaries = null;
    private var mPowerZoneBoundaries = null;
    private var ftp = null;
    private static var ZONE_COLORS = [
        0x4da6ff, // Z1 - blue
        0x33cc33, // Z2 - green
        0xffcc00, // Z3 - yellow
        0xff8800, // Z4 - orange
        0xff2200, // Z5 - red
    ];

    function initialize() {
        DataField.initialize();
        var settings = System.getDeviceSettings();
        mIsMetric = settings.paceUnits == System.UNIT_METRIC;
        mIsElevationMetric = settings.elevationUnits == System.UNIT_METRIC;
        var deviceType = WatchUi.loadResource(Rez.Strings.deviceType) as String;
        mDeviceProfile = initDeviceProfile(
            settings.screenWidth,
            settings.screenHeight,
            deviceType
        );

        // HR zones: pulled from the user's Garmin Connect profile for the current sport.
        try {
            mHrZoneBoundaries = UserProfile.getHeartRateZones(
                UserProfile.getCurrentSport()
            );
        } catch (e) {
            mHrZoneBoundaries = null;
        }

        // Power zones: prefer the FTP from the user's Garmin Connect profile;
        // fall back to the app's FTP setting if the profile has none set.
        // getFunctionalThresholdPower is API 5.2.2+ (Edge 1040/1050 only); the
        // `has` check is required because a missing symbol is a fatal runtime
        // error rather than a catchable exception.
        ftp = null;
        if (UserProfile has :getFunctionalThresholdPower) {
            try {
                ftp = UserProfile.getFunctionalThresholdPower(
                    Activity.SPORT_CYCLING
                );
            } catch (e) {
                ftp = null;
            }
        }
        if (ftp == null || ftp == 0) {
            ftp = Application.Properties.getValue("ftp");
        }
        // Coggan-style boundaries derived from FTP.
        if (ftp != null && ftp > 0) {
            mPowerZoneBoundaries = [
                0,
                ftp * 0.55,
                ftp * 0.75,
                ftp * 0.9,
                ftp * 1.05,
                ftp * 999,
            ];
        }
    }

    // Returns the zone color for value given a 6-entry boundary array
    // (lower bound of zones 1-5 plus an upper cap), or fallbackColor if
    // boundaries are unavailable.
    private function zoneColor(
        value as Numeric,
        boundaries as Array?,
        fallbackColor as Number
    ) as Number {
        if (boundaries == null || boundaries.size() < 6) {
            return fallbackColor;
        }
        for (var i = 1; i <= 4; i++) {
            if (value < boundaries[i]) {
                return ZONE_COLORS[i - 1];
            }
        }
        return ZONE_COLORS[4];
    }

    // The DataField object outlives a timer reset, so the grade window has to be
    // cleared explicitly. Otherwise the anchor keeps the finished activity's
    // distance, the new activity's distance starts back at zero, and no update
    // can ever land again.
    function onTimerReset() as Void {
        mGrade = 0.0;
        mGradeLastAlt = null;
        mGradeLastDist = null;
        mGradeStallCount = 0;
    }

    function compute(info as Activity.Info) as Void {
        var settings = System.getDeviceSettings();
        var actInfo = Activity.getActivityInfo();

        // Current Speed
        if (info.currentSpeed != null) {
            mSpeed = mIsMetric
                ? info.currentSpeed * 3.6
                : info.currentSpeed * 2.23694;
        } else {
            mSpeed = 0.0;
        }

        // Average Speed
        if (info.averageSpeed != null) {
            mAvgSpeed = mIsMetric
                ? info.averageSpeed * 3.6
                : info.averageSpeed * 2.23694;
        }

        // Max Speed
        if (info.maxSpeed != null) {
            mMaxSpeed = mIsMetric
                ? info.maxSpeed * 3.6
                : info.maxSpeed * 2.23694;
        }

        // Distance
        if (info.elapsedDistance != null) {
            mDistance = mIsMetric
                ? info.elapsedDistance
                : info.elapsedDistance * 0.621371;
        }

        // Elapsed Time
        if (info.timerTime != null) {
            mElapsedMs = info.timerTime;
        }

        // Heart Rate
        mHeartRate = null;
        if (info.currentHeartRate != null) {
            mHeartRate = info.currentHeartRate;
        } else if (actInfo != null && actInfo.currentHeartRate != null) {
            mHeartRate = actInfo.currentHeartRate;
        }
        if (info.averageHeartRate != null) {
            mAvgHeartRate = info.averageHeartRate;
        }

        // Shifting
        mGearInfo = "--";
        var rear =
            actInfo != null && actInfo has :rearDerailleurIndex
                ? actInfo.rearDerailleurIndex
                : null;
        var front =
            actInfo != null && actInfo has :frontDerailleurIndex
                ? actInfo.frontDerailleurIndex
                : null;
        if (rear) {
            if (rear > 13 || rear < 1) {
                rear = 1;
            }
            mGearInfo = rear.format("%d");
            if (front) {
                if (front > 3 || front < 1) {
                    front = 1;
                }
                mGearInfo = front.format("%d") + ":" + mGearInfo;
            }
        }

        // 3s Power
        mHasPowerData = false;
        if (info.currentPower != null) {
            mPower3s = info.currentPower;
            mHasPowerData = true;
        } else {
            if (actInfo != null && actInfo.currentPower != null) {
                mPower3s = actInfo.currentPower;
                mHasPowerData = true;
            }
        }

        // Average Power
        if (info.averagePower != null) {
            mAvgPower = info.averagePower;
            mHasPowerData = true;
        }

        // Max Power
        if (info.maxPower != null) {
            mMaxPower = info.maxPower;
            mHasPowerData = true;
        }

        // Cadence
        if (info.currentCadence != null) {
            mCadence = info.currentCadence;
            if (mCadence > 150) {
                mCadence = mCadence / 2;
            }
        }
        if (info.averageCadence != null) {
            mAvgCadence = info.averageCadence;
            if (mAvgCadence > 150) {
                mAvgCadence = mAvgCadence / 2;
            }
        }

        // Calories
        if (info.calories != null) {
            mCalories = info.calories;
        }

        // --- TEMPERATURE RESOLUTION ---
        var rawTemp = Storage.getValue("sensorTemperature");

        // Priority 2: Activity.Info (Standard way)
        if (info has :ambientTemperature && info.ambientTemperature != null) {
            rawTemp = info.ambientTemperature;
        }

        // Priority 3: Activity.getActivityInfo (Final fallback)
        if (rawTemp == null) {
            if (
                actInfo != null &&
                actInfo has :ambientTemperature &&
                actInfo.ambientTemperature != null
            ) {
                rawTemp = actInfo.ambientTemperature;
            }
        }

        // Priority 4: SensorHistory fallback (for older CIQ devices like Edge 1030)
        if (rawTemp == null) {
            if (
                Toybox has :SensorHistory &&
                SensorHistory has :getTemperatureHistory
            ) {
                var iter = SensorHistory.getTemperatureHistory({
                    :period => 1,
                    :order => SensorHistory.ORDER_NEWEST_FIRST,
                });
                if (iter != null) {
                    var sample = iter.next();
                    if (sample != null && sample.data != null) {
                        rawTemp = sample.data;
                    }
                }
            }
        }

        if (rawTemp != null) {
            if (settings.temperatureUnits == System.UNIT_STATUTE) {
                mTemp = (rawTemp * 9.0) / 5.0 + 32.0;
            } else {
                mTemp = rawTemp.toFloat();
            }
        }

        // Elevation Data
        var altMult = mIsElevationMetric ? 1.0 : 3.28084;
        var rawAlt =
            info.altitude != null
                ? info.altitude
                : actInfo != null && actInfo has :altitude
                  ? actInfo.altitude
                  : null;
        if (rawAlt != null) {
            mElevation = rawAlt * altMult;
        }
        if (info.totalAscent != null) {
            mAscent = info.totalAscent * altMult;
        }
        calculateGrade(rawAlt, info.elapsedDistance);
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        mBgColor = getBackgroundColor();
        var isDark = mBgColor == Graphics.COLOR_BLACK;
        mValuesColor = isDark ? 0xffffff : Graphics.COLOR_BLACK;
        mLabelsColor = isDark ? 0xeeeeee : Graphics.COLOR_LT_GRAY;
        mTrackColor = isDark ? 0xeeeeee : 0xdddddd;

        var width = dc.getWidth();
        var height = dc.getHeight();
        if (
            mLayoutCache == null ||
            mLayoutWidth != width ||
            mLayoutHeight != height
        ) {
            mLayoutCache = computeLayout(dc);
            mLayoutWidth = width;
            mLayoutHeight = height;
        }
        var layout = mLayoutCache;

        dc.setColor(mBgColor, mBgColor);
        dc.clear();

        if (layout[:variant] == :compact) {
            drawCompactTopBar(dc, layout);
            drawCompactSpeedGauge(dc, layout);
            drawCompactBars(dc, layout);
            drawCompactFooter(dc, layout);
        } else {
            drawTopBar(dc, layout);
            drawSpeedGauge(dc, layout);
            drawMiddleRow(dc, layout);
            drawPanels(dc, layout);
            drawFooter(dc, layout);
        }
    }

    // --- LAYOUT -------------------------------------------------------------

    // Returns the y-bands and gauge geometry that the five draw functions work
    // from, so no draw call derives its own position. Keys:
    //   :width :height :centerX :colW              — screen basics
    //   :topBarY :topBarH                          — band 1, top stats bar
    //   :radius :centerY :trackWidth               — band 2, speed gauge
    //   :elapsedY :middleRowY                      — band 3, the two text rows
    //   :panelTop :panelH :panelCenterY :panelRadius :panelBarW
    //   :panelLeftX :panelRightX :panelLabelOffset — band 4, HR / power panels
    //   :footerY                                   — band 5, bottom stats bar
    //   :xtinyH :rowValueH                         — font heights the bands stack from
    private function computeLayout(dc as Graphics.Dc) as Lang.Dictionary {
        if (mDeviceProfile[:layoutVariant] == :compact) {
            return computeCompactLayout(dc);
        }
        return computeFullLayout(dc);
    }

    // The 1.67-aspect layout every currently shipped device uses: hand-tuned
    // pixel offsets from the device profile, positions derived from screen
    // width with the footer anchored to height.
    private function computeFullLayout(dc as Graphics.Dc) as Lang.Dictionary {
        var width = dc.getWidth();
        var height = dc.getHeight();

        var topBarH = (height * 0.081).toNumber();

        var minDim = width < height ? width : height;
        var trackWidth = (width * 0.083).toNumber();
        var radius = minDim * mDeviceProfile[:gaugeRadiusFactor];
        var centerX = width / 2.0;
        var speedGaugeCenterYOffset = mDeviceProfile[:speedGaugeCenterYOffset];
        var centerY = radius + topBarH + trackWidth + speedGaugeCenterYOffset;

        var xtinyH = dc.getFontHeight(Graphics.FONT_XTINY);
        var rowValueH = dc.getFontHeight(mDeviceProfile[:rowValueFont]);

        // Footer is anchored to the bottom so its value and the label under it
        // both fit; the panel band absorbs whatever is left over.
        var footerY = height - rowValueH - xtinyH + 1;

        var panelTop = centerY + radius * 0.5 + topBarH * 2;
        var panelH = footerY - panelTop - (height * 0.01).toNumber();
        var barW = (width * 0.063).toNumber();
        var lBarX = (width * 0.021).toNumber();
        var rBarX = width - (width * 0.038).toNumber();

        return {
            :variant => :full,
            :width => width,
            :height => height,
            :centerX => centerX,
            :colW => width / 3.0,

            :topBarY => 5 + mDeviceProfile[:topBarYOffset],
            :topBarH => topBarH,

            :radius => radius,
            :centerY => centerY,
            :trackWidth => trackWidth,

            :elapsedY =>
                2 * radius +
                topBarH / 2 +
                xtinyH +
                1 +
                mDeviceProfile[:elapsedTimeYOffset],
            :middleRowY =>
                2 * radius +
                topBarH * 2 -
                speedGaugeCenterYOffset +
                mDeviceProfile[:cadenceLineYOffset],

            :panelTop => panelTop,
            :panelH => panelH,
            :panelCenterY =>
                panelTop +
                panelH / 2.0 +
                (height * 0.01).toNumber() +
                mDeviceProfile[:hrPwrGaugeCenterYOffset],
            :panelRadius => centerX - lBarX - barW / 2.0,
            :panelBarW => barW,
            :panelLeftX => (lBarX + barW / 2 + centerX) / 2.0,
            :panelRightX => (centerX + rBarX - barW / 2) / 2.0,
            :panelLabelOffset => (height * 0.088).toNumber(),

            :footerY => footerY,

            :xtinyH => xtinyH,
            :rowValueH => rowValueH,
        };
    }

    // The 1.31-aspect layout for the 246x322 devices (Edge 830 / 840).
    //
    // Unlike computeFullLayout this derives every band from measured font
    // heights instead of hand-tuned pixel offsets, because the two devices
    // sharing this resolution do *not* share font metrics: at FONT_LARGE the
    // 830 is 41 px tall against the 840's 31, while their number fonts match to
    // within 1 px. Absolute offsets tuned on one would be wrong on the other.
    //
    // Bands are laid out from the outside in — top bar off the top edge, footer
    // and zone bars off the bottom edge — and the speed gauge takes whatever is
    // left, capped so it does not run into the side edges. Keys are the ones
    // computeFullLayout documents plus:
    //   :barsValueY :barsBarY :barsBarH :barsSegLen :barsSegGap
    //   :barsLeftX0 :barsLeftX1 :barsRightX0 :barsRightX1  — band 3, zone bars
    //   :topBarValueY                                      — band 1 value row,
    //                                                        under the label row at :topBarY
    //   :speedAvgLabelY :speedAvgValueY                    — the AVG / MAX pair
    //                                                        in the gauge crown
    //   :speedAvgColOffset                                 — how far off centre
    //                                                        that pair's two
    //                                                        columns sit
    //   :colW                                              — band 1 column width,
    //                                                        a quarter of the screen
    //   :footerLabelY                                      — band 4 label row
    //   :barValueH                                         — zone bar value font height
    private function computeCompactLayout(dc as Graphics.Dc) as Lang.Dictionary {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2.0;

        var xtinyH = dc.getFontHeight(Graphics.FONT_XTINY);
        var rowValueH = dc.getFontHeight(mDeviceProfile[:rowValueFont]);
        var barValueH = dc.getFontHeight(mDeviceProfile[:barValueFont]);

        var pad = (height * 0.012).toNumber();
        var edge = (width * 0.025).toNumber();

        // Band 1: clock and temperature, each under an xtiny label. The label
        // row costs the gauge nothing here — on both 830 and 840 the radius is
        // bounded by screen width, not by this band's height.
        var topBarY = pad;
        // The label and value rows are stacked at their full font heights, with
        // none of the leading slack taken back out — the extra air reads better
        // than the tighter stack the full layout uses.
        var topBarValueY = topBarY + xtinyH;

        // Band 4: value row with its label row tucked under it. The -2 keeps the
        // band bottom exactly `pad` off the screen edge: the label bottom lands
        // at footerY + rowValueH + xtinyH - 2, which is what is subtracted here.
        var footerY = height - pad - (rowValueH + xtinyH - 2);

        // The speed gauge's pen width, and with it the thickness of every lit
        // element on the screen: band 3's zone bars are drawn this tall so the
        // three gauges read as one weight rather than three.
        var trackWidth = (width * 0.075).toNumber();

        // Band 3: label and value share a line, with the bar under them. This
        // is the band's unlifted position — band 2 is measured against it, then
        // the band is lifted clear of the gauge below (see barsLift).
        var barH = trackWidth;
        var barsValueY = footerY - pad * 2 - (barValueH + pad + barH);

        // Band 2: everything left between bands 1 and 3. The gauge sweeps 240
        // degrees from 210, so it stands `radius` above its center and
        // `radius / 2` below it, plus half the track width at each end.
        var gaugeTop = topBarValueY + rowValueH + pad * 2;
        var gaugeBandH = barsValueY - pad * 2 - gaugeTop;
        var radius = width * mDeviceProfile[:gaugeRadiusFactor];
        var radiusFitH = (gaugeBandH - trackWidth) / 1.5;
        if (radius > radiusFitH) {
            radius = radiusFitH;
        }
        var radiusFitW = centerX - trackWidth / 2.0 - edge;
        if (radius > radiusFitW) {
            radius = radiusFitW;
        }
        // A data field can be placed as one cell of a multi-field data screen,
        // in which case dc is a fraction of the panel and the four bands alone
        // are taller than it. Floor the gauge rather than hand drawArc a
        // negative radius; the text bands still draw and stay readable.
        if (radius < 0) {
            radius = 0;
        }
        // Centre the gauge in whatever band it did not need.
        var gaugeSlack = (gaugeBandH - (radius * 1.5 + trackWidth)) / 2.0;
        if (gaugeSlack < 0) {
            gaugeSlack = 0;
        }
        // No hand-tuned lift here: the gauge sits where centring in its band
        // puts it. It used to be raised 8 px off centre by eye to compensate for
        // the crown's open bottom, which read as too high once the top bar and
        // footer went up a font size and closed in on it.
        var centerY = gaugeTop + gaugeSlack + trackWidth / 2.0 + radius;

        // The one hand-tuned offset on this path, and the reason band 2 is
        // measured against the unlifted barsValueY above: band 3 sat lower in
        // the gap under the gauge crown than it needed to. Lifting it here
        // rather than at its definition keeps the gauge where it is — folded into
        // barsValueY earlier it would have eaten the gauge band and carried the
        // arc up with it. Clamped against the bottom of the arc, because on a
        // small dc (one cell of a multi-field screen) the gap it eats is not
        // there to take.
        var barsLift = 20;
        var gaugeBottom = centerY + radius / 2.0 + trackWidth / 2.0;
        if (barsValueY - barsLift < gaugeBottom) {
            barsLift = (barsValueY - gaugeBottom).toNumber();
        }
        if (barsLift < 0) {
            barsLift = 0;
        }
        barsValueY -= barsLift;

        // The AVG / MAX pair sits inside the crown above the speed readout, as
        // it does on :full. Stacked upward from the top of the speed number
        // rather than dropped at a fraction of the radius: at FONT_MEDIUM the
        // 830 is 26 px against the 840's 19, so one radius fraction would leave
        // a gap on one device and an overlap on the other. The +2s are the same
        // text-box leading slack the footer and band 3 take out.
        //
        // :crownYOffset then nudges the whole pair, label and value together.
        // This is the one pixel offset on the :compact path, and it is only safe
        // because the two 246x322 devices now take separate profiles — a value
        // tuned against the 840's font metrics is never applied to the 830's.
        var speedH = dc.getFontHeight(mDeviceProfile[:speedFont]);
        var avgValueH = dc.getFontHeight(mDeviceProfile[:crownValueFont]);
        var crownYOffset = mDeviceProfile[:crownYOffset];
        var speedAvgValueY =
            centerY - speedH / 2.0 - avgValueH + 2 + crownYOffset;
        var speedAvgLabelY = speedAvgValueY - xtinyH + 2;

        // How far off centre the AVG / MAX columns sit. :full and the 830 can
        // afford the flat 0.35 of the radius this pair was designed around, but
        // the 840's larger crown font pushes the stack higher, and the crown
        // narrows as it goes up: at 0.35 the top corner of the value box lands
        // 0.45 px off the arc's inner edge there, against 13 px on the 830.
        //
        // So derive it rather than pin it. The binding point is the top corner
        // of the value box — the box's widest row at its narrowest crown height
        // — and the string measured is a two-digit speed, the widest that leaves
        // the pair room to sit side by side. A three-digit speed is wider than
        // half the crown at this height on the 840, so no offset both clears the
        // arc and keeps the two values apart; sizing for it would push them into
        // each other, which reads worse than clipping the arc. Two-digit it is.
        var crownValueW = dc.getTextWidthInPixels(
            "99.9",
            mDeviceProfile[:crownValueFont]
        );
        var crownInner = radius - trackWidth / 2.0;
        var crownDy = centerY - speedAvgValueY;
        var crownHalf = 0.0;
        if (crownDy < crownInner) {
            crownHalf = Math.sqrt(
                crownInner * crownInner - crownDy * crownDy
            );
        }
        // Outward until the box corner is 2 px off the arc, but never so far in
        // that the two values touch, and never wider than the 0.35 the crown was
        // laid out around. On the 830 the cap binds and nothing changes.
        var avgColOffset = crownHalf - 2 - crownValueW / 2.0;
        var avgColMin = crownValueW / 2.0 + 3;
        if (avgColOffset < avgColMin) {
            avgColOffset = avgColMin;
        }
        if (avgColOffset > radius * 0.35) {
            avgColOffset = radius * 0.35;
        }

        var barLen = centerX - edge * 2;
        var segGap = 2;
        var segLen = (barLen - segGap * 9) / 10.0;

        return {
            :variant => :compact,
            :width => width,
            :height => height,
            :centerX => centerX,

            :topBarY => topBarY,
            :topBarValueY => topBarValueY,
            :colW => width / 4.0,

            :radius => radius,
            :centerY => centerY,
            :trackWidth => trackWidth,
            :speedAvgLabelY => speedAvgLabelY,
            :speedAvgValueY => speedAvgValueY,
            :speedAvgColOffset => avgColOffset,

            :barsValueY => barsValueY,
            :barsBarY => barsValueY + barValueH + pad,
            :barsBarH => barH,
            :barsSegLen => segLen,
            :barsSegGap => segGap,
            :barsLeftX0 => edge,
            :barsLeftX1 => centerX - edge,
            :barsRightX0 => centerX + edge,
            :barsRightX1 => width - edge,

            :footerY => footerY,
            :footerLabelY => footerY + rowValueH - 2,

            :xtinyH => xtinyH,
            :rowValueH => rowValueH,
            :barValueH => barValueH,
        };
    }

    // --- BANDS --------------------------------------------------------------

    // Band 1: temperature, clock and elevation across three columns.
    private function drawTopBar(
        dc as Graphics.Dc,
        layout as Lang.Dictionary
    ) as Void {
        var topBarY = layout[:topBarY];
        var colW = layout[:colW];
        var xtinyH = layout[:xtinyH];
        var rowValueFont = mDeviceProfile[:rowValueFont];
        var hideClockLabel = mDeviceProfile[:hideClockLabel];
        var topBarValueYOffset = mDeviceProfile[:topBarValueYOffset];

        dc.setPenWidth(1);
        dc.setColor(mTrackColor, Graphics.COLOR_TRANSPARENT);

        var now = System.getClockTime();

        var topValues = [
            mTemp.format("%.1f") + "°",
            Lang.format("$1$:$2$", [
                now.hour.format("%02d"),
                now.min.format("%02d"),
            ]),
            mElevation.format("%.0f"),
        ];
        var topLabels = ["TEMP", "CLOCK", "ELEV"];

        for (var i = 0; i < 3; i++) {
            var x = colW * (i + 0.5);
            if (!hideClockLabel || i != 1) {
                dc.setColor(mLabelsColor, Graphics.COLOR_TRANSPARENT);
                dc.drawText(
                    x,
                    topBarY + 2,
                    Graphics.FONT_XTINY,
                    topLabels[i],
                    Graphics.TEXT_JUSTIFY_CENTER
                );
            }
            dc.setColor(mValuesColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                x,
                topBarY + 2 + xtinyH + topBarValueYOffset,
                rowValueFont,
                topValues[i],
                Graphics.TEXT_JUSTIFY_CENTER
            );
        }
    }

    // Band 2: the segmented speed arc, the AVG/MAX pair inside its crown, and
    // the central speed readout with its unit label.
    private function drawSpeedGauge(
        dc as Graphics.Dc,
        layout as Lang.Dictionary
    ) as Void {
        var centerX = layout[:centerX];
        var centerY = layout[:centerY];
        var radius = layout[:radius];
        var speedGaugeCenterYOffset = mDeviceProfile[:speedGaugeCenterYOffset];
        var speedYOffset = mDeviceProfile[:speedYOffset];
        var avgLabelOffset = mDeviceProfile[:avgLabelOffset];
        var speedAvgValueOffset = mDeviceProfile[:speedAvgValueOffset];

        var maxVal = mIsMetric ? 60.0 : 40.0;
        var gaugeStart = 210.0;
        var gaugeSweep = 240.0;

        // --- SEGMENTED ARC GAUGE (SPEED) ---
        var arcSegCount = 24;
        var segArcLen = gaugeSweep / arcSegCount;
        var segGapDeg = 2.5;
        var ratio = mSpeed / maxVal;
        if (ratio > 1.0) {
            ratio = 1.0;
        }
        var litArcSegs = (ratio * arcSegCount + 0.5).toNumber();

        dc.setPenWidth(layout[:trackWidth]);
        for (var i = 0; i < arcSegCount; i++) {
            var segStartDeg = gaugeStart - i * segArcLen;
            var segEndDeg = segStartDeg - segArcLen + segGapDeg;
            dc.setColor(
                i < litArcSegs ? COLOR_SPEED : mTrackColor,
                Graphics.COLOR_TRANSPARENT
            );
            dc.drawArc(
                centerX,
                centerY,
                radius,
                Graphics.ARC_CLOCKWISE,
                segStartDeg,
                segEndDeg
            );
        }

        // --- AVG / MAX ABOVE SPEED ---
        dc.setColor(mLabelsColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            centerX - radius * 0.35,
            centerY - radius * 0.65 + avgLabelOffset,
            Graphics.FONT_XTINY,
            "AVG",
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            centerX + radius * 0.35,
            centerY - radius * 0.65 + avgLabelOffset,
            Graphics.FONT_XTINY,
            "MAX",
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.setColor(mValuesColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            centerX - radius * 0.35,
            centerY - radius * 0.54 + avgLabelOffset + speedAvgValueOffset,
            Graphics.FONT_MEDIUM,
            mAvgSpeed.format("%.1f"),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            centerX + radius * 0.35,
            centerY - radius * 0.54 + avgLabelOffset + speedAvgValueOffset,
            Graphics.FONT_MEDIUM,
            mMaxSpeed.format("%.1f"),
            Graphics.TEXT_JUSTIFY_CENTER
        );

        // --- CENTRAL SPEED READOUT ---
        dc.setColor(mValuesColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            centerY + speedGaugeCenterYOffset + speedYOffset,
            mDeviceProfile[:speedFont],
            mSpeed.format("%.1f"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
        dc.setColor(mLabelsColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            centerY + radius * 0.3 + speedYOffset,
            mDeviceProfile[:unitLabelFont],
            mIsMetric ? "KMH" : "MPH",
            Graphics.TEXT_JUSTIFY_CENTER
        );
    }

    // Band 3: elapsed time, then the cadence / gear / grade row under it.
    private function drawMiddleRow(
        dc as Graphics.Dc,
        layout as Lang.Dictionary
    ) as Void {
        var width = layout[:width];
        var centerX = layout[:centerX];
        var xtinyH = layout[:xtinyH];
        var rowValueFont = mDeviceProfile[:rowValueFont];
        var timeLabelOffset = mDeviceProfile[:timeLabelOffset];
        var middleRowLabelOffset = mDeviceProfile[:middleRowLabelOffset];

        // --- ELAPSED TIME ---
        var totalSecs = mElapsedMs / 1000;
        var elapsedStr = Lang.format("$1$:$2$:$3$", [
            (totalSecs / 3600).format("%d"),
            ((totalSecs % 3600) / 60).format("%02d"),
            (totalSecs % 60).format("%02d"),
        ]);

        var elapsedY = layout[:elapsedY];
        dc.setColor(mLabelsColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            elapsedY - xtinyH - 1 + timeLabelOffset,
            Graphics.FONT_XTINY,
            "TIME",
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.setColor(mValuesColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            elapsedY,
            rowValueFont,
            elapsedStr,
            Graphics.TEXT_JUSTIFY_CENTER
        );

        // --- CADENCE AND GRADIENT ---
        var middleRowY = layout[:middleRowY];
        var labelY = middleRowY - xtinyH - 1 + middleRowLabelOffset;
        dc.setColor(mLabelsColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            width * 0.15,
            labelY,
            Graphics.FONT_XTINY,
            "CAD",
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            width * 0.5,
            labelY,
            Graphics.FONT_XTINY,
            "GEAR",
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            width * 0.85,
            labelY,
            Graphics.FONT_XTINY,
            "GRD",
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.setColor(mValuesColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            width * 0.15,
            middleRowY,
            rowValueFont,
            mCadence.format("%.0f"),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            width * 0.5,
            middleRowY,
            rowValueFont,
            mGearInfo,
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            width * 0.85,
            middleRowY,
            rowValueFont,
            mGrade.format("%.1f"),
            Graphics.TEXT_JUSTIFY_CENTER
        );
    }

    // Band 4: the HR panel on the left and the power (or, with no power data,
    // cadence) panel on the right, each a zone-coloured segmented arc.
    private function drawPanels(
        dc as Graphics.Dc,
        layout as Lang.Dictionary
    ) as Void {
        var centerX = layout[:centerX];
        var sideCenterY = layout[:panelCenterY];
        var sideRadius = layout[:panelRadius];
        var barW = layout[:panelBarW];
        var lPanelCenterX = layout[:panelLeftX];
        var rPanelCenterX = layout[:panelRightX];
        var panelLabelOffset = layout[:panelLabelOffset];
        var xtinyH = layout[:xtinyH];

        var panelValueFont = mDeviceProfile[:panelValueFont];
        var unitLabelFont = mDeviceProfile[:unitLabelFont];
        var panelTextYOffset = mDeviceProfile[:panelTextYOffset];
        var panelTopLabelYOffset = mDeviceProfile[:panelTopLabelYOffset];
        var panelAvgValueOffset = mDeviceProfile[:panelAvgValueOffset];
        var avgLabelOffset = mDeviceProfile[:avgLabelOffset];

        var arcSweepDeg = mDeviceProfile[:panelArcSweep];
        var segCount = 10;
        var gapDeg = 1.0; // The physical gap between segments

        // Calculate how many degrees each individual block gets
        var totalGapSweep = gapDeg * (segCount - 1);
        var segSweepDeg = (arcSweepDeg - totalGapSweep) / segCount;

        // ---- LEFT PANEL: Heart Rate ----
        // Start at bottom-left (e.g., 210 deg)
        var hrStartAngle = 180.0 + arcSweepDeg / 2.0;

        dc.setColor(mLabelsColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            lPanelCenterX,
            sideCenterY - panelLabelOffset + panelTopLabelYOffset,
            unitLabelFont,
            "HR",
            Graphics.TEXT_JUSTIFY_CENTER
        );

        var hrMin = 0.0;
        var hrMax = 200.0;
        var hrZones = mHrZoneBoundaries as Array<Numeric>?;
        if (hrZones != null && hrZones.size() >= 6) {
            hrMin = hrZones[0].toFloat();
            hrMax = hrZones[5].toFloat();
        }
        var hrRange = hrMax - hrMin;
        var hrRatio = 0.0;
        if (mHeartRate != null && hrRange > 0) {
            hrRatio = (mHeartRate.toFloat() - hrMin) / hrRange;
        }
        if (hrRatio > 1.0) {
            hrRatio = 1.0;
        }
        if (hrRatio < 0.0) {
            hrRatio = 0.0;
        }
        var litSegs = (hrRatio * segCount + 0.5).toNumber();
        if (mHeartRate != null && litSegs < 1) {
            litSegs = 1; // Ensure at least one segment is lit if HR is non-null
        }
        var hrZoneColor = zoneColor(
            mHeartRate != null ? mHeartRate : 0,
            mHrZoneBoundaries,
            COLOR_HR
        );

        dc.setPenWidth(barW);

        for (var i = 0; i < segCount; i++) {
            // Clockwise goes down in angle
            var segStart = hrStartAngle - i * (segSweepDeg + gapDeg);
            var segEnd = segStart - segSweepDeg;

            // Set lit color or dark background color
            dc.setColor(
                i < litSegs ? hrZoneColor : mTrackColor,
                Graphics.COLOR_TRANSPARENT
            );

            // Draw the segment block
            dc.drawArc(
                centerX,
                sideCenterY,
                sideRadius,
                Graphics.ARC_CLOCKWISE,
                segStart,
                segEnd
            );
        }

        dc.setColor(mValuesColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            lPanelCenterX,
            sideCenterY + panelTextYOffset,
            panelValueFont,
            mHeartRate != null ? mHeartRate.toString() : "--",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
        dc.setColor(mLabelsColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            lPanelCenterX,
            sideCenterY +
                panelLabelOffset -
                xtinyH -
                1 +
                avgLabelOffset +
                panelTextYOffset,
            Graphics.FONT_XTINY,
            "AVG",
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.setColor(mValuesColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            lPanelCenterX,
            sideCenterY +
                panelLabelOffset +
                panelAvgValueOffset +
                avgLabelOffset +
                panelTextYOffset,
            Graphics.FONT_MEDIUM,
            mAvgHeartRate.format("%.0f"),
            Graphics.TEXT_JUSTIFY_CENTER
        );

        // ---- RIGHT PANEL: 3s Power ----
        // Start at bottom-right (e.g., 330 deg)
        var pwrStartAngle = 360.0 - arcSweepDeg / 2.0;

        dc.setColor(mLabelsColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            rPanelCenterX,
            sideCenterY - panelLabelOffset + panelTopLabelYOffset,
            unitLabelFont,
            mHasPowerData ? "PWR" : "CAD",
            Graphics.TEXT_JUSTIFY_CENTER
        );

        var rightRatio = 0.0;
        if (mHasPowerData) {
            var powerScaleMax = ftp;
            if (mMaxPower > powerScaleMax) {
                powerScaleMax = mMaxPower.toFloat();
            }
            rightRatio = mPower3s.toFloat() / powerScaleMax;
        } else {
            var cadenceScaleMax = 150.0;
            rightRatio = mCadence.toFloat() / cadenceScaleMax;
        }
        if (rightRatio > 1.0) {
            rightRatio = 1.0;
        }
        if (rightRatio < 0.0) {
            rightRatio = 0.0;
        }
        var litPwrSegs = (rightRatio * segCount + 0.5).toNumber();
        var pwrZoneColor = zoneColor(
            mPower3s,
            mPowerZoneBoundaries,
            COLOR_POWER
        );

        dc.setPenWidth(barW);

        for (var i = 0; i < segCount; i++) {
            // Right side goes Counter-Clockwise (increases in angle)
            var pwrSegStart = pwrStartAngle + i * (segSweepDeg + gapDeg);
            var pwrSegEnd = pwrSegStart + segSweepDeg;

            dc.setColor(
                i < litPwrSegs
                    ? mHasPowerData
                        ? pwrZoneColor
                        : COLOR_CADENCE
                    : mTrackColor,
                Graphics.COLOR_TRANSPARENT
            );

            dc.drawArc(
                centerX,
                sideCenterY,
                sideRadius,
                Graphics.ARC_COUNTER_CLOCKWISE,
                pwrSegStart,
                pwrSegEnd
            );
        }

        dc.setColor(mValuesColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            rPanelCenterX,
            sideCenterY + panelTextYOffset,
            panelValueFont,
            mHasPowerData ? mPower3s.toString() : mCadence.format("%.0f"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
        dc.setColor(mLabelsColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            rPanelCenterX,
            sideCenterY +
                panelLabelOffset -
                xtinyH -
                1 +
                avgLabelOffset +
                panelTextYOffset,
            Graphics.FONT_XTINY,
            "AVG",
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.setColor(mValuesColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            rPanelCenterX,
            sideCenterY +
                panelLabelOffset +
                panelAvgValueOffset +
                avgLabelOffset +
                panelTextYOffset,
            Graphics.FONT_MEDIUM,
            mHasPowerData
                ? mAvgPower.format("%.0f")
                : mAvgCadence.format("%.0f"),
            Graphics.TEXT_JUSTIFY_CENTER
        );
    }

    // Band 5: ascent, distance and calories across three columns.
    private function drawFooter(
        dc as Graphics.Dc,
        layout as Lang.Dictionary
    ) as Void {
        var footerY = layout[:footerY];
        var colW = layout[:colW];
        var rowValueH = layout[:rowValueH];
        var rowValueFont = mDeviceProfile[:rowValueFont];
        var footerValueYOffset = mDeviceProfile[:footerValueYOffset];
        var bottomLabelOffset = mDeviceProfile[:bottomLabelOffset];

        var bottomValues = [
            mAscent.format("%.0f"),
            (mDistance / 1000).format("%.1f"),
            mCalories.format("%.0f"),
        ];
        var bottomLabels = ["ASC", "DIST", "CAL"];

        for (var i = 0; i < 3; i++) {
            var x = colW * (i + 0.5);
            dc.setColor(mValuesColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                x,
                footerY + 2 + footerValueYOffset,
                rowValueFont,
                bottomValues[i],
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.setColor(mLabelsColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                x,
                footerY + 2 + rowValueH - 6 + bottomLabelOffset,
                Graphics.FONT_XTINY,
                bottomLabels[i],
                Graphics.TEXT_JUSTIFY_CENTER
            );
        }
    }

    // --- COMPACT BANDS ------------------------------------------------------
    //
    // The 246x322 render path. Roughly 150 px of the full layout's content does
    // not fit, so the review-time metrics (AVG/MAX speed, AVG HR, AVG power,
    // elevation, ascent, calories, gear) are dropped rather than shrunk — at
    // 156 ppi on a 2.6" panel a smaller font stops being glanceable on rough
    // road, which is the whole point of the field.

    // Compact band 1: temperature, clock, elevation and gear across four evenly
    // spaced columns, each under an xtiny label — the same column order and
    // label-over-value stack the full layout's top bar uses, with DI2 appended.
    // Four columns is a quarter of the screen each, 61 px on both devices. The
    // widest things that can land in one are a five-digit elevation in feet and
    // a negative one-decimal temperature.
    //
    // The columns are centre-justified, so what actually constrains the row is
    // neighbour-to-neighbour, not string-vs-column: a string wider than 61 px is
    // fine as long as the column beside it is running something narrow.
    //   830 at FONT_MEDIUM: 55 and 54 px. Everything clears with margin.
    //   840 at FONT_LARGE:  70 and 69 px, and even the clock is 64. Typical
    //     values still clear — "12.3°" (58) ends at 60 and "23:59" starts at 60
    //     — but a sub-zero temperature overlaps the clock by ~5 px, and a
    //     five-digit elevation in feet overlaps it by ~5 px on the other side.
    //     Metric elevation is four digits (56 px) and never collides.
    private function drawCompactTopBar(
        dc as Graphics.Dc,
        layout as Lang.Dictionary
    ) as Void {
        var colW = layout[:colW];
        var topBarY = layout[:topBarY];
        var topBarValueY = layout[:topBarValueY];
        var rowValueFont = mDeviceProfile[:rowValueFont];

        var now = System.getClockTime();

        var topLabels = ["TEMP", "CLOCK", "ELEV", "DI2"];
        var topValues = [
            mTemp.format("%.1f") + "°",
            Lang.format("$1$:$2$", [
                now.hour.format("%02d"),
                now.min.format("%02d"),
            ]),
            mElevation.format("%.0f"),
            mGearInfo,
        ];

        for (var i = 0; i < 4; i++) {
            var x = colW * (i + 0.5);
            dc.setColor(mLabelsColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                x,
                topBarY,
                Graphics.FONT_XTINY,
                topLabels[i],
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.setColor(mValuesColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                x,
                topBarValueY,
                rowValueFont,
                topValues[i],
                Graphics.TEXT_JUSTIFY_CENTER
            );
        }
    }

    // Compact band 2: the speed arc, the AVG/MAX pair inside its crown and the
    // central readout, in the same stack the full layout uses.
    // 12 segments rather than the full layout's 24: the 830 is 2019 hardware
    // and drawArc is the most expensive call in the pass.
    private function drawCompactSpeedGauge(
        dc as Graphics.Dc,
        layout as Lang.Dictionary
    ) as Void {
        var centerX = layout[:centerX];
        var centerY = layout[:centerY];
        var radius = layout[:radius];

        var maxVal = mIsMetric ? 60.0 : 40.0;
        var gaugeStart = 210.0;
        var gaugeSweep = 240.0;

        var arcSegCount = 12;
        var segArcLen = gaugeSweep / arcSegCount;
        var segGapDeg = 3.5;
        var ratio = mSpeed / maxVal;
        if (ratio > 1.0) {
            ratio = 1.0;
        }
        var litArcSegs = (ratio * arcSegCount + 0.5).toNumber();

        dc.setPenWidth(layout[:trackWidth]);
        for (var i = 0; i < arcSegCount; i++) {
            var segStartDeg = gaugeStart - i * segArcLen;
            var segEndDeg = segStartDeg - segArcLen + segGapDeg;
            dc.setColor(
                i < litArcSegs ? COLOR_SPEED : mTrackColor,
                Graphics.COLOR_TRANSPARENT
            );
            dc.drawArc(
                centerX,
                centerY,
                radius,
                Graphics.ARC_CLOCKWISE,
                segStartDeg,
                segEndDeg
            );
        }

        // --- AVG / MAX PAIR ---
        // Columns come from the layout, which starts at the same 0.35 of the
        // radius :full uses and pulls them in if the crown font is too big to
        // clear the arc there — see :speedAvgColOffset in computeCompactLayout.
        var avgColOffset = layout[:speedAvgColOffset];
        var avgX = centerX - avgColOffset;
        var maxX = centerX + avgColOffset;
        var avgLabelY = layout[:speedAvgLabelY];
        var avgValueY = layout[:speedAvgValueY];

        dc.setColor(mLabelsColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            avgX,
            avgLabelY,
            Graphics.FONT_XTINY,
            "AVG",
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            maxX,
            avgLabelY,
            Graphics.FONT_XTINY,
            "MAX",
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.setColor(mValuesColor, Graphics.COLOR_TRANSPARENT);
        var crownFont = mDeviceProfile[:crownValueFont];
        dc.drawText(
            avgX,
            avgValueY,
            crownFont,
            mAvgSpeed.format("%.1f"),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            maxX,
            avgValueY,
            crownFont,
            mMaxSpeed.format("%.1f"),
            Graphics.TEXT_JUSTIFY_CENTER
        );

        dc.setColor(mValuesColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            centerY + mDeviceProfile[:speedYOffset],
            mDeviceProfile[:speedFont],
            mSpeed.format("%.1f"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
        dc.setColor(mLabelsColor, Graphics.COLOR_TRANSPARENT);
        // The -10 tucks the unit label up under the speed number: 0.38 of the
        // radius clears the THAI_HOT text box, but the box carries more leading
        // under the digits than they need, so the label read as detached.
        dc.drawText(
            centerX,
            centerY + radius * 0.38 - 10 + mDeviceProfile[:speedYOffset],
            mDeviceProfile[:unitLabelFont],
            mIsMetric ? "KMH" : "MPH",
            Graphics.TEXT_JUSTIFY_CENTER
        );
    }

    // Compact band 3: HR and power as horizontal zone bars. Horizontal because
    // a bar costs a fraction of the vertical space an arc does at the same
    // length, and reads at a glance from the corner of the eye. Same
    // no-power-data fallback as the full layout's right panel: the bar becomes
    // a 0-150 rpm cadence bar, label and all.
    private function drawCompactBars(
        dc as Graphics.Dc,
        layout as Lang.Dictionary
    ) as Void {
        var valueY = layout[:barsValueY];
        var barY = layout[:barsBarY];
        var barH = layout[:barsBarH];
        var segLen = layout[:barsSegLen];
        var segGap = layout[:barsSegGap];
        var lX0 = layout[:barsLeftX0];
        var lX1 = layout[:barsLeftX1];
        var rX0 = layout[:barsRightX0];
        var rX1 = layout[:barsRightX1];
        var xtinyH = layout[:xtinyH];
        var barValueFont = mDeviceProfile[:barValueFont];

        // Sit the label on the same baseline as the much taller value.
        var labelY = valueY + layout[:barValueH] - xtinyH - 2;

        // ---- LEFT: heart rate, filling centre-outward ----
        var hrMin = 0.0;
        var hrMax = 200.0;
        var hrZones = mHrZoneBoundaries as Array<Numeric>?;
        if (hrZones != null && hrZones.size() >= 6) {
            hrMin = hrZones[0].toFloat();
            hrMax = hrZones[5].toFloat();
        }
        var hrRange = hrMax - hrMin;
        var hrRatio = 0.0;
        if (mHeartRate != null && hrRange > 0) {
            hrRatio = (mHeartRate.toFloat() - hrMin) / hrRange;
        }
        if (hrRatio > 1.0) {
            hrRatio = 1.0;
        }
        if (hrRatio < 0.0) {
            hrRatio = 0.0;
        }
        var litHrSegs = (hrRatio * 10 + 0.5).toNumber();
        if (mHeartRate != null && litHrSegs < 1) {
            litHrSegs = 1;
        }
        var hrZoneColor = zoneColor(
            mHeartRate != null ? mHeartRate : 0,
            mHrZoneBoundaries,
            COLOR_HR
        );

        dc.setColor(mLabelsColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            lX0,
            labelY,
            Graphics.FONT_XTINY,
            "HR",
            Graphics.TEXT_JUSTIFY_LEFT
        );
        dc.setColor(mValuesColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            lX1,
            valueY,
            barValueFont,
            mHeartRate != null ? mHeartRate.toString() : "--",
            Graphics.TEXT_JUSTIFY_RIGHT
        );

        // Segment 0 is the one nearest the centre, so the bar grows out towards
        // the left screen edge. Slot 9 lands exactly on lX0.
        for (var i = 0; i < 10; i++) {
            dc.setColor(
                i < litHrSegs ? hrZoneColor : mTrackColor,
                Graphics.COLOR_TRANSPARENT
            );
            dc.fillRectangle(
                lX1 - segLen - i * (segLen + segGap),
                barY,
                segLen,
                barH
            );
        }

        // ---- RIGHT: power, or cadence when the bike has no power meter ----
        var rightRatio = 0.0;
        if (mHasPowerData) {
            var powerScaleMax = ftp;
            if (mMaxPower > powerScaleMax) {
                powerScaleMax = mMaxPower.toFloat();
            }
            rightRatio = mPower3s.toFloat() / powerScaleMax;
        } else {
            rightRatio = mCadence.toFloat() / 150.0;
        }
        if (rightRatio > 1.0) {
            rightRatio = 1.0;
        }
        if (rightRatio < 0.0) {
            rightRatio = 0.0;
        }
        var litPwrSegs = (rightRatio * 10 + 0.5).toNumber();
        var pwrZoneColor = zoneColor(
            mPower3s,
            mPowerZoneBoundaries,
            COLOR_POWER
        );

        dc.setColor(mLabelsColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            rX1,
            labelY,
            Graphics.FONT_XTINY,
            mHasPowerData ? "PWR" : "CAD",
            Graphics.TEXT_JUSTIFY_RIGHT
        );
        dc.setColor(mValuesColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            rX0,
            valueY,
            barValueFont,
            mHasPowerData ? mPower3s.toString() : mCadence.format("%.0f"),
            Graphics.TEXT_JUSTIFY_LEFT
        );

        // Mirror of the HR bar: segment 0 sits nearest the centre and the fill
        // runs out towards the right screen edge. Slot 9 lands exactly on rX1.
        for (var i = 0; i < 10; i++) {
            dc.setColor(
                i < litPwrSegs
                    ? mHasPowerData
                        ? pwrZoneColor
                        : COLOR_CADENCE
                    : mTrackColor,
                Graphics.COLOR_TRANSPARENT
            );
            dc.fillRectangle(
                rX0 + i * (segLen + segGap),
                barY,
                segLen,
                barH
            );
        }
    }

    // Compact band 4: elapsed time, cadence, grade and distance. Columns are
    // spaced by content rather than evenly — elapsed time is three times the
    // width of the others. When there is no power data the cadence bar above
    // already carries cadence, so that slot shows ascent instead.
    // This is the tighter of the two text bands, because TIME is wide and the
    // three columns beside it are fixed fractions of the width.
    //   830 at FONT_MEDIUM: the tightest pair is GRD/DIST, "-12.3" and "199.9"
    //     at 46 and 49 px against centres 52 px apart — ~4 px clear. That is
    //     what caps the font on this device, not the band height.
    //   840 at FONT_LARGE: typical values clear (a 1-hour time, 2-digit cadence,
    //     1-digit grade and 2-digit distance leave 9 px at the tightest point),
    //     but the absolute worst case needs 262 px of a 246 px row, so it cannot
    //     be respaced into fitting. Two things overrun: a 10-hour-plus TIME is
    //     100 px and clips ~6 px off the left edge, and a 3-digit distance
    //     beside a 2-digit negative grade overlaps it by ~9 px.
    private function drawCompactFooter(
        dc as Graphics.Dc,
        layout as Lang.Dictionary
    ) as Void {
        var width = layout[:width];
        var footerY = layout[:footerY];
        var labelY = layout[:footerLabelY];
        var rowValueFont = mDeviceProfile[:rowValueFont];

        var totalSecs = mElapsedMs / 1000;
        var values = [
            Lang.format("$1$:$2$:$3$", [
                (totalSecs / 3600).format("%d"),
                ((totalSecs % 3600) / 60).format("%02d"),
                (totalSecs % 60).format("%02d"),
            ]),
            mHasPowerData ? mCadence.format("%.0f") : mAscent.format("%.0f"),
            mGrade.format("%.1f"),
            (mDistance / 1000).format("%.1f"),
        ];
        var labels = [
            "TIME",
            mHasPowerData ? "CAD" : "ASC",
            "GRD",
            "DIST",
        ];
        var columns = [0.18, 0.45, 0.66, 0.87];

        for (var i = 0; i < 4; i++) {
            var x = width * columns[i];
            dc.setColor(mValuesColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                x,
                footerY,
                rowValueFont,
                values[i],
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.setColor(mLabelsColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                x,
                labelY,
                Graphics.FONT_XTINY,
                labels[i],
                Graphics.TEXT_JUSTIFY_CENTER
            );
        }
    }

    // Returns a Dictionary of device-specific layout and font values keyed by screen size.
    // To add support for a new device, add a new profile block below.
    //
    // Which keys a profile must carry depends on its :layoutVariant. A :full
    // profile carries all of them; a :compact profile carries only the eight
    // marked [compact] below, because computeCompactLayout derives its bands
    // from measured font heights rather than from pixel offsets.
    //
    // Profile keys:
    //   :layoutVariant         (Symbol) — which band stack computeLayout builds.
    //                            :full is the 1.67-aspect layout the 1030 /
    //                            1040 / 1050 / 850 / Explore 2 use; :compact is
    //                            the four-band stack for the 246x322 830 / 840.
    //   :speedGaugeCenterYOffset
    //                          (Number) — vertical offset for the speed gauge (positive =
    //                            lower). Reaches three places at different strengths, so a
    //                            change here is not a simple translation: the arc centre
    //                            moves +1x, the cadence/gear/grade row moves -1x (it is
    //                            measured up from the gauge, so the gauge going down pulls
    //                            the row up), and the central speed digits move +2x because
    //                            drawSpeedGauge adds the offset again on top of the centre
    //                            it is already baked into. Use :speedYOffset to move the
    //                            digits alone. The HR/power gauge below is not read from
    //                            this key but still shifts +0.5x — see
    //                            :hrPwrGaugeCenterYOffset.
    //   :speedFont             (Graphics.FontType) — font for the central speed readout [compact]
    //   :panelValueFont        (Graphics.FontType) — font for HR and power panel values
    //   :rowValueFont          (Graphics.FontType) — font for the top bar, elapsed time,
    //                            cadence/gear/grade and footer values. FONT_LARGE on 1.67
    //                            aspect screens; shorter screens step it down. [compact]
    //   :barValueFont          (Graphics.FontType) — font for the HR and power values on the
    //                            compact zone bars. [compact only]
    //   :crownValueFont        (Graphics.FontType) — font for the AVG / MAX speed pair inside
    //                            the gauge crown. Sized independently of :rowValueFont because
    //                            the crown narrows as the pair grows: the columns are pulled
    //                            in to compensate (:speedAvgColOffset), and past a point the
    //                            two values would meet in the middle. [compact only]
    //   :crownYOffset          (Number) — vertical nudge for the AVG / MAX pair, label and
    //                            value together (positive = lower). The only pixel offset on
    //                            the :compact path; safe only because the 830 and 840 take
    //                            separate profiles. [compact only]
    //   :gaugeRadiusFactor     (Float) — speed gauge radius as a fraction of the narrow
    //                            screen dimension. 0.33 on 1.67 aspect screens; shorter
    //                            screens need less so the rows below still fit. On :compact
    //                            it is an upper bound — the layout shrinks below it if the
    //                            band or the screen width cannot take it. [compact]
    //   :speedYOffset          (Number) — vertical shift for the central speed value and km/h label [compact]
    //   :elapsedTimeYOffset    (Number) — vertical shift for the elapsed time row
    //   :bottomLabelOffset     (Number) — extra downward shift for bottom bar labels
    //   :timeLabelOffset       (Number) — extra downward shift for the TIME label
    //   :cadenceLineYOffset    (Number) — vertical shift for the cadence/gradient row (negative = higher)
    //   :middleRowLabelOffset  (Number) — extra downward shift for CAD, DI2, GRD labels relative to the row
    //   :topBarYOffset         (Number) — vertical shift for the entire top bar (negative = higher)
    //   :topBarValueYOffset    (Number) — extra vertical shift for top bar values relative to labels (negative = closer)
    //   :footerValueYOffset    (Number) — extra downward shift for footer bar values
    //   :hrPwrGaugeCenterYOffset
    //                          (Number) — vertical offset for the HR and power gauges
    //                            (positive = lower), applied +1x to their shared centre and
    //                            to nothing else. This is the only key that moves those two
    //                            gauges alone. It is not the only thing that moves them: the
    //                            band is the leftover space between the gauge bottom and the
    //                            fixed footer, and its centre is that space's midpoint, so
    //                            anything changing the speed gauge's size or position
    //                            (:gaugeRadiusFactor, :speedGaugeCenterYOffset) drags the
    //                            HR/power gauges along at half strength. That is the band
    //                            re-centring itself, and it is deliberate — this key is for
    //                            nudging off that midpoint, not for holding position
    //                            against it.
    //   :panelTextYOffset      (Number) — vertical shift for panel values and avg text (negative = up), arc unaffected
    //   :panelTopLabelYOffset  (Number) — vertical shift for the HR / PWR top labels (negative = up)
    //   :hideClockLabel        (Boolean) — suppress the CLOCK label in the top bar
    //   :unitLabelFont         (Graphics.FontType) — font for km/h, HR, and CAD/PWR labels [compact]
    //   :avgLabelOffset        (Number) — vertical shift for AVG/MAX and panel AVG labels and values (negative = up)
    //   :speedAvgValueOffset   (Number) — extra vertical shift for the AVG/MAX speed values
    //                            only, relative to their AVG/MAX labels. Use to open up the
    //                            label-to-value gap when a smaller gauge radius closes it.
    //   :panelAvgValueOffset   (Number) — vertical shift for avg HR and avg power/cadence values (negative = up)
    //   :panelArcSweep         (Float)  — total sweep angle in degrees for HR and power arc gauges
    private function initDeviceProfile(
        screenWidth as Number,
        screenHeight as Number,
        deviceType as String
    ) as Lang.Dictionary {
        // --- Edge 850 / 550: 420 x 600 ---
        // Same 269 ppi font metrics as the 1050 but 200 fewer vertical pixels, so
        // the 1050 profile overflows by roughly 160 px. Must be tested before the
        // screenWidth >= 400 branch below, which would otherwise swallow it.
        // Recovered by stepping the row, speed and panel fonts down one each and
        // shrinking the gauge from 0.33 to 0.275 of screen width. That started at
        // 0.25 and was opened up 10%; the gauge band is the one place this layout
        // has slack, and everything below it keys off the radius, so the cost is
        // paid by the panel band — see :gaugeRadiusFactor below.
        // The 550 is the button-only 850 — identical panel, ppi and font point
        // sizes — so it shares this profile outright. It MUST be matched here by
        // deviceType: unlike the 530 / 540, no width test catches it, and a 550
        // falling through to screenWidth >= 400 would silently take the 1050
        // profile and render the overflow above.
        if (deviceType.equals("edge850") || deviceType.equals("edge550")) {
            return {
                :layoutVariant => :full,
                :speedGaugeCenterYOffset => 0,
                :speedYOffset => 6,
                :elapsedTimeYOffset => 12,
                :speedFont => Graphics.FONT_NUMBER_MEDIUM,
                :panelValueFont => Graphics.FONT_NUMBER_MILD,
                :rowValueFont => Graphics.FONT_MEDIUM,
                :gaugeRadiusFactor => 0.275,
                :bottomLabelOffset => 0,
                :timeLabelOffset => 0,
                :cadenceLineYOffset => 22,
                :middleRowLabelOffset => 0,
                :hideClockLabel => false,
                :unitLabelFont => Graphics.FONT_TINY,
                :avgLabelOffset => 0,
                :speedAvgValueOffset => 4,
                :panelAvgValueOffset => 0,
                :panelArcSweep => 45.0,
                :topBarYOffset => 0,
                :topBarValueYOffset => -4,
                :footerValueYOffset => 0,
                :hrPwrGaugeCenterYOffset => 10,
                :panelTextYOffset => 0,
                :panelTopLabelYOffset => 0,
            };
        }

        // --- Edge 1050: 480 x 800 ---
        if (screenWidth >= 400) {
            return {
                :layoutVariant => :full,
                :speedGaugeCenterYOffset => -5,
                :speedYOffset => 0,
                :elapsedTimeYOffset => 0,
                :speedFont => Graphics.FONT_NUMBER_THAI_HOT,
                :panelValueFont => Graphics.FONT_NUMBER_HOT,
                :rowValueFont => Graphics.FONT_LARGE,
                :gaugeRadiusFactor => 0.33,
                :bottomLabelOffset => 0,
                :timeLabelOffset => 0,
                :cadenceLineYOffset => 0,
                :middleRowLabelOffset => 0,
                :hideClockLabel => false,
                :unitLabelFont => Graphics.FONT_SMALL,
                :avgLabelOffset => 0,
                :speedAvgValueOffset => 0,
                :panelAvgValueOffset => 0,
                :panelArcSweep => 54.0,
                :topBarYOffset => 0,
                :topBarValueYOffset => 0,
                :footerValueYOffset => 0,
                :hrPwrGaugeCenterYOffset => 10,
                :panelTextYOffset => -12,
                :panelTopLabelYOffset => -12,
            };
        }

        // --- Edge Explore 2: 240 x 400 ---
        if (deviceType.equals("edgeexplore2")) {
            return {
                :layoutVariant => :full,
                :speedGaugeCenterYOffset => 5,
                :speedYOffset => -4,
                :elapsedTimeYOffset => -10,
                :speedFont => Graphics.FONT_NUMBER_HOT,
                :panelValueFont => Graphics.FONT_NUMBER_MEDIUM,
                :rowValueFont => Graphics.FONT_LARGE,
                :gaugeRadiusFactor => 0.33,
                :bottomLabelOffset => 0,
                :timeLabelOffset => 8,
                :cadenceLineYOffset => -2,
                :middleRowLabelOffset => 8,
                :hideClockLabel => false,
                :unitLabelFont => Graphics.FONT_SMALL,
                :avgLabelOffset => 0,
                :speedAvgValueOffset => 0,
                :panelAvgValueOffset => -3,
                :panelArcSweep => 54.0,
                :topBarYOffset => -6,
                :topBarValueYOffset => -6,
                :footerValueYOffset => 0,
                :hrPwrGaugeCenterYOffset => 8,
                :panelTextYOffset => -10,
                :panelTopLabelYOffset => -10,
            };
        }

        // --- Edge 840 / 540: 246 x 322 ---
        // Same panel as the 830/530 below and the same :compact layout, split
        // out for one key: :rowValueFont. This pair renders the system fonts far
        // smaller than the 830 does — FONT_MEDIUM is 19 px here against 26 —
        // so the step that fills the top bar and footer on the 830 leaves these
        // two looking undersized, and they have the room for one more step.
        //
        // FONT_LARGE is the last font available (the FONT_NUMBER_* faces carry
        // no '°', ':' or '/', and this device reports no vector font support),
        // and it is a big step: 19 px to 31. It fits typical values with a few
        // px to spare but overruns its neighbours at the extremes — see
        // drawCompactTopBar and drawCompactFooter for which strings and by how
        // much. That trade is deliberate; step back to FONT_MEDIUM to undo it.
        if (deviceType.equals("edge840") || deviceType.equals("edge540")) {
            return {
                :layoutVariant => :compact,
                :speedFont => Graphics.FONT_NUMBER_THAI_HOT,
                :barValueFont => Graphics.FONT_NUMBER_MILD,
                :rowValueFont => Graphics.FONT_LARGE,
                :crownValueFont => Graphics.FONT_LARGE,
                // The taller crown font stacks the pair higher than it wants to
                // sit; 6 px back down re-centres it in the crown by eye. That is
                // as far as it goes: the AVG / MAX digits end 1 px above the top
                // of the speed digits here (measured via getFontAscent, and the
                // number fonts carry no leading — box height is ascent+descent
                // exactly, so the boxes are the glyphs). 7 would touch.
                :crownYOffset => 6,
                :unitLabelFont => Graphics.FONT_TINY,
                :gaugeRadiusFactor => 0.40,
                :speedYOffset => 0,
            };
        }

        // --- Edge 830 / 530: 246 x 322 ---
        // The other :compact profile. Both carry the short key set —
        // computeCompactLayout derives its bands from measured font heights, so
        // the ~20 pixel offsets the :full path needs have nothing to apply to,
        // and the same profile covers a device pair whose font metrics differ
        // (830 FONT_LARGE 41, 840 31) because the layout measures whatever it
        // gets. 530 and 540 are the button-only 830 and 840 — identical panel,
        // ppi and font point sizes. The width test stays as a safety net for any
        // other sub-260 device that is not a build target; it lands here rather
        // than on the 840 profile because this is the more conservative of the
        // two font choices.
        if (
            deviceType.equals("edge830") ||
            deviceType.equals("edge530") ||
            screenWidth < 260
        ) {
            return {
                :layoutVariant => :compact,
                :speedFont => Graphics.FONT_NUMBER_THAI_HOT,
                :barValueFont => Graphics.FONT_NUMBER_MILD,
                // FONT_MEDIUM rather than FONT_SMALL: the top bar and footer
                // values are the least glanceable thing on this screen, and
                // both bands have the width for the step (see drawCompactTopBar
                // for the worst-case column). The extra height comes out of the
                // gauge band, which shrinks to fit on its own. FONT_LARGE is 41
                // px here and does not fit — that step is 840/540 only.
                :rowValueFont => Graphics.FONT_MEDIUM,
                :crownValueFont => Graphics.FONT_MEDIUM,
                :crownYOffset => 0,
                :unitLabelFont => Graphics.FONT_TINY,
                :gaugeRadiusFactor => 0.40,
                :speedYOffset => 0,
            };
        }

        // --- Edge 1030 / 1030 Plus: labels sit higher than on 1040 ---
        if (deviceType.equals("edge1030")) {
            return {
                :layoutVariant => :full,
                :speedGaugeCenterYOffset => 5,
                :speedYOffset => 0,
                :elapsedTimeYOffset => -13,
                :speedFont => Graphics.FONT_NUMBER_HOT,
                :panelValueFont => Graphics.FONT_NUMBER_MEDIUM,
                :rowValueFont => Graphics.FONT_LARGE,
                :gaugeRadiusFactor => 0.33,
                :bottomLabelOffset => 2,
                :timeLabelOffset => 8,
                :cadenceLineYOffset => 0,
                :middleRowLabelOffset => 8,
                :hideClockLabel => false,
                :unitLabelFont => Graphics.FONT_XTINY,
                :avgLabelOffset => -6,
                :speedAvgValueOffset => 0,
                :panelAvgValueOffset => -6,
                :panelArcSweep => 45.0,
                :topBarYOffset => -6,
                :topBarValueYOffset => -6,
                :footerValueYOffset => 4,
                :hrPwrGaugeCenterYOffset => 10,
                :panelTextYOffset => -10,
                :panelTopLabelYOffset => -10,
            };
        }

        // --- Edge 1040: 282 x 470 (default / fallback) ---
        return {
            :layoutVariant => :full,
            :speedGaugeCenterYOffset => 5,
            :speedYOffset => -14,
            :elapsedTimeYOffset => -10,
            :speedFont => Graphics.FONT_NUMBER_HOT,
            :panelValueFont => Graphics.FONT_NUMBER_MEDIUM,
            :rowValueFont => Graphics.FONT_LARGE,
            :gaugeRadiusFactor => 0.33,
            :bottomLabelOffset => 0,
            :timeLabelOffset => 0,
            :cadenceLineYOffset => 0,
            :middleRowLabelOffset => 0,
            :hideClockLabel => false,
            :unitLabelFont => Graphics.FONT_SMALL,
            :avgLabelOffset => 0,
            :speedAvgValueOffset => 0,
            :panelAvgValueOffset => 0,
            :panelArcSweep => 54.0,
            :topBarYOffset => 0,
            :topBarValueYOffset => 0,
            :footerValueYOffset => 0,
            :hrPwrGaugeCenterYOffset => 4,
            :panelTextYOffset => -12,
            :panelTopLabelYOffset => -4,
        };
    }

    private function calculateGrade(
        rawAlt as Float?,
        rawDist as Float?
    ) as Void {
        if (rawAlt == null || rawDist == null) {
            ageGradeWindow();
            return;
        }

        if (mGradeLastAlt == null || mGradeLastDist == null) {
            seedGradeWindow(rawAlt, rawDist);
            return;
        }

        var distDiff = rawDist - mGradeLastDist;

        // Distance ran backwards, so the anchor sits ahead of us and would block
        // every future update. Re-seed rather than wait for the ride to catch up.
        if (distDiff < 0) {
            seedGradeWindow(rawAlt, rawDist);
            return;
        }

        // 20m window: wide enough to suppress barometric noise, tight enough to stay responsive
        if (distDiff > 20.0) {
            var altDiff = rawAlt - mGradeLastAlt;
            var newGrade = (altDiff / distDiff) * 100.0;

            if (newGrade > 30.0) {
                newGrade = 30.0;
            }
            if (newGrade < -30.0) {
                newGrade = -30.0;
            }

            // EMA blend: absorbs altitude spikes without hiding sustained grade changes
            mGrade = mGrade * 0.5 + newGrade * 0.5;

            seedGradeWindow(rawAlt, rawDist);
        } else {
            ageGradeWindow();
        }
    }

    private function seedGradeWindow(rawAlt as Float, rawDist as Float) as Void {
        mGradeLastAlt = rawAlt;
        mGradeLastDist = rawDist;
        mGradeStallCount = 0;
    }

    // Drops the window after a long run of computes that produced no update, so
    // the next valid sample re-seeds it. Recovers a stranded anchor even when
    // distance never runs backwards; re-seeding while genuinely stopped just
    // rewrites the same values, so the normal case is unaffected.
    private function ageGradeWindow() as Void {
        mGradeStallCount++;
        if (mGradeStallCount > GRADE_STALL_LIMIT) {
            mGradeLastAlt = null;
            mGradeLastDist = null;
            mGradeStallCount = 0;
        }
    }
}
