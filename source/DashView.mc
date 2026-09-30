import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Activity;
import Toybox.Lang;
import Toybox.Application;
import Toybox.Background;
import Toybox.UserProfile;
import Toybox.Math;

class DashView extends WatchUi.DataField {
    // Live metrics. The ones that can drop out mid-ride are nullable and the
    // draw path renders "--" for them: a power meter or cadence sensor that
    // disconnects used to leave its last value frozen on screen, which reads
    // as live data. Cumulative stats (averages, maxima, totals) are not
    // nullable — they keep their last value by definition.
    private var mSpeed as Float = 0.0;
    private var mAvgSpeed as Float = 0.0;
    private var mMaxSpeed as Float = 0.0;
    private var mDistance as Float = 0.0;
    private var mElapsedMs as Number = 0;
    private var mHeartRate as Number? = null;
    private var mPower3s as Number? = null;
    private var mTemp as Float? = null;
    private var mCadence as Number? = null;
    private var mCalories as Number = 0;
    private var mAvgHeartRate as Number = 0;
    private var mAvgCadence as Number = 0;
    private var mAvgPower as Number = 0;
    private var mMaxPower as Number = 0;
    private var mHasPowerData as Boolean = false;

    // Header Fields
    private var mGrade as Float = 0.0;
    private var mElevation as Float = 0.0;
    private var mAscent as Float = 0.0;
    private var mGearInfo as String = "--";

    private var mIsMetric as Boolean = true;
    private var mIsElevationMetric as Boolean = true;
    private var mIsTempStatute as Boolean = false;

    // grade calculation (tracked in raw meters, independent of display units)
    private var mGradeLastAlt as Float? = null;
    private var mGradeLastDist as Float? = null;
    // Consecutive compute() calls that produced no grade update. Once the window
    // anchor is stranded (or its inputs drop out) nothing else can unstick it,
    // so a long enough run of dead computes forces a re-seed.
    private var mGradeStallCount as Number = 0;
    private const GRADE_STALL_LIMIT = 60;

    // Last temperature handed over by the background service, pushed in by
    // DashApp.onBackgroundData. Seeded from Storage once at startup so a
    // restart mid-ride does not blank the reading; compute() never touches
    // Storage, which used to cost a flash-backed read every second for a value
    // that changes every five minutes.
    private var mBackgroundTemp as Numeric? = null;
    // Set once info.ambientTemperature returns a real reading. That proves the
    // device reports temperature directly, so the five-minute background wake
    // is pure battery cost and gets cancelled. DashApp re-registers on the next
    // load if it turns out to be needed after all.
    private var mDirectTempSeen as Boolean = false;

    // Device-specific layout and font profile, set once in initialize()
    private var mDeviceProfile as Lang.Dictionary;

    // Band geometry every draw function works from. Depends only on the dc
    // dimensions, the device profile and font heights, so it is computed on the
    // first draw and reused; the width/height guard picks up a data-screen
    // layout change without costing anything on a normal frame.
    // Named ...Cache because WatchUi.View already declares a protected mLayout.
    private var mLayoutCache as Lang.Dictionary? = null;
    private var mLayoutWidth as Number = -1;
    private var mLayoutHeight as Number = -1;

    // Palette for the frame being drawn. Recomputed at the top of every
    // onUpdate because the device's dark/light setting can change at runtime;
    // held in fields so the draw pass itself allocates nothing.
    private var mBgColor as Number = Graphics.COLOR_BLACK;
    private var mValuesColor as Number = 0xffffff;
    private var mLabelsColor as Number = 0xeeeeee;
    private var mTrackColor as Number = 0xeeeeee;

    private const COLOR_SPEED = 0x0066ff;
    private const COLOR_HR = 0xff2200;
    private const COLOR_POWER = 0x9900ff;
    private const COLOR_CADENCE = 0xff8800;
    private const COLOR_AVG_INDICATOR = 0xff8800;   //orange
    private const COLOR_MAX_INDICATOR = 0x00aa00;   //green

    // Band label rows. Constant for the life of the field, so they live here
    // rather than being rebuilt as fresh Arrays on every draw call.
    private const TOP_LABELS = ["TEMP", "CLOCK", "ELEV"];
    private const BOTTOM_LABELS = ["ASC", "DIST", "CAL"];
    private const COMPACT_TOP_LABELS = ["TEMP", "CLOCK", "ELEV", "DI2"];
    private const COMPACT_FOOTER_COLUMNS = [0.18, 0.45, 0.66, 0.87];

    // Placeholder for a metric whose sensor is not reporting.
    private const NO_VALUE = "--";

    // Fallback full-scale speed when the speedGaugeMax setting is left at 0.
    private const SPEED_MAX_DEFAULT_METRIC = 60.0;
    private const SPEED_MAX_DEFAULT_STATUTE = 40.0;
    // Used when FTP is missing or nonsensical. The setting itself is clamped to
    // 50 W at the bottom, but a null or corrupt stored value still lands here.
    private const FTP_DEFAULT = 200;

    // Zone boundaries for arc coloring, refreshed by readSettings().
    // HR zones come from the user's Garmin profile; power zones are derived from the FTP app setting.
    private var mHrZoneBoundaries as Array<Number>? = null;
    private var mPowerZoneBoundaries as Array<Numeric>? = null;
    // Always a usable positive number: it is the divisor for the power gauge.
    private var mFtp as Number = FTP_DEFAULT;
    private var mSpeedGaugeMax as Float = SPEED_MAX_DEFAULT_METRIC;
    // Avg/max markers on the speed arc, from the visualizeSpeedIndicator setting.
    private var mShowSpeedIndicators as Boolean = true;
    private const ZONE_COLORS = [
        0x4da6ff, // Z1 - blue
        0x33cc33, // Z2 - green
        0xffcc00, // Z3 - yellow
        0xff8800, // Z4 - orange
        0xff2200, // Z5 - red
    ];

    function initialize() {
        DataField.initialize();
        var settings = System.getDeviceSettings();
        var deviceType = WatchUi.loadResource(Rez.Strings.deviceType) as String;
        mDeviceProfile = DeviceProfiles.forDevice(
            settings.screenWidth,
            settings.screenHeight,
            deviceType
        );
        mBackgroundTemp = Storage.getValue("sensorTemperature") as Numeric?;
        readSettings();
    }

    // Everything that comes from device settings, the user profile or the app's
    // own properties, in one place so onSettingsChanged can re-run it. Before
    // this existed an FTP edit in Connect IQ did nothing until the data field
    // was recreated, and temperatureUnits was re-read on every compute().
    private function readSettings() as Void {
        var settings = System.getDeviceSettings();
        mIsMetric = settings.paceUnits == System.UNIT_METRIC;
        mIsElevationMetric = settings.elevationUnits == System.UNIT_METRIC;
        mIsTempStatute = settings.temperatureUnits == System.UNIT_STATUTE;

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
        var ftp = null;
        if (UserProfile has :getFunctionalThresholdPower) {
            try {
                ftp = UserProfile.getFunctionalThresholdPower(
                    Activity.SPORT_CYCLING
                );
            } catch (e) {
                ftp = null;
            }
        }
        if (!(ftp instanceof Lang.Number) || ftp <= 0) {
            ftp = Application.Properties.getValue("ftp");
        }
        // mFtp is the divisor for the power gauge's full-scale value, so it is
        // never allowed to be null or zero. The setting used to permit 0, which
        // divided by zero at ride start before any max power had been recorded.
        if (!(ftp instanceof Lang.Number) || ftp <= 0) {
            ftp = FTP_DEFAULT;
        }
        mFtp = ftp;
        // Coggan-style boundaries derived from FTP.
        mPowerZoneBoundaries = [
            0,
            mFtp * 0.55,
            mFtp * 0.75,
            mFtp * 0.9,
            mFtp * 1.05,
            mFtp * 999,
        ];

        // Speed gauge full scale, in the rider's display units. 0 means "leave
        // it at the built-in default", which is what ships.
        var speedMax = Application.Properties.getValue("speedGaugeMax");
        if (speedMax instanceof Lang.Number && speedMax > 0) {
            mSpeedGaugeMax = speedMax.toFloat();
        } else {
            mSpeedGaugeMax = mIsMetric
                ? SPEED_MAX_DEFAULT_METRIC
                : SPEED_MAX_DEFAULT_STATUTE;
        }

        // Avg/max speed markers. Read here rather than once in initialize() so
        // toggling the setting mid-ride takes effect through onSettingsChanged.
        var showIndicators = Application.Properties.getValue("visualizeSpeedIndicator");
        mShowSpeedIndicators = !(showIndicators instanceof Lang.Boolean) || showIndicators;
    }

    // Called by DashApp when the user edits the app's settings.
    function onSettingsChanged() as Void {
        readSettings();
    }

    // Called by DashApp when the background service reports a temperature.
    function onSensorTemperature(temp as Numeric) as Void {
        mBackgroundTemp = temp;
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

    // How full the HR gauge should be, 0.0 to 1.0. Scaled across the user's
    // own zone span when the profile has zones, 0-200 bpm otherwise.
    //
    // Shared by drawPanels and drawCompactBars. The two render paths
    // deliberately share no geometry, but this is metric arithmetic rather
    // than geometry, and keeping one copy is what stops the arc and the bar
    // disagreeing about what a given heart rate means.
    private function hrFillRatio() as Float {
        var hr = mHeartRate;
        if (hr == null) {
            return 0.0;
        }
        var hrMin = 0.0;
        var hrMax = 200.0;
        var hrZones = mHrZoneBoundaries;
        if (hrZones != null && hrZones.size() >= 6) {
            hrMin = hrZones[0].toFloat();
            hrMax = hrZones[5].toFloat();
        }
        var hrRange = hrMax - hrMin;
        if (hrRange <= 0) {
            return 0.0;
        }
        return clampRatio((hr.toFloat() - hrMin) / hrRange);
    }

    // How full the right-hand gauge should be, 0.0 to 1.0. Power against FTP
    // (or the ride's max power, once it exceeds FTP) when a meter is present,
    // otherwise cadence against 150 rpm. mFtp is guaranteed positive by
    // readSettings, which is what keeps this from dividing by zero.
    private function rightFillRatio() as Float {
        if (mHasPowerData) {
            var power = mPower3s;
            if (power == null) {
                return 0.0;
            }
            var powerScaleMax = mFtp.toFloat();
            if (mMaxPower > powerScaleMax) {
                powerScaleMax = mMaxPower.toFloat();
            }
            return clampRatio(power.toFloat() / powerScaleMax);
        }
        var cadence = mCadence;
        if (cadence == null) {
            return 0.0;
        }
        return clampRatio(cadence.toFloat() / 150.0);
    }

    private function clampRatio(ratio as Float) as Float {
        if (ratio > 1.0) {
            return 1.0;
        }
        if (ratio < 0.0) {
            return 0.0;
        }
        return ratio;
    }

    // Lit segment count for a gauge of `segCount` segments. `floorToOne` keeps
    // a live-but-very-low reading visible as one lit segment instead of an
    // empty gauge; it is off for power, where zero watts is a real reading.
    private function litSegments(
        ratio as Float,
        segCount as Number,
        floorToOne as Boolean
    ) as Number {
        var lit = (ratio * segCount + 0.5).toNumber();
        if (floorToOne && lit < 1) {
            lit = 1;
        }
        return lit;
    }

    // The colour the right-hand gauge lights up in.
    private function rightZoneColor() as Number {
        if (!mHasPowerData) {
            return COLOR_CADENCE;
        }
        var power = mPower3s;
        return zoneColor(power != null ? power : 0, mPowerZoneBoundaries, COLOR_POWER);
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

    // `info` is the current Activity.Info. The redundant
    // Activity.getActivityInfo() call this used to make on every tick returned
    // the same object, so its "fallbacks" could never differ from the values
    // already in hand; the `has` guards moved onto `info` unchanged.
    function compute(info as Activity.Info) as Void {
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
        mHeartRate = info.currentHeartRate;
        if (info.averageHeartRate != null) {
            mAvgHeartRate = info.averageHeartRate;
        }

        // Shifting
        mGearInfo = NO_VALUE;
        var rear = info has :rearDerailleurIndex
            ? info.rearDerailleurIndex
            : null;
        var front = info has :frontDerailleurIndex
            ? info.frontDerailleurIndex
            : null;
        if (rear != null) {
            if (rear > 13 || rear < 1) {
                rear = 1;
            }
            mGearInfo = rear.format("%d");
            if (front != null) {
                if (front > 3 || front < 1) {
                    front = 1;
                }
                mGearInfo = front.format("%d") + ":" + mGearInfo;
            }
        }

        // 3s Power. mPower3s goes back to null the moment the meter stops
        // reporting, so a dropout shows "--" rather than freezing the last
        // watt number on screen. mHasPowerData stays true for the rest of the
        // ride once any power has been seen, which is what keeps the right
        // panel a power gauge instead of flipping to cadence at every gap.
        mPower3s = info.currentPower;
        if (mPower3s != null) {
            mHasPowerData = true;
        }
        if (info.averagePower != null) {
            mAvgPower = info.averagePower;
            mHasPowerData = true;
        }

        // Max Power
        if (info.maxPower != null) {
            mMaxPower = info.maxPower;
            mHasPowerData = true;
        }

        // Cadence. Same dropout handling as power. The old "halve anything over
        // 150 rpm" correction is gone: it silently halved a legitimate sprint
        // cadence, and Garmin already validates this value.
        mCadence = info.currentCadence;
        if (info.averageCadence != null) {
            mAvgCadence = info.averageCadence;
        }

        // Calories
        if (info.calories != null) {
            mCalories = info.calories;
        }

        // --- TEMPERATURE RESOLUTION ---
        // Priority 1: the background service's reading, pushed in by
        // DashApp.onBackgroundData and seeded from Storage at startup.
        var rawTemp = mBackgroundTemp;

        // Priority 2: Activity.Info (Standard way)
        if (info has :ambientTemperature && info.ambientTemperature != null) {
            rawTemp = info.ambientTemperature;
            if (!mDirectTempSeen) {
                mDirectTempSeen = true;
                // The device reports temperature directly, so the five-minute
                // background wake buys nothing. Cancel it; DashApp registers
                // again on the next load, and this cancels it again one tick
                // later, so at worst one wake per ride is wasted.
                if (
                    System has :ServiceDelegate &&
                    Background.getTemporalEventRegisteredTime() != null
                ) {
                    Background.deleteTemporalEvent();
                }
            }
        }

        // Priority 3: SensorHistory fallback (for older CIQ devices like Edge 1030)
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

        if (rawTemp == null) {
            mTemp = null;
        } else if (mIsTempStatute) {
            mTemp = (rawTemp * 9.0) / 5.0 + 32.0;
        } else {
            mTemp = rawTemp.toFloat();
        }

        // Elevation Data
        var altMult = mIsElevationMetric ? 1.0 : 3.28084;
        var rawAlt = info.altitude;
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

    // --- VALUE FORMATTING ---------------------------------------------------
    //
    // One place per metric that can be absent, so the two render paths print
    // the same thing when a sensor is not reporting.

    private function tempString() as String {
        var temp = mTemp;
        if (temp == null) {
            return NO_VALUE;
        }
        return temp.format("%.1f") + "°";
    }

    private function cadenceString() as String {
        var cadence = mCadence;
        return cadence != null ? cadence.format("%d") : NO_VALUE;
    }

    private function clockString(now as System.ClockTime) as String {
        return Lang.format("$1$:$2$", [
            now.hour.format("%02d"),
            now.min.format("%02d"),
        ]);
    }

    // h:mm:ss, hours unpadded.
    private function elapsedString() as String {
        var totalSecs = mElapsedMs / 1000;
        return Lang.format("$1$:$2$:$3$", [
            (totalSecs / 3600).format("%d"),
            ((totalSecs % 3600) / 60).format("%02d"),
            (totalSecs % 60).format("%02d"),
        ]);
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
            tempString(),
            clockString(now),
            mElevation.format("%.0f"),
        ];
        var topLabels = TOP_LABELS;

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
        var speedYOffset = mDeviceProfile[:speedYOffset];
        var unitLabelYOffset = mDeviceProfile[:unitLabelYOffset];
        var avgLabelOffset = mDeviceProfile[:avgLabelOffset];
        var speedAvgValueOffset = mDeviceProfile[:speedAvgValueOffset];

        var maxVal = mSpeedGaugeMax;
        var gaugeStart = 210.0;
        var gaugeSweep = 240.0;

        // --- SEGMENTED ARC GAUGE (SPEED) ---
        var arcSegCount = 24;
        var segArcLen = gaugeSweep / arcSegCount;
        var segGapDeg = 2.5;
        
        // --- 1. VALUE CLAMPING ---
        var ratio = mSpeed / maxVal;
        if (ratio > 1.0) { ratio = 1.0; }
        if (ratio < 0.0) { ratio = 0.0; }
        var activeSweep = ratio * gaugeSweep;

        var avgRatio = mAvgSpeed / maxVal;
        if (avgRatio > 1.0) { avgRatio = 1.0; }
        if (avgRatio < 0.0) { avgRatio = 0.0; }

        var maxRatio = mMaxSpeed / maxVal;
        if (maxRatio > 1.0) { maxRatio = 1.0; }
        if (maxRatio < 0.0) { maxRatio = 0.0; }

        dc.setPenWidth(layout[:trackWidth]);

        // --- 2. STEP ONE: DRAW THE ENTIRE BACKGROUND TRACK (GREY) ---
        dc.setColor(mTrackColor, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < arcSegCount; i++) {
            var segStartDeg = gaugeStart - i * segArcLen;
            var segEndDeg = segStartDeg - segArcLen + segGapDeg;
            
            dc.drawArc(centerX, centerY, radius, Graphics.ARC_CLOCKWISE, segStartDeg, segEndDeg);
        }

        // --- 3. STEP TWO: OVERLAY THE ACTIVE SPEED (SMOOTH FILL) ---
        dc.setColor(COLOR_SPEED, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < arcSegCount; i++) {
            var segStartDeg = gaugeStart - i * segArcLen;
            var segEndDeg = segStartDeg - segArcLen + segGapDeg;
            
            var currentSegStartSweep = i * segArcLen;
            var currentSegEndSweep = (i + 1) * segArcLen - segGapDeg;

            if (activeSweep >= currentSegEndSweep) {
                // Speed completely covers this block -> Fill full segment
                dc.drawArc(centerX, centerY, radius, Graphics.ARC_CLOCKWISE, segStartDeg, segEndDeg);
            } 
            else if (activeSweep > currentSegStartSweep) {
                // Speed ends mid-segment -> Safely calculate partial fill
                var partialSweep = activeSweep - currentSegStartSweep;
                var smoothCutoffDeg = segStartDeg - partialSweep;

                // Protect against 0-degree / full-circle inversion error
                if ((segStartDeg - smoothCutoffDeg).abs() > 0.1) {
                    dc.drawArc(centerX, centerY, radius, Graphics.ARC_CLOCKWISE, segStartDeg, smoothCutoffDeg);
                }
                break; // No need to process remaining segments since speed is exhausted
            } 
            else {
                break; // Remaining segments are unreached
            }
        }

        // --- 4. STEP THREE: DRAW THE AVERAGE SPEED INDICATOR ---
        if (mAvgSpeed > 0.0 and mShowSpeedIndicators) {
            var avgAngleDeg = gaugeStart - (avgRatio * gaugeSweep);
            dc.setColor(COLOR_AVG_INDICATOR, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(layout[:trackWidth] + 4);
            
            dc.drawArc(
                centerX,
                centerY,
                radius,
                Graphics.ARC_CLOCKWISE,
                avgAngleDeg + 2,
                avgAngleDeg - 2
            );
        }

        // --- 5. STEP FOUR: DRAW THE MAX SPEED INDICATOR ---
        if (mMaxSpeed > 0.0 and mShowSpeedIndicators) {
            var maxAngleDeg = gaugeStart - (maxRatio * gaugeSweep);
            dc.setColor(COLOR_MAX_INDICATOR, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(layout[:trackWidth] + 4);
            
            dc.drawArc(
                centerX,
                centerY,
                radius,
                Graphics.ARC_CLOCKWISE,
                maxAngleDeg + 2,
                maxAngleDeg - 2
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
            centerY + speedYOffset,
            mDeviceProfile[:speedFont],
            mSpeed.format("%.1f"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
        dc.setColor(mLabelsColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            centerX,
            centerY + radius * 0.3 + unitLabelYOffset,
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
        var elapsedStr = elapsedString();

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
            cadenceString(),
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

        var heartRate = mHeartRate;
        var litSegs = litSegments(hrFillRatio(), segCount, heartRate != null);
        var hrZoneColor = zoneColor(
            heartRate != null ? heartRate : 0,
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
            heartRate != null ? heartRate.toString() : NO_VALUE,
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

        var litPwrSegs = litSegments(rightFillRatio(), segCount, false);
        var pwrZoneColor = rightZoneColor();

        dc.setPenWidth(barW);

        for (var i = 0; i < segCount; i++) {
            // Right side goes Counter-Clockwise (increases in angle)
            var pwrSegStart = pwrStartAngle + i * (segSweepDeg + gapDeg);
            var pwrSegEnd = pwrSegStart + segSweepDeg;

            dc.setColor(
                i < litPwrSegs ? pwrZoneColor : mTrackColor,
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
            rightValueString(),
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

    // What the right-hand gauge prints: watts with a meter attached, rpm
    // without, "--" when that sensor is not currently reporting.
    private function rightValueString() as String {
        var value = mHasPowerData ? mPower3s : mCadence;
        return value != null ? value.toString() : NO_VALUE;
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
        var bottomLabels = BOTTOM_LABELS;

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

        var topLabels = COMPACT_TOP_LABELS;
        var topValues = [
            tempString(),
            clockString(now),
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

        var maxVal = mSpeedGaugeMax;
        var gaugeStart = 210.0;
        var gaugeSweep = 240.0;

        var arcSegCount = 12;
        var segArcLen = gaugeSweep / arcSegCount;
        var segGapDeg = 3.5;
        
        // --- 1. VALUE CLAMPING ---
        var ratio = mSpeed / maxVal;
        if (ratio > 1.0) { ratio = 1.0; }
        if (ratio < 0.0) { ratio = 0.0; }
        var activeSweep = ratio * gaugeSweep;

        var avgRatio = mAvgSpeed / maxVal;
        if (avgRatio > 1.0) { avgRatio = 1.0; }
        if (avgRatio < 0.0) { avgRatio = 0.0; }

        var maxRatio = mMaxSpeed / maxVal;
        if (maxRatio > 1.0) { maxRatio = 1.0; }
        if (maxRatio < 0.0) { maxRatio = 0.0; }

        dc.setPenWidth(layout[:trackWidth]);

        // --- 2. STEP ONE: DRAW THE ENTIRE BACKGROUND TRACK (GREY) ---
        dc.setColor(mTrackColor, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < arcSegCount; i++) {
            var segStartDeg = gaugeStart - i * segArcLen;
            var segEndDeg = segStartDeg - segArcLen + segGapDeg;
            
            dc.drawArc(centerX, centerY, radius, Graphics.ARC_CLOCKWISE, segStartDeg, segEndDeg);
        }

        // --- 3. STEP TWO: OVERLAY THE ACTIVE SPEED (SMOOTH FILL) ---
        dc.setColor(COLOR_SPEED, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < arcSegCount; i++) {
            var segStartDeg = gaugeStart - i * segArcLen;
            var segEndDeg = segStartDeg - segArcLen + segGapDeg;
            
            var currentSegStartSweep = i * segArcLen;
            var currentSegEndSweep = (i + 1) * segArcLen - segGapDeg;

            if (activeSweep >= currentSegEndSweep) {
                // Speed completely covers this block -> Fill full segment
                dc.drawArc(centerX, centerY, radius, Graphics.ARC_CLOCKWISE, segStartDeg, segEndDeg);
            } 
            else if (activeSweep > currentSegStartSweep) {
                // Speed ends mid-segment -> Safely calculate partial fill
                var partialSweep = activeSweep - currentSegStartSweep;
                var smoothCutoffDeg = segStartDeg - partialSweep;

                // Protect against 0-degree / full-circle inversion error
                if ((segStartDeg - smoothCutoffDeg).abs() > 0.1) {
                    dc.drawArc(centerX, centerY, radius, Graphics.ARC_CLOCKWISE, segStartDeg, smoothCutoffDeg);
                }
                break; // No need to process remaining segments since speed is exhausted
            } 
            else {
                break; // Remaining segments are unreached
            }
        }

        // --- 4. STEP THREE: DRAW THE AVERAGE SPEED INDICATOR ---
        if (mAvgSpeed > 0.0 and mShowSpeedIndicators) {
            var avgAngleDeg = gaugeStart - (avgRatio * gaugeSweep);
            dc.setColor(COLOR_AVG_INDICATOR, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(layout[:trackWidth] + 4);
            
            dc.drawArc(
                centerX,
                centerY,
                radius,
                Graphics.ARC_CLOCKWISE,
                avgAngleDeg + 2,
                avgAngleDeg - 2
            );
        }

        // --- 5. STEP FOUR: DRAW THE MAX SPEED INDICATOR ---
        if (mMaxSpeed > 0.0 and mShowSpeedIndicators) {
            var maxAngleDeg = gaugeStart - (maxRatio * gaugeSweep);
            dc.setColor(COLOR_MAX_INDICATOR, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(layout[:trackWidth] + 4);
            
            dc.drawArc(
                centerX,
                centerY,
                radius,
                Graphics.ARC_CLOCKWISE,
                maxAngleDeg + 2,
                maxAngleDeg - 2
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
            centerY + radius * 0.38 - 10 + mDeviceProfile[:unitLabelYOffset],
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
        var heartRate = mHeartRate;
        var litHrSegs = litSegments(hrFillRatio(), 10, heartRate != null);
        var hrZoneColor = zoneColor(
            heartRate != null ? heartRate : 0,
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
            heartRate != null ? heartRate.toString() : NO_VALUE,
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
        var litPwrSegs = litSegments(rightFillRatio(), 10, false);
        var pwrZoneColor = rightZoneColor();

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
            rightValueString(),
            Graphics.TEXT_JUSTIFY_LEFT
        );

        // Mirror of the HR bar: segment 0 sits nearest the centre and the fill
        // runs out towards the right screen edge. Slot 9 lands exactly on rX1.
        for (var i = 0; i < 10; i++) {
            dc.setColor(
                i < litPwrSegs ? pwrZoneColor : mTrackColor,
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

        var values = [
            elapsedString(),
            mHasPowerData ? cadenceString() : mAscent.format("%.0f"),
            mGrade.format("%.1f"),
            (mDistance / 1000).format("%.1f"),
        ];
        var labels = [
            "TIME",
            mHasPowerData ? "CAD" : "ASC",
            "GRD",
            "DIST",
        ];
        var columns = COMPACT_FOOTER_COLUMNS;

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
