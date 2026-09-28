import Toybox.Graphics;
import Toybox.Lang;

// The device-tuned pixel offsets and font choices that computeLayout and the
// band draw functions add to their coordinates. Split out of DashView so the
// ~300-line table is not sitting in the middle of the render code.
module DeviceProfiles {
    // Returns a Dictionary of device-specific layout and font values keyed by screen size.
    // To add support for a new device, add a new profile block below.
    //
    // Branch order is load-bearing — see the device targeting section of
    // CLAUDE.md. A width test placed ahead of a deviceType test will swallow it.
    //
    // Which keys a profile must carry depends on its :layoutVariant. A :full
    // profile carries all of them; a :compact profile carries only the nine
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
    //                            lower). Still not a simple translation, but the strengths
    //                            are now the ones you would expect: the arc centre and
    //                            everything drawn around it move +1x, and the
    //                            cadence/gear/grade row moves -1x, because that row is
    //                            measured up from the gauge and the gauge going down pulls
    //                            it up. It used to move the central speed digits +2x —
    //                            computeFullLayout bakes the offset into centerY and
    //                            drawSpeedGauge added it a second time — which left every
    //                            profile's digits 2x its offset off the arc centre as a
    //                            side effect. drawSpeedGauge no longer re-adds it; the
    //                            per-profile :speedYOffset values absorbed the difference,
    //                            so the rendering is unchanged. The HR/power gauge is not
    //                            read from this key but still shifts +0.5x — see
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
    //   :speedYOffset          (Number) — vertical shift for the central speed digits alone,
    //                            measured from the arc centre. [compact]
    //   :unitLabelYOffset      (Number) — vertical shift for the KMH / MPH label under the
    //                            speed digits. Split out from :speedYOffset when the double
    //                            add above was removed: the two used to share a key, so the
    //                            digits could not be nudged without dragging the label. [compact]
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
    //   :panelTextYOffset      (Number) — vertical shift for panel values and avg text
    //                            (negative = up), arc unaffected. Move it together with
    //                            :panelTopLabelYOffset: the HR / PWR label is positioned
    //                            from the arc centre and this key is not applied to it, so
    //                            changing one alone opens or closes the label-to-value gap
    //                            instead of translating the group.
    //   :panelTopLabelYOffset  (Number) — vertical shift for the HR / PWR top labels (negative = up)
    //   :hideClockLabel        (Boolean) — suppress the CLOCK label in the top bar
    //   :unitLabelFont         (Graphics.FontType) — font for km/h, HR, and CAD/PWR labels [compact]
    //   :avgLabelOffset        (Number) — vertical shift for AVG/MAX and panel AVG labels and values (negative = up)
    //   :speedAvgValueOffset   (Number) — extra vertical shift for the AVG/MAX speed values
    //                            only, relative to their AVG/MAX labels. Use to open up the
    //                            label-to-value gap when a smaller gauge radius closes it.
    //   :panelAvgValueOffset   (Number) — vertical shift for avg HR and avg power/cadence values (negative = up)
    //   :panelArcSweep         (Float)  — total sweep angle in degrees for HR and power arc gauges
    function forDevice(
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
                :unitLabelYOffset => 6,
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
                :panelTextYOffset => -10,
                :panelTopLabelYOffset => -10,
            };
        }

        // --- Edge 1050: 480 x 800 ---
        if (screenWidth >= 400) {
            return {
                :layoutVariant => :full,
                :speedGaugeCenterYOffset => -5,
                :speedYOffset => -5,
                :unitLabelYOffset => 0,
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
                :speedYOffset => 1,
                :unitLabelYOffset => -4,
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
                :unitLabelYOffset => 0,
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
                :unitLabelYOffset => 0,
            };
        }

        // --- Edge 1030 / 1030 Plus: labels sit higher than on 1040 ---
        if (deviceType.equals("edge1030")) {
            return {
                :layoutVariant => :full,
                :speedGaugeCenterYOffset => 5,
                :speedYOffset => 5,
                :unitLabelYOffset => 0,
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
            :speedYOffset => -9,
            :unitLabelYOffset => -14,
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
}
