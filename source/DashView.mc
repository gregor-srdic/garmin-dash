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
    private var mLayoutCache = null;
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

        drawTopBar(dc, layout);
        drawSpeedGauge(dc, layout);
        drawMiddleRow(dc, layout);
        drawPanels(dc, layout);
        drawFooter(dc, layout);
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
        // :compact is declared in the profiles but has no layout of its own yet
        // — Phase 3 adds computeCompactLayout() and dispatches to it here.
        // Every shipped device is :full, so this is currently the only path.
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
        var gaugeCenterYOffset = mDeviceProfile[:gaugeCenterYOffset];
        var centerY = radius + topBarH + trackWidth + gaugeCenterYOffset;

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
                gaugeCenterYOffset +
                mDeviceProfile[:cadenceLineYOffset],

            :panelTop => panelTop,
            :panelH => panelH,
            :panelCenterY =>
                panelTop +
                panelH / 2.0 +
                (height * 0.01).toNumber() +
                mDeviceProfile[:panelCenterYOffset],
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
        var gaugeCenterYOffset = mDeviceProfile[:gaugeCenterYOffset];
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
            centerY + gaugeCenterYOffset + speedYOffset,
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

    // Returns a Dictionary of device-specific layout and font values keyed by screen size.
    // To add support for a new device, add a new profile block below.
    //
    // Profile keys:
    //   :layoutVariant         (Symbol) — which band stack computeLayout builds.
    //                            :full is the 1.67-aspect layout every shipped
    //                            device uses. :compact is reserved for the
    //                            246x322 devices and has no layout yet.
    //   :gaugeCenterYOffset    (Number) — vertical offset applied to gauge center and cadence/gradient line
    //   :speedFont             (Graphics.FontType) — font for the central speed readout
    //   :panelValueFont        (Graphics.FontType) — font for HR and power panel values
    //   :rowValueFont          (Graphics.FontType) — font for the top bar, elapsed time,
    //                            cadence/gear/grade and footer values. FONT_LARGE on 1.67
    //                            aspect screens; shorter screens step it down.
    //   :gaugeRadiusFactor     (Float) — speed gauge radius as a fraction of the narrow
    //                            screen dimension. 0.33 on 1.67 aspect screens; shorter
    //                            screens need less so the rows below still fit.
    //   :speedYOffset          (Number) — vertical shift for the central speed value and km/h label
    //   :elapsedTimeYOffset    (Number) — vertical shift for the elapsed time row
    //   :bottomLabelOffset     (Number) — extra downward shift for bottom bar labels
    //   :timeLabelOffset       (Number) — extra downward shift for the TIME label
    //   :cadenceLineYOffset    (Number) — vertical shift for the cadence/gradient row (negative = higher)
    //   :middleRowLabelOffset  (Number) — extra downward shift for CAD, DI2, GRD labels relative to the row
    //   :topBarYOffset         (Number) — vertical shift for the entire top bar (negative = higher)
    //   :topBarValueYOffset    (Number) — extra vertical shift for top bar values relative to labels (negative = closer)
    //   :footerValueYOffset    (Number) — extra downward shift for footer bar values
    //   :panelCenterYOffset    (Number) — extra downward shift for the HR and power panel center
    //   :panelTextYOffset      (Number) — vertical shift for panel values and avg text (negative = up), arc unaffected
    //   :panelTopLabelYOffset  (Number) — vertical shift for the HR / PWR top labels (negative = up)
    //   :hideClockLabel        (Boolean) — suppress the CLOCK label in the top bar
    //   :unitLabelFont         (Graphics.FontType) — font for km/h, HR, and CAD/PWR labels
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
        // --- Edge 850: 420 x 600 ---
        // Same 269 ppi font metrics as the 1050 but 200 fewer vertical pixels, so
        // the 1050 profile overflows by roughly 160 px. Must be tested before the
        // screenWidth >= 400 branch below, which would otherwise swallow it.
        // Recovered by stepping the row, speed and panel fonts down one each and
        // shrinking the gauge from 0.33 to 0.25 of screen width.
        if (deviceType.equals("edge850")) {
            return {
                :layoutVariant => :full,
                :gaugeCenterYOffset => 0,
                :speedYOffset => 6,
                :elapsedTimeYOffset => 20,
                :speedFont => Graphics.FONT_NUMBER_MEDIUM,
                :panelValueFont => Graphics.FONT_NUMBER_MILD,
                :rowValueFont => Graphics.FONT_MEDIUM,
                :gaugeRadiusFactor => 0.25,
                :bottomLabelOffset => 0,
                :timeLabelOffset => 0,
                :cadenceLineYOffset => 30,
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
                :panelCenterYOffset => 0,
                :panelTextYOffset => 0,
                :panelTopLabelYOffset => 0,
            };
        }

        // --- Edge 1050: 480 x 800 ---
        if (screenWidth >= 400) {
            return {
                :layoutVariant => :full,
                :gaugeCenterYOffset => -5,
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
                :panelCenterYOffset => 10,
                :panelTextYOffset => -12,
                :panelTopLabelYOffset => -12,
            };
        }

        // --- Edge Explore 2: 240 x 400 ---
        if (deviceType.equals("edgeexplore2")) {
            return {
                :layoutVariant => :full,
                :gaugeCenterYOffset => 5,
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
                :panelCenterYOffset => 8,
                :panelTextYOffset => -10,
                :panelTopLabelYOffset => -10,
            };
        }

        // --- Edge 840 / 540: 246 x 322 ---
        if (screenWidth < 260) {
            return {
                :layoutVariant => :full,
                :gaugeCenterYOffset => 8,
                :speedYOffset => 0,
                :elapsedTimeYOffset => 0,
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
                :panelCenterYOffset => 0,
                :panelTextYOffset => -10,
                :panelTopLabelYOffset => -10,
            };
        }

        // --- Edge 1030 / 1030 Plus: labels sit higher than on 1040 ---
        if (deviceType.equals("edge1030")) {
            return {
                :layoutVariant => :full,
                :gaugeCenterYOffset => 5,
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
                :panelCenterYOffset => 10,
                :panelTextYOffset => -10,
                :panelTopLabelYOffset => -10,
            };
        }

        // --- Edge 1040: 282 x 470 (default / fallback) ---
        return {
            :layoutVariant => :full,
            :gaugeCenterYOffset => 5,
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
            :panelCenterYOffset => 4,
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
