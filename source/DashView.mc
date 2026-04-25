import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Activity;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Sensor;
import Toybox.Application;

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

    // grade calculation
    private var mLastAlt = null;
    private var mLastDist = null;

    // Device-specific layout and font profile, set once in initialize()
    private var mDeviceProfile = null;

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
        if (info.altitude != null) {
            mElevation = info.altitude * altMult;
        }
        if (info.totalAscent != null) {
            mAscent = info.totalAscent * altMult;
        }
        // if (info.totalDescent != null) {
        //     mDescent = info.totalDescent * altMult;
        // }
        calculateGrade();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var bgColor = getBackgroundColor();
        var isDark = bgColor == Graphics.COLOR_BLACK;
        var fgColor = isDark ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
        var dimColor = isDark ? Graphics.COLOR_DK_GRAY : Graphics.COLOR_LT_GRAY;

        var speedFont = mDeviceProfile[:speedFont];
        var panelValueFont = mDeviceProfile[:panelValueFont];
        var speedNudge = mDeviceProfile[:speedNudge];
        var elapsedTimeNudge = mDeviceProfile[:elapsedTimeNudge];
        var bottomLabelOffset = mDeviceProfile[:bottomLabelOffset];
        var midLabelOffset = mDeviceProfile[:midLabelOffset];
        var hideClockLabel = mDeviceProfile[:hideClockLabel];
        var unitLabelFont = mDeviceProfile[:unitLabelFont];
        var avgMaxOffset = mDeviceProfile[:avgMaxOffset];
        var speedValueOffset = mDeviceProfile[:speedValueOffset];
        var avgPanelValueOffset = mDeviceProfile[:avgPanelValueOffset];
        var panelArcSweep = mDeviceProfile[:panelArcSweep];

        dc.setColor(bgColor, bgColor);
        dc.clear();

        // --- TOP STATS BAR (3 columns) ---
        var topBarY = 0;
        var topBarH = (height * 0.081).toNumber();
        dc.setPenWidth(1);
        dc.setColor(isDark ? 0x222222 : 0xdddddd, Graphics.COLOR_TRANSPARENT);

        var colW = width / 3.0;

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
            dc.setColor(fgColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                x,
                topBarY + 8,
                Graphics.FONT_LARGE,
                topValues[i],
                Graphics.TEXT_JUSTIFY_CENTER
            );
            if (!hideClockLabel || i != 1) {
                dc.setColor(dimColor, Graphics.COLOR_TRANSPARENT);
                dc.drawText(
                    x,
                    topBarY + 8 + dc.getFontHeight(Graphics.FONT_LARGE) - 6,
                    Graphics.FONT_XTINY,
                    topLabels[i],
                    Graphics.TEXT_JUSTIFY_CENTER
                );
            }
        }

        // --- GAUGE LAYOUT (Adjusted height) ---
        var minDim = width < height ? width : height;
        var trackWidth = (width * 0.083).toNumber();
        var radius = minDim * 0.33;
        var centerX = width / 2.0;
        var heightOffset = mDeviceProfile[:heightOffset];
        var centerY = minDim * 0.33 + topBarH + trackWidth + heightOffset;
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

        dc.setPenWidth(trackWidth);
        for (var i = 0; i < arcSegCount; i++) {
            var segStartDeg = gaugeStart - i * segArcLen;
            var segEndDeg = segStartDeg - segArcLen + segGapDeg;
            dc.setColor(
                i < litArcSegs ? 0x0066ff : isDark ? 0x222222 : 0xdddddd,
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
        dc.setColor(dimColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            centerX - radius * 0.35,
            centerY - radius * 0.65 + avgMaxOffset,
            Graphics.FONT_XTINY,
            "AVG",
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            centerX + radius * 0.35,
            centerY - radius * 0.65 + avgMaxOffset,
            Graphics.FONT_XTINY,
            "MAX",
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.setColor(fgColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            centerX - radius * 0.35,
            centerY - radius * 0.54 + avgMaxOffset,
            Graphics.FONT_MEDIUM,
            mAvgSpeed.format("%.1f"),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            centerX + radius * 0.35,
            centerY - radius * 0.54 + avgMaxOffset,
            Graphics.FONT_MEDIUM,
            mMaxSpeed.format("%.1f"),
            Graphics.TEXT_JUSTIFY_CENTER
        );

        // --- CENTRAL SPEED READOUT ---
        dc.setColor(fgColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            centerY + heightOffset + speedNudge + speedValueOffset,
            speedFont,
            mSpeed.format("%.1f"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
        dc.setColor(dimColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            centerY + radius * 0.3 + speedNudge + speedValueOffset,
            unitLabelFont,
            mIsMetric ? "km/h" : "mph",
            Graphics.TEXT_JUSTIFY_CENTER
        );

        // --- ELAPSED TIME ---

        var totalSecs = mElapsedMs / 1000;
        var elapsedStr = Lang.format("$1$:$2$:$3$", [
            (totalSecs / 3600).format("%d"),
            ((totalSecs % 3600) / 60).format("%02d"),
            (totalSecs % 60).format("%02d"),
        ]);

        var xtinyH = dc.getFontHeight(Graphics.FONT_XTINY);
        var largeH = dc.getFontHeight(Graphics.FONT_LARGE);
        var elapsedY = 2 * radius + topBarH / 2 + xtinyH + 1 + elapsedTimeNudge;
        dc.setColor(dimColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            elapsedY - xtinyH - 1 + midLabelOffset,
            Graphics.FONT_XTINY,
            "TIME",
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.setColor(fgColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            elapsedY,
            Graphics.FONT_LARGE,
            elapsedStr,
            Graphics.TEXT_JUSTIFY_CENTER
        );

        // --- CADENCE AND GRADIENT ---

        var cadenceAndGradientLineY = 2 * radius + topBarH * 2 - heightOffset;
        dc.setColor(dimColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            width * 0.15,
            cadenceAndGradientLineY - xtinyH - 1 + midLabelOffset,
            Graphics.FONT_XTINY,
            "CAD",
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            width * 0.5,
            cadenceAndGradientLineY - xtinyH - 1 + midLabelOffset,
            Graphics.FONT_XTINY,
            "DI2",
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            width * 0.85,
            cadenceAndGradientLineY - xtinyH - 1 + midLabelOffset,
            Graphics.FONT_XTINY,
            "GRD",
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.setColor(fgColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            width * 0.15,
            cadenceAndGradientLineY,
            Graphics.FONT_LARGE,
            mCadence.format("%.0f"),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            width * 0.5,
            cadenceAndGradientLineY,
            Graphics.FONT_LARGE,
            mGearInfo,
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            width * 0.85,
            cadenceAndGradientLineY,
            Graphics.FONT_LARGE,
            mGrade.format("%.1f"),
            Graphics.TEXT_JUSTIFY_CENTER
        );

        // Footer Y needed by panels
        var footerY = height - dc.getFontHeight(Graphics.FONT_LARGE) - 4;

        // --- HR & POWER PANELS ---
        var panelTop = centerY + radius * 0.5 + topBarH * 2;
        var panelH = footerY - panelTop - (height * 0.01).toNumber();
        var barW = (width * 0.063).toNumber();

        // ---- LEFT PANEL: Heart Rate ----
        var lBarX = (width * 0.021).toNumber();
        var sideRadius = centerX - lBarX - barW / 2.0;
        var sideCenterY = panelTop + panelH / 2.0 + (height * 0.01).toNumber();
        var arcSweepDeg = panelArcSweep;
        var segCount = 10;
        var gapDeg = 1.0; // The physical gap between segments

        // Calculate how many degrees each individual block gets
        var totalGapSweep = gapDeg * (segCount - 1);
        var segSweepDeg = (arcSweepDeg - totalGapSweep) / segCount;

        var bgTrackColor = isDark ? 0x1a1a1a : 0xeeeeee;

        // ---- LEFT PANEL: Heart Rate ----
        var lPanelCenterX = (lBarX + barW / 2 + centerX) / 2.0;
        // Start at bottom-left (e.g., 210 deg)
        var hrStartAngle = 180.0 + arcSweepDeg / 2.0;
        var panelLabelOffset = (height * 0.088).toNumber();

        dc.setColor(dimColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            lPanelCenterX,
            sideCenterY - panelLabelOffset,
            unitLabelFont,
            "HR",
            Graphics.TEXT_JUSTIFY_CENTER
        );

        var hrRatio = mHeartRate != null ? mHeartRate.toFloat() / 200.0 : 0.0;
        if (hrRatio > 1.0) {
            hrRatio = 1.0;
        }
        var litSegs = (hrRatio * segCount + 0.5).toNumber();

        dc.setPenWidth(barW);

        for (var i = 0; i < segCount; i++) {
            // Clockwise goes down in angle
            var segStart = hrStartAngle - i * (segSweepDeg + gapDeg);
            var segEnd = segStart - segSweepDeg;

            // Set lit color or dark background color
            dc.setColor(
                i < litSegs ? 0xff2200 : bgTrackColor,
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

        dc.setColor(fgColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            lPanelCenterX,
            sideCenterY,
            panelValueFont,
            mHeartRate != null ? mHeartRate.toString() : "--",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
        dc.setColor(dimColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            lPanelCenterX,
            sideCenterY + panelLabelOffset - xtinyH - 1 + avgMaxOffset,
            Graphics.FONT_XTINY,
            "AVG",
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.setColor(fgColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            lPanelCenterX,
            sideCenterY + panelLabelOffset + avgPanelValueOffset + avgMaxOffset,
            Graphics.FONT_MEDIUM,
            mAvgHeartRate.format("%.0f"),
            Graphics.TEXT_JUSTIFY_CENTER
        );

        // ---- RIGHT PANEL: 3s Power ----
        var rBarX = width - (width * 0.038).toNumber();
        var rPanelCenterX = (centerX + rBarX - barW / 2) / 2.0;
        // Start at bottom-right (e.g., 330 deg)
        var pwrStartAngle = 360.0 - arcSweepDeg / 2.0;

        dc.setColor(dimColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            rPanelCenterX,
            sideCenterY - panelLabelOffset,
            unitLabelFont,
            mHasPowerData ? "PWR" : "CAD",
            Graphics.TEXT_JUSTIFY_CENTER
        );

        var rightRatio = 0.0;
        if (mHasPowerData) {
            var powerScaleMax = 400.0;
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

        dc.setPenWidth(barW);

        for (var i = 0; i < segCount; i++) {
            // Right side goes Counter-Clockwise (increases in angle)
            var pwrSegStart = pwrStartAngle + i * (segSweepDeg + gapDeg);
            var pwrSegEnd = pwrSegStart + segSweepDeg;

            dc.setColor(
                i < litPwrSegs
                    ? mHasPowerData
                        ? 0x9900ff
                        : 0xff8800
                    : bgTrackColor,
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

        dc.setColor(fgColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            rPanelCenterX,
            sideCenterY,
            panelValueFont,
            mHasPowerData ? mPower3s.toString() : mCadence.format("%.0f"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
        dc.setColor(dimColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            rPanelCenterX,
            sideCenterY + panelLabelOffset - xtinyH - 1 + avgMaxOffset,
            Graphics.FONT_XTINY,
            "AVG",
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.setColor(fgColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            rPanelCenterX,
            sideCenterY + panelLabelOffset + avgPanelValueOffset + avgMaxOffset,
            Graphics.FONT_MEDIUM,
            mHasPowerData
                ? mAvgPower.format("%.0f")
                : mAvgCadence.format("%.0f"),
            Graphics.TEXT_JUSTIFY_CENTER
        );

        var bottomValues = [
            mAscent.format("%.0f"),
            (mDistance / 1000).format("%.1f"),
            mCalories.format("%.0f"),
        ];
        var bottomLabels = ["ASC", "DIST", "CAL"];

        for (var i = 0; i < 3; i++) {
            var x = colW * (i + 0.5);
            dc.setColor(dimColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                x,
                footerY + 2 - xtinyH + bottomLabelOffset,
                Graphics.FONT_XTINY,
                bottomLabels[i],
                Graphics.TEXT_JUSTIFY_CENTER
            );
            dc.setColor(fgColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                x,
                footerY + 2,
                Graphics.FONT_LARGE,
                bottomValues[i],
                Graphics.TEXT_JUSTIFY_CENTER
            );
        }
    }

    // Returns a Dictionary of device-specific layout and font values keyed by screen size.
    // To add support for a new device, add a new profile block below.
    //
    // Profile keys:
    //   :heightOffset       (Number) — vertical offset applied to gauge center and cadence/gradient line
    //   :speedFont          (Graphics.FontType) — font for the central speed readout
    //   :panelValueFont     (Graphics.FontType) — font for HR and power panel values
    //   :bottomLabelOffset  (Number)  — extra downward shift for bottom bar labels
    //   :midLabelOffset     (Number)  — extra downward shift for TIME, CAD, DI2, GRD labels
    //   :hideClockLabel     (Boolean)        — suppress the CLOCK label in the top bar
    //   :unitLabelFont      (Graphics.FontType) — font for km/h, HR, and CAD/PWR labels
    //   :avgMaxOffset       (Number) — vertical shift for AVG/MAX speed labels and values (negative = up)
    //   :speedValueOffset      (Number) — extra downward shift for the central speed value and km/h label
    //   :avgPanelValueOffset   (Number) — vertical shift for avg HR and avg power/cadence values (negative = up)
    //   :panelArcSweep         (Float)  — total sweep angle in degrees for HR and power arc gauges
    private function initDeviceProfile(
        screenWidth as Number,
        screenHeight as Number,
        deviceType as String
    ) as Lang.Dictionary {
        // --- Edge 1050: 480 x 800 ---
        if (screenWidth >= 400) {
            return {
                :heightOffset => 0,
                :speedNudge => 0,
                :elapsedTimeNudge => 0,
                :speedFont => Graphics.FONT_NUMBER_THAI_HOT,
                :panelValueFont => Graphics.FONT_NUMBER_HOT,
                :bottomLabelOffset => 0,
                :midLabelOffset => 0,
                :hideClockLabel => false,
                :unitLabelFont => Graphics.FONT_SMALL,
                :avgMaxOffset => 0,
                :speedValueOffset => 0,
                :avgPanelValueOffset => 0,
                :panelArcSweep => 54.0,
            };
        }

        // --- Edge 840 / 540: 246 x 322 ---
        if (screenWidth < 260) {
            return {
                :heightOffset => 8,
                :speedNudge => 0,
                :elapsedTimeNudge => 0,
                :speedFont => Graphics.FONT_NUMBER_HOT,
                :panelValueFont => Graphics.FONT_NUMBER_MEDIUM,
                :bottomLabelOffset => 0,
                :midLabelOffset => 0,
                :hideClockLabel => false,
                :unitLabelFont => Graphics.FONT_SMALL,
                :avgMaxOffset => 0,
                :speedValueOffset => 0,
                :avgPanelValueOffset => 0,
                :panelArcSweep => 54.0,
            };
        }

        // --- Edge 1030 / 1030 Plus: labels sit higher than on 1040 ---
        if (deviceType.equals("edge1030")) {
            return {
                :heightOffset => 5,
                :speedNudge => -10,
                :elapsedTimeNudge => -13,
                :speedFont => Graphics.FONT_NUMBER_HOT,
                :panelValueFont => Graphics.FONT_NUMBER_MEDIUM,
                :bottomLabelOffset => 8,
                :midLabelOffset => 8,
                :hideClockLabel => true,
                :unitLabelFont => Graphics.FONT_XTINY,
                :avgMaxOffset => -6,
                :speedValueOffset => 10,
                :avgPanelValueOffset => -6,
                :panelArcSweep => 45.0,
            };
        }

        // --- Edge 1040: 282 x 470 (default / fallback) ---
        return {
            :heightOffset => 5,
            :speedNudge => -10,
            :elapsedTimeNudge => -10,
            :speedFont => Graphics.FONT_NUMBER_HOT,
            :panelValueFont => Graphics.FONT_NUMBER_MEDIUM,
            :bottomLabelOffset => 0,
            :midLabelOffset => 0,
            :hideClockLabel => false,
            :unitLabelFont => Graphics.FONT_SMALL,
            :avgMaxOffset => 0,
            :speedValueOffset => 0,
            :avgPanelValueOffset => 0,
            :panelArcSweep => 54.0,
        };
    }

    private function calculateGrade() as Void {
        // --- NEW GRADE CALCULATION ---
        if (mElevation != null && mDistance != null) {
            // Initialize the tracking variables on the first valid reading
            if (mLastAlt == null || mLastDist == null) {
                mLastAlt = mElevation;
                mLastDist = mDistance;
            } else {
                var distDiff = mDistance - mLastDist;

                // Wait until we've covered at least 15 meters to recalculate.
                // This smooths out the sensor drift so the grade isn't jumpy.
                if (distDiff > 15.0) {
                    var altDiff = mElevation - mLastAlt;

                    // Grade is (Rise / Run) * 100
                    mGrade = (altDiff / distDiff) * 100.0;

                    // Cap the grade to realistic cycling limits (-30% to +30%)
                    if (mGrade > 30.0) {
                        mGrade = 30.0;
                    }
                    if (mGrade < -30.0) {
                        mGrade = -30.0;
                    }

                    // Update the markers for the next interval
                    mLastAlt = mElevation;
                    mLastDist = mDistance;
                }
            }
        }

        // Reset grade to 0% if the rider comes to a stop
        if (mSpeed == null || mSpeed < 1.0) {
            mGrade = 0.0;
        }
    }
}
