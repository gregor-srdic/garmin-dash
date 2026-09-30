# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Dash is a Garmin Connect IQ **data field** (not a widget/app) for Edge cycling computers, written in Monkey C. It renders a full-screen ride dashboard: speed gauge, HR/power arc gauges, and stat rows. Target products are declared in `manifest.xml`: edge1030, edge1030bontrager, edge1030plus, edge1040, edge1050, edge530, edge540, edge550, edge830, edge840, edge850, edgeexplore2. `minApiLevel` is 3.2.0.

Three of those twelve are button-only siblings that are pixel-identical to a touch model — same resolution, ppi, memory and font point sizes — and share its profile outright: **530 ≡ 830, 540 ≡ 840, 550 ≡ 850**. A data field takes no input, so buttons vs touch changes nothing here. Tune a parent and the sibling follows. Note this pairs *across* the 246×322 pair, not within it: the 830 and 840 share a panel but not font metrics, so they take separate profiles while each carries its sibling along.

## Build & run

There is no test suite, linter, or package manager — verification means "it compiles and looks right in the simulator". The project builds clean at type-check level 2 (`-l 2`, "informative"), which `.vscode/settings.json` pins via `monkeyC.typeCheckLevel`; keep it there, and pass `-l 2` on the CLI. `monkey.jungle` sets `base.sourcePath = source` — without it the source scan also picks up the copies the extension leaves in `bin/optimized/`, and every CLI build fails with `Redefinition of '$.DashApp'` once an IDE build has run.

Primary workflow is the VS Code Monkey C extension:
- `Monkey C: Build for Device`
- `Monkey C: Run` / F5 (uses the `Run Optimized` config in `.vscode/launch.json`, which prompts for the target device)
- `Monkey C: Install to Device`

CLI equivalent (SDK lives under `%APPDATA%\Garmin\ConnectIQ\Sdks\<version>\bin`; the active SDK path is in `%APPDATA%\Garmin\ConnectIQ\current-sdk.cfg`):

```powershell
$sdk = (Get-Content "$env:APPDATA\Garmin\ConnectIQ\current-sdk.cfg").Trim()
& "$sdk\bin\monkeyc.bat" -f monkey.jungle -o bin/Dash.prg -y "$env:APPDATA\Garmin\ConnectIQ\developer_key.der" -d edge1050 -l 2
& "$sdk\bin\connectiq.bat"          # start simulator, then:
& "$sdk\bin\monkeydo.bat" bin/Dash.prg edge1050
```

Always build against **more than one device** after touching layout code — the layout is device-tuned (see below) and a change that looks right on the 1050 routinely breaks the 1030.

## Architecture

Four source files, but the interesting behavior is cross-file.

### Rendering: `DashView.mc`

`DashView extends WatchUi.DataField`. `compute(info)` reads and unit-converts every metric into `m*` member fields; `onUpdate(dc)` draws the entire screen imperatively from those fields. There is no layout XML — `setLayout()` is never called, and `resources/layouts/` was deleted along with the `Background` drawable that shadowed `Toybox.Background`. Do not add UI by adding layouts; add it to the band draw functions below.

Metrics that can drop out mid-ride — heart rate, power, cadence, temperature — are **nullable** fields, and the draw path prints `NO_VALUE` (`"--"`) for them. This is load-bearing: they used to be plain numbers that were only ever assigned when a reading arrived, so a power meter disconnecting left its last watt number frozen on screen, reading as live data. Cumulative stats (averages, maxima, totals, distance) are non-nullable and keep their last value by definition. Each such metric gets one formatter (`tempString`, `cadenceString`, `rightValueString`) so both render paths print the same thing when a sensor is quiet.

`onUpdate` itself only sets the palette, resolves the layout and calls the band functions for the layout's variant in z-order — `:full` calls `drawTopBar` → `drawSpeedGauge` → `drawMiddleRow` → `drawPanels` → `drawFooter`, `:compact` calls `drawCompactTopBar` → `drawCompactSpeedGauge` → `drawCompactBars` → `drawCompactFooter`. None of them derives its own geometry — every position comes from the Dictionary returned by `computeLayout(dc)`, whose keys are documented above `computeFullLayout`. That Dictionary is cached in `mLayoutCache` and only recomputed when the dc dimensions change, so it may not read anything that varies per frame. Colors do vary per frame (the dark/light setting is live) and live in the `mBgColor` / `mValuesColor` / `mLabelsColor` / `mTrackColor` fields, reset at the top of `onUpdate`.

`computeLayout` dispatches on the profile's `:layoutVariant`, and the two variants are built on opposite principles:

- `:full` (1030 / 1040 / 1050 / 850 / Explore 2) positions bands with ~20 hand-tuned pixel offsets from the device profile.
- `:compact` (840 / 830) derives every band from `dc.getFontHeight()` at runtime and carries only eight profile keys. It has to: the two devices sharing 246×322 do **not** share font metrics — `FONT_LARGE` is 41 px on the 830 against 31 px on the 840, while their number fonts match within 1 px — so any absolute offset tuned on one is wrong on the other. Lay bands out from the screen edges inward and let the speed gauge absorb the slack. The one exception is `:crownYOffset`, a pixel nudge for the AVG/MAX pair, and it is only safe because the two devices now take separate profiles — do not add pixel offsets that a single profile would apply to both.

  That font-metric gap is also why `:compact` needs **two** profiles rather than one. They differ in two keys, `:rowValueFont` (top bar and footer values) and `:crownValueFont` (the AVG/MAX speed pair): the 840/540 take `FONT_LARGE` at 31 px, the 830/530 `FONT_MEDIUM` at 26 px, both landing in the same 20-30 px range on screen. The crown pair is sized separately from the rows because it is bounded by the arc rather than by the screen edge — `computeCompactLayout` derives `:speedAvgColOffset` from the measured width of a two-digit speed, pulling the two columns in from the `0.35 × radius` the design started at until the value box clears the arc's inner edge by 2 px. On the 830/530 that cap still binds and the geometry is untouched; on the 840/540 the columns come in ~1.5 px. A three-digit speed is wider than half the crown at that height on the 840 and will clip the arc — sizing for it would push AVG and MAX into each other instead. `:crownYOffset` then drops the pair 6 px on the 840/540; that also lands it in a wider part of the crown, which lets the offset return to the `0.35` cap. It is at its limit — the AVG/MAX digits end 1 px above the speed digits. Note the `FONT_NUMBER_*` faces carry no leading (box height is exactly ascent + descent, checked with `Graphics.getFontAscent`), so text-box arithmetic against them is glyph arithmetic, with none of the usual slack to absorb an overlap. Everything else is identical and the layout measures whatever it is given. `FONT_LARGE` is the top of the range — the `FONT_NUMBER_*` faces carry no `°`, `:` or `/`, and neither device reports `Graphics has :getVectorFont` — so on the 840 it is a deliberate overrun: typical values clear, but a sub-zero temperature, a five-digit elevation in feet, a 10-hour elapsed time or a 3-digit distance beside a steep negative grade collide with their neighbours by 5-9 px. The measured worst cases are tabulated above `drawCompactTopBar` and `drawCompactFooter`.

The two paths share no draw code. `:compact` drops the metrics it has no room for (AVG HR, AVG power, calories) rather than shrinking them, and draws the HR/power zone bars as horizontal `fillRectangle` runs instead of arcs. It issues 12 `drawArc` calls per frame against `:full`'s 44, which matters on the 830 (2019 hardware).

The metric-to-gauge arithmetic — `hrFillRatio`, `rightFillRatio`, `clampRatio`, `litSegments`, `rightZoneColor` — is shared by both render paths. The two paths share no *geometry* on purpose, but a heart rate has to mean the same fill on an arc as on a bar, so that arithmetic lives in one place.

### Device targeting: two mechanisms, order-sensitive

`DeviceProfiles.forDevice(screenWidth, screenHeight, deviceType)`, in `DeviceProfiles.mc`, returns a Dictionary of ~20 pixel offsets and font choices that `computeLayout` and the band draw functions add to their coordinates. The key list and meaning of each key is documented in the comment block directly above the function — keep it in sync when adding keys.

Selection uses both screen dimensions *and* a `deviceType` string:
- `resources/strings/strings.xml` defines `deviceType` = `default`; each `resources-<productId>/` directory overrides it (Connect IQ picks these up by directory-name convention — they are not listed in `monkey.jungle`). Note both 1030 variants and the 1030 Plus all map to `deviceType` = `edge1030`.
- Branch order in `DeviceProfiles.forDevice` matters: `deviceType == "edge850"`/`"edge550"` → `screenWidth >= 400` (1050) → `deviceType == "edgeexplore2"` → `deviceType == "edge840"`/`"edge540"` → `deviceType == "edge830"`/`"edge530"` or `screenWidth < 260` (the two `:compact` branches; the width test is now only a safety net for non-target sub-260 devices, and sits on the 830 branch because that is the more conservative font choice) → `deviceType == "edge1030"` → fallback (1040). A width check placed before a deviceType check will swallow it — the 850 and 550 are 420 wide and must be tested before the `>= 400` branch.
- **The 550 is the cautionary case.** 246×322 devices are caught by the `screenWidth < 260` net even on `deviceType` = `default`, so they tolerate a missing resource dir. A 420×600 device does not: without `resources-edge550/`, a 550 falls into `screenWidth >= 400`, takes the **1050** profile, and renders a layout that overflows by ~160 px — while still compiling and drawing, so it looks like it works. Any future 420×600 target needs its `deviceType` wired into the 850 branch.
- Verifying which branch a device actually takes cannot be done statically: `Rez.mcgen` carries only resource ids, and every `.prg` embeds all the `deviceType` literals regardless of target because they are the `.equals()` operands in `DeviceProfiles.forDevice`. Print the resolved profile from `initialize()` and run it under `monkeydo`. `:gaugeRadiusFactor` is the cheapest discriminator — **0.275** means the 850/550 branch, 0.33 the 1050/1040 branches, 0.40 either `:compact` branch. (It was 0.25 when that procedure was written; read the value out of the profile rather than matching a remembered literal.) To tell the two `:compact` branches apart use `:rowValueFont` / `:crownValueFont` instead (`FONT_LARGE` = 840/540, `FONT_MEDIUM` = 830/530).

Two pairs of keys have to move together. `:speedYOffset` shifts the central speed digits and `:unitLabelYOffset` the KMH/MPH label under them; they were one key until `drawSpeedGauge` stopped re-adding `:speedGaugeCenterYOffset` on top of the centre `computeFullLayout` had already baked it into (which moved the digits at 2x and left every profile's digits offset from the arc centre as a side effect). `:panelTextYOffset` moves the panel values and AVG rows but **not** the HR/PWR label above them, which takes `:panelTopLabelYOffset` — change one alone and you resize the label-to-value gap instead of translating the group.

Two profile keys carry the `:full` layout across aspect ratios: `:gaugeRadiusFactor` (speed gauge radius as a fraction of screen width) and `:rowValueFont` (the font for top bar, elapsed time, cadence row and footer values). Every 1.67-aspect device uses `0.33` / `FONT_LARGE`; the 850 at 1.43 needs `FONT_MEDIUM` and a reduced radius — `0.25` is what the recovery was tuned at, `0.275` is what it ships at. Opening it up cost the panel band 16 px, which pushed the panel AVG row into the footer; the 850/550 profile pays that back with `:panelTextYOffset`/`:panelTopLabelYOffset` at -10, bringing it into line with every other `:full` profile. Everything below the gauge keys off the radius, and the footer is anchored to the bottom, so the panel band is what pays for a larger gauge: on the 850 each 0.025 of factor moves the middle row down ~21 px and the panel top down ~16 px, taking that 16 px straight out of `:panelH`. The layout is designed to *exactly* fill a 1.67-aspect screen — on the 1050 the shipped design already has ~4px of text-box overlap — so a shorter screen has no slack and needs both keys reduced, not just offsets nudged. Below roughly 1.4 this stops working at any font size and the device belongs on `:compact`, where `:gaugeRadiusFactor` becomes an upper bound the layout shrinks past if the band cannot take it.

To add a device: add the `<iq:product>` to `manifest.xml`, add `resources-<productId>/strings/strings.xml` with a `deviceType`, and add a profile branch in `DeviceProfiles.mc` — inserted at the right position in that chain.

Font heights are **not** derivable from ppi or from the SDK's `simulator.json` point sizes, and devices with identical resolution and ppi do not necessarily share them. Measure them: build a `(:debug)` `System.println` of `dc.getFontHeight()` / `dc.getTextWidthInPixels()` for the fonts and worst-case strings you plan to use, then `monkeydo` it and read the console. Known values:

| Font | 830 | 840 | 1040 | Explore 2 | 1050 / 850 |
|---|---|---|---|---|---|
| xtiny | 13 | 11 | 13 | 12 | 21 |
| tiny | 20 | 14 | 17 | 16 | 28 |
| small | 22 | 17 | 19 | 19 | 33 |
| medium | 26 | 19 | 22 | 22 | 38 |
| large | 41 | 31 | 36 | 36 | 61 |
| numberMild | 36 | 35 | 42 | 41 | 71 |
| numberMedium | 42 | 42 | 48 | 48 | 82 |
| numberHot | 56 | 55 | 64 | 64 | 109 |
| numberThaiHot | 70 | 67 | 80 | 81 | 136 |

### Temperature: spans all four files

Edge devices vary in whether ambient temperature is exposed to a data field, so there is a fallback chain in `compute()`: the background service's last reading → `info.ambientTemperature` → `SensorHistory.getTemperatureHistory()`. If all three are empty the field shows `"--"` rather than a stale number.

The background reading lives in `mBackgroundTemp`, seeded from `Storage` once in `initialize()` and pushed in afterwards by `DashApp.onBackgroundData` → `DashView.onSensorTemperature`. `compute()` does **not** read `Storage` — that was a flash-backed read every second for a value that changes every five minutes. Once `info.ambientTemperature` returns a real reading the device has proved it reports temperature directly, so `compute()` cancels the temporal event outright; `DashApp` re-registers on the next load if it turns out to be needed.

The reading is produced by a background service: `DashApp.getInitialView()` registers a 5-minute temporal event **only when none is registered** (re-registering restarts the five-minute window, so a field that reloads often never reaches its first event), `GlobalBackgroundService.onTemporalEvent()` (must carry the `(:background)` annotation) reads the sensor and calls `Background.exit(temp)`, and `DashApp.onBackgroundData()` persists it to `Storage` and hands it to the view. `onTemporalEvent` only works on the `ServiceDelegate`; a copy on a `WatchUi.Drawable` is never called, which is the dead end `DashBackground.mc` used to record before it was deleted.

### API-level guards

Because the app targets devices from CIQ 3.2 to 5.x, optional APIs must be probed with `has` before use — **a missing symbol is a fatal runtime error, not a catchable exception**, so `try/catch` alone is not sufficient. See the `UserProfile has :getFunctionalThresholdPower` guard in `initialize()` (that API is 5.2.2+, i.e. 1040/1050 only). The same pattern appears for `info has :ambientTemperature`, `actInfo has :rearDerailleurIndex`, `Toybox has :SensorHistory`, and `System has :ServiceDelegate`.

### Zones and gauges

`zoneColor(value, boundaries, fallback)` maps a value onto the 5-entry `ZONE_COLORS` table given a 6-element boundary array. HR boundaries come from `UserProfile.getHeartRateZones()`; power boundaries are Coggan multiples derived from FTP (profile FTP first, then the `ftp` app property, default 200 W — declared in `resources/properties/properties.xml` and exposed via `resources/settings/settings.xml`). If boundaries are unavailable the gauge falls back to a single flat color.

`mFtp` is **guaranteed positive**: it is the divisor for the power gauge's full-scale value, and `readSettings()` falls back to `FTP_DEFAULT` for anything null, non-numeric or `<= 0`. The setting's `min` is 50 for the same reason — it used to allow 0, which divided by zero at ride start, before any max power had been recorded to take over as the scale.

The speed gauge's full scale comes from the `speedGaugeMax` property, in display units; 0 means the built-in default (60 km/h / 40 mph).

The right panel is dual-purpose: with no power data (`mHasPowerData == false`) it silently becomes a 0–150 rpm cadence gauge, label and all.

### Grade

`calculateGrade()` keeps a distance/altitude anchor in **raw metres**, deliberately independent of the display-unit conversions applied to everything else. It updates only after 20 m of travel, clamps to ±30%, and EMA-blends 50/50. The anchor can strand itself (activity restart, distance running backwards, inputs dropping out), so there are three recovery paths — `onTimerReset()`, the negative-`distDiff` re-seed, and the `GRADE_STALL_LIMIT` counter in `ageGradeWindow()`. All three exist because of real bugs; don't remove one as redundant.

## Conventions

- Metrics are unit-converted once in `compute()` and stored ready-to-display; `onUpdate` does no conversion. `mIsMetric` (speed/distance) and `mIsElevationMetric` (altitude/ascent) are separate device settings and are read independently, as is `settings.temperatureUnits` (`mIsTempStatute`).
- Anything read from device settings, the user profile or app properties is read in `readSettings()` and cached — never on the 1 Hz path. `DashApp.onSettingsChanged()` re-runs it, which is what makes an FTP edit take effect without recreating the field.
- `compute(info)` uses `info` for everything. It is the current `Activity.Info`, so the `Activity.getActivityInfo()` "fallbacks" this used to make on every tick returned the same object and could never differ; the `has` guards sit on `info` instead.
- Constant label rows (`TOP_LABELS`, `BOTTOM_LABELS`, `COMPACT_TOP_LABELS`, `COMPACT_FOOTER_COLUMNS`) are class constants, not Arrays rebuilt per draw call.
- `manifest.xml` declares only the permissions the code uses: `Background`, `Sensor`, `SensorHistory`, `UserProfile`. Do not re-add `Ant`/`BluetoothLowEnergy`/`DataFieldAlert`/`PersistedContent`/`Positioning` — none of them is used, and they show on the store listing.
- Dark/light is driven by `getBackgroundColor()`; colors are chosen at the top of `onUpdate` from the `isDark` flag rather than hardcoded per draw call.
- Never commit `developer_key`/`*.der`/`*.pem`, `bin/`, or `*.prg` — already covered by `.gitignore`.
