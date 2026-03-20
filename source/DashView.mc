import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Activity;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

class DashView extends WatchUi.DataField {
    private var mSpeed = 0.0;
    private var mAvgSpeed = 0.0;
    private var mMaxSpeed = 0.0;
    private var mDistance = 0.0;
    private var mElapsedMs = 0;
    private var mHeartRate = 0;
    private var mPower3s = 0;
    private var mTemp = 0.0;
    private var mCadence = 0;
    private var mCalories = 0;
    private var mAvgHeartRate = 0;
    private var mAvgPower = 0;

    // Header Fields
    private var mGrade = 0.0;
    private var mElevation = 0.0;
    private var mAscent = 0.0;
    private var mDescent = 0.0;

    private var mIsMetric = true;
    private var mIsElevationMetric = true;
    private var mTempUnit = "C";
    private var mGaugeColors = [
        0x29ff00, 0x45ff00, 0x60ff00, 0x7cff00, 0x97ff00, 0xb3ff00, 0xceff00,
        0xeaff00, 0xfaff00, 0xfff500, 0xffeb00, 0xffe000, 0xffd600, 0xffcb00,
        0xffc100, 0xffb600, 0xffac00, 0xffa100, 0xff9100, 0xff7c00, 0xff6200,
        0xff4800, 0xff2d00, 0xff0000,
    ];

    function initialize() {
        DataField.initialize();
        var settings = System.getDeviceSettings();
        mIsMetric = settings.paceUnits == System.UNIT_METRIC;
        mIsElevationMetric = settings.elevationUnits == System.UNIT_METRIC;
    }

    function compute(info as Activity.Info) as Void {
        var settings = System.getDeviceSettings();

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
                ? info.elapsedDistance / 1000.0
                : info.elapsedDistance * 0.000621371;
        }

        // Elapsed Time
        if (info.timerTime != null) {
            mElapsedMs = info.timerTime;
        }

        // Heart Rate
        if (info.currentHeartRate != null) {
            mHeartRate = info.currentHeartRate;
        } else {
            var actInfo = Activity.getActivityInfo();
            if (actInfo != null && actInfo.currentHeartRate != null) {
                mHeartRate = actInfo.currentHeartRate;
            }
        }
        if (info.averageHeartRate != null) {
            mAvgHeartRate = info.averageHeartRate;
        }

        // 3s Power
        if (info.currentPower != null) {
            mPower3s = info.currentPower;
        } else {
            var actInfo = Activity.getActivityInfo();
            if (actInfo != null && actInfo.currentPower != null) {
                mPower3s = actInfo.currentPower;
            }
        }
        if (info.averagePower != null) {
            mAvgPower = info.averagePower;
        }

        // Cadence
        if (info.currentCadence != null) {
            mCadence = info.currentCadence;
        }

        // Calories
        if (info.calories != null) {
            mCalories = info.calories;
        }

        // Temperature
        if (info has :ambientTemperature) {
            var rawTemp = info.ambientTemperature;
            if (rawTemp != null) {
                if (settings.temperatureUnits == System.UNIT_STATUTE) {
                    mTemp = (rawTemp * 9.0) / 5.0 + 32.0;
                    mTempUnit = "F";
                } else {
                    mTemp = rawTemp.toFloat();
                    mTempUnit = "C";
                }
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
        if (info.totalDescent != null) {
            mDescent = info.totalDescent * altMult;
        }
        if (info has :grade && info.grade != null) {
            mGrade = info.grade;
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var bgColor = getBackgroundColor();
        var isDark = bgColor == Graphics.COLOR_BLACK;
        var fgColor = isDark ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
        var dimColor = isDark ? Graphics.COLOR_DK_GRAY : Graphics.COLOR_LT_GRAY;

        dc.setColor(bgColor, bgColor);
        dc.clear();

        // --- STATUS BAR ---
        // dc.setColor(dimColor, Graphics.COLOR_TRANSPARENT);
        // dc.drawText(
        //     15,
        //     5,
        //     Graphics.FONT_XTINY,
        //     "GPS 3D",
        //     Graphics.TEXT_JUSTIFY_LEFT
        // );

        // var clockTime = System.getClockTime();
        // var timeStr = Lang.format("$1$:$2$", [
        //     clockTime.hour.format("%02d"),
        //     clockTime.min.format("%02d"),
        // ]);
        // var battery = System.getSystemStats().battery.toNumber();
        // dc.drawText(
        //     width - 15,
        //     5,
        //     Graphics.FONT_XTINY,
        //     battery.toString() + "%  " + timeStr,
        //     Graphics.TEXT_JUSTIFY_RIGHT
        // );

        // --- TOP STATS BAR (4 columns) ---
        var topBarY = 0;
        var topBarH = 65;
        dc.setPenWidth(1);
        dc.setColor(isDark ? 0x222222 : 0xdddddd, Graphics.COLOR_TRANSPARENT);

        // dc.drawLine(0, topBarY + topBarH, width, topBarY + topBarH); // Divider

        var colW = width / 3.0;
        // for (var i = 1; i < 3; i++) {
        //     dc.drawLine(colW * i, topBarY + 5, colW * i, topBarY + topBarH);
        // }

        // var topLabels = ["CADENCE", "GRADE", "ELEV"];
        var topValues = [
            mCadence.format("%.0f"),
            mGrade.format("%.0f") + "%",
            mElevation.format("%.0f"),
        ];

        for (var i = 0; i < 3; i++) {
            var x = colW * (i + 0.5);
            // dc.setColor(dimColor, Graphics.COLOR_TRANSPARENT);
            // dc.drawText(
            //     x,
            //     topBarY + 8,
            //     Graphics.FONT_XTINY,
            //     topLabels[i],
            //     Graphics.TEXT_JUSTIFY_CENTER
            // );
            dc.setColor(fgColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                x,
                topBarY + 8,
                Graphics.FONT_LARGE,
                topValues[i],
                Graphics.TEXT_JUSTIFY_CENTER
            );
        }

        // --- GAUGE LAYOUT (Adjusted height) ---
        var minDim = width < height ? width : height;
        var trackWidth = 40;
        var radius = minDim * 0.36;
        var centerX = width / 2.0;
        var centerY = radius + topBarH + trackWidth;
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
                i < litArcSegs ? mGaugeColors[i] : isDark ? 0x222222 : 0xdddddd,
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

        // --- SCALE ENDPOINTS ---
        var startRad = Math.toRadians(gaugeStart);
        var endRad = Math.toRadians(gaugeStart - gaugeSweep);
        var labelR = radius + trackWidth / 2.0 + 16;
        dc.setColor(dimColor, Graphics.COLOR_TRANSPARENT);
        // dc.drawText(
        //     centerX + labelR * Math.cos(startRad),
        //     centerY - labelR * Math.sin(startRad),
        //     Graphics.FONT_XTINY,
        //     "0",
        //     Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        // );
        // dc.drawText(
        //     centerX + labelR * Math.cos(endRad),
        //     centerY - labelR * Math.sin(endRad),
        //     Graphics.FONT_XTINY,
        //     maxVal.toNumber().toString(),
        //     Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        // );

        // --- AVG / MAX ABOVE SPEED ---
        dc.setColor(dimColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            centerX - radius * 0.35,
            centerY - radius * 0.65,
            Graphics.FONT_XTINY,
            "AVG",
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            centerX + radius * 0.35,
            centerY - radius * 0.65,
            Graphics.FONT_XTINY,
            "MAX",
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.setColor(fgColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            centerX - radius * 0.35,
            centerY - radius * 0.54,
            Graphics.FONT_MEDIUM,
            mAvgSpeed.format("%.1f"),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        dc.drawText(
            centerX + radius * 0.35,
            centerY - radius * 0.54,
            Graphics.FONT_MEDIUM,
            mMaxSpeed.format("%.1f"),
            Graphics.TEXT_JUSTIFY_CENTER
        );

        // --- CENTRAL SPEED READOUT ---
        dc.setColor(fgColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            centerY,
            Graphics.FONT_NUMBER_THAI_HOT,
            mSpeed.format("%.1f"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
        dc.setColor(dimColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            centerY + radius * 0.3,
            Graphics.FONT_SMALL,
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

        dc.setColor(fgColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            2 * radius + topBarH / 2,
            Graphics.FONT_LARGE,
            elapsedStr,
            Graphics.TEXT_JUSTIFY_CENTER
        );

        // Footer Y needed by panels
        var footerY = height - topBarH;

        // --- HR & POWER PANELS ---
        var panelTop = centerY + radius * 0.5 + topBarH;
        var panelH = footerY - panelTop - 8;
        var barH = panelH - 4;
        var segCount = 10;
        var segGap = 4;
        var lBarW = 16;
        var rBarW = 16;

        // ---- LEFT PANEL: Heart Rate ----
        var lBarX = 18;
        var lPanelCenterX = (lBarX + lBarW / 2 + width / 2.0) / 2.0;
        var lPanelCenterY = panelTop + panelH / 2.0 + 8;

        dc.setColor(dimColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            lPanelCenterX,
            lPanelCenterY - 70,
            Graphics.FONT_XTINY,
            "HR",
            Graphics.TEXT_JUSTIFY_CENTER
        );

        var segH = ((barH - (segCount - 1) * segGap) / segCount).toNumber();
        var hrRatio = mHeartRate.toFloat() / 200.0;
        if (hrRatio > 1.0) {
            hrRatio = 1.0;
        }
        var litSegs = (hrRatio * segCount + 0.5).toNumber();

        for (var i = 0; i < segCount; i++) {
            var segY = panelTop + 2 + barH - (i + 1) * (segH + segGap) + segGap;
            dc.setColor(
                i < litSegs
                    ? mGaugeColors[(i * 23) / 9]
                    : isDark
                      ? 0x1a1a1a
                      : 0xeeeeee,
                Graphics.COLOR_TRANSPARENT
            );
            dc.fillRoundedRectangle(
                lBarX - lBarW / 2,
                segY,
                lBarW,
                segH,
                segH / 2
            );
        }

        dc.setColor(fgColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            lPanelCenterX,
            lPanelCenterY,
            Graphics.FONT_NUMBER_HOT,
            mHeartRate.toString(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );

        dc.drawText(
            lPanelCenterX,
            lPanelCenterY + 70,
            Graphics.FONT_MEDIUM,
            mAvgHeartRate.format("%.0f"),
            Graphics.TEXT_JUSTIFY_CENTER
        );

        // ---- RIGHT PANEL: 3s Power ----
        var rBarX = width - 18;
        var rPanelCenterX = (width / 2.0 + rBarX - rBarW / 2) / 2.0;
        var rPanelCenterY = panelTop + panelH / 2.0 + 8;

        dc.setColor(dimColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            rPanelCenterX,
            rPanelCenterY - 70,
            Graphics.FONT_XTINY,
            "PWR",
            Graphics.TEXT_JUSTIFY_CENTER
        );

        var pwrRatio = mPower3s.toFloat() / 300.0;
        if (pwrRatio > 1.0) {
            pwrRatio = 1.0;
        }
        var litPwrSegs = (pwrRatio * segCount + 0.5).toNumber();

        for (var i = 0; i < segCount; i++) {
            var segY = panelTop + 2 + barH - (i + 1) * (segH + segGap) + segGap;
            dc.setColor(
                i < litPwrSegs
                    ? mGaugeColors[(i * 23) / 9]
                    : isDark
                      ? 0x1a1a1a
                      : 0xeeeeee,
                Graphics.COLOR_TRANSPARENT
            );
            dc.fillRoundedRectangle(
                rBarX - rBarW / 2,
                segY,
                rBarW,
                segH,
                segH / 2
            );
        }

        dc.setColor(fgColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            rPanelCenterX,
            rPanelCenterY,
            Graphics.FONT_NUMBER_HOT,
            mPower3s.toString(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );

        dc.drawText(
            rPanelCenterX,
            rPanelCenterY + 70,
            Graphics.FONT_MEDIUM,
            mAvgPower.format("%.0f"),
            Graphics.TEXT_JUSTIFY_CENTER
        );

        // --- STATS BAR (BOTTOM) ---
        dc.setPenWidth(1);
        dc.setColor(isDark ? 0x222222 : 0xdddddd, Graphics.COLOR_TRANSPARENT);

        // dc.drawLine(0, footerY, width, footerY);

        // for (var i = 1; i < 4; i++) {
        //     dc.drawLine(colW * i, footerY, colW * i, height);
        // }

        // var bottomLabels = ["TIME", "TEMP", "DIST", "TIMER"];
        var now = System.getClockTime();
        var bottomValues = [
            Lang.format("$1$:$2$", [
                now.hour.format("%02d"),
                now.min.format("%02d"),
            ]),
            mTemp.format("%d") + "°" + mTempUnit,
            mDistance.format("%.1f"),
        ];

        for (var i = 0; i < 3; i++) {
            var x = colW * (i + 0.5);
            dc.setColor(dimColor, Graphics.COLOR_TRANSPARENT);
            // dc.drawText(
            //     x,
            //     footerY + 8,
            //     Graphics.FONT_XTINY,
            //     bottomLabels[i],
            //     Graphics.TEXT_JUSTIFY_CENTER
            // );
            dc.setColor(fgColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                x,
                footerY + 8,
                Graphics.FONT_LARGE,
                bottomValues[i],
                Graphics.TEXT_JUSTIFY_CENTER
            );
        }
    }
}
