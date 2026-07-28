# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Dash is a Garmin Connect IQ **data field** (not a widget/app) for Edge cycling computers, written in Monkey C. It renders a full-screen ride dashboard: speed gauge, HR/power arc gauges, and stat rows. Target products are declared in `manifest.xml`: edge1030, edge1030bontrager, edge1030plus, edge1040, edge1050, edge850, edgeexplore2. `minApiLevel` is 3.2.0.

## Build & run

There is no test suite, linter, or package manager — verification means "it compiles and looks right in the simulator".

Primary workflow is the VS Code Monkey C extension:
- `Monkey C: Build for Device`
- `Monkey C: Run` / F5 (uses the `Run Optimized` config in `.vscode/launch.json`, which prompts for the target device)
- `Monkey C: Install to Device`

CLI equivalent (SDK lives under `%APPDATA%\Garmin\ConnectIQ\Sdks\<version>\bin`; the active SDK path is in `%APPDATA%\Garmin\ConnectIQ\current-sdk.cfg`):

```powershell
$sdk = (Get-Content "$env:APPDATA\Garmin\ConnectIQ\current-sdk.cfg").Trim()
& "$sdk\bin\monkeyc.bat" -f monkey.jungle -o bin/Dash.prg -y "$env:APPDATA\Garmin\ConnectIQ\developer_key.der" -d edge1050
& "$sdk\bin\connectiq.bat"          # start simulator, then:
& "$sdk\bin\monkeydo.bat" bin/Dash.prg edge1050
```

Always build against **more than one device** after touching layout code — the layout is device-tuned (see below) and a change that looks right on the 1050 routinely breaks the 1030.

## Architecture

Four source files, but the interesting behavior is cross-file.

### Rendering: `DashView.mc`

`DashView extends WatchUi.DataField`. `compute(info)` reads and unit-converts every metric into `m*` member fields; `onUpdate(dc)` draws the entire screen imperatively from those fields. **`resources/layouts/layouts.xml` is vestigial** — `setLayout()` is never called and nothing in it is used except the `Background` drawable class. Do not add UI by editing layouts; add it to `onUpdate`.

`DashBackground.mc` defines `class Background extends WatchUi.Drawable`, which shadows `Toybox.Background`. That is why files needing the real background API write `using Toybox.Background` and call it fully qualified.

### Device targeting: two mechanisms, order-sensitive

`initDeviceProfile(screenWidth, screenHeight, deviceType)` returns a Dictionary of ~20 pixel offsets and font choices that every draw call in `onUpdate` adds to its coordinates. The key list and meaning of each key is documented in the comment block directly above the function — keep it in sync when adding keys.

Selection uses both screen dimensions *and* a `deviceType` string:
- `resources/strings/strings.xml` defines `deviceType` = `default`; each `resources-<productId>/` directory overrides it (Connect IQ picks these up by directory-name convention — they are not listed in `monkey.jungle`). Note both 1030 variants and the 1030 Plus all map to `deviceType` = `edge1030`.
- Branch order in `initDeviceProfile` matters: `deviceType == "edge850"` → `screenWidth >= 400` (1050) → `deviceType == "edgeexplore2"` → `screenWidth < 260` (840/540, not currently a build target) → `deviceType == "edge1030"` → fallback (1040). A width check placed before a deviceType check will swallow it — the 850 is 420 wide and must be tested before the `>= 400` branch.

Two profile keys carry the layout across aspect ratios: `:gaugeRadiusFactor` (speed gauge radius as a fraction of screen width) and `:rowValueFont` (the font for top bar, elapsed time, cadence row and footer values). Every 1.67-aspect device uses `0.33` / `FONT_LARGE`; the 850 at 1.43 needs `0.25` / `FONT_MEDIUM`. The layout is designed to *exactly* fill a 1.67-aspect screen — on the 1050 the shipped design already has ~4px of text-box overlap — so a shorter screen has no slack and needs both keys reduced, not just offsets nudged.

To add a device: add the `<iq:product>` to `manifest.xml`, add `resources-<productId>/strings/strings.xml` with a `deviceType`, and add a profile branch — inserted at the right position in that chain.

### Temperature: spans all four files

Edge devices vary in whether ambient temperature is exposed to a data field, so there is a fallback chain in `compute()`: `Storage["sensorTemperature"]` → `info.ambientTemperature` → `Activity.getActivityInfo().ambientTemperature` → `SensorHistory.getTemperatureHistory()`.

The `Storage` entry is populated by a background service: `DashApp.getInitialView()` registers a 5-minute temporal event, `GlobalBackgroundService.onTemporalEvent()` (must carry the `(:background)` annotation) reads the sensor and calls `Background.exit(temp)`, and `DashApp.onBackgroundData()` writes it to `Storage`. `onTemporalEvent` only works on the `ServiceDelegate` — the commented-out copy in `DashBackground.mc` is a record of that dead end.

### API-level guards

Because the app targets devices from CIQ 3.2 to 5.x, optional APIs must be probed with `has` before use — **a missing symbol is a fatal runtime error, not a catchable exception**, so `try/catch` alone is not sufficient. See the `UserProfile has :getFunctionalThresholdPower` guard in `initialize()` (that API is 5.2.2+, i.e. 1040/1050 only). The same pattern appears for `info has :ambientTemperature`, `actInfo has :rearDerailleurIndex`, `Toybox has :SensorHistory`, and `System has :ServiceDelegate`.

### Zones and gauges

`zoneColor(value, boundaries, fallback)` maps a value onto the 5-entry `ZONE_COLORS` table given a 6-element boundary array. HR boundaries come from `UserProfile.getHeartRateZones()`; power boundaries are Coggan multiples derived from FTP (profile FTP first, then the `ftp` app property, default 200 W — declared in `resources/properties/properties.xml` and exposed via `resources/settings/settings.xml`). If boundaries are unavailable the gauge falls back to a single flat color.

The right panel is dual-purpose: with no power data (`mHasPowerData == false`) it silently becomes a 0–150 rpm cadence gauge, label and all.

### Grade

`calculateGrade()` keeps a distance/altitude anchor in **raw metres**, deliberately independent of the display-unit conversions applied to everything else. It updates only after 20 m of travel, clamps to ±30%, and EMA-blends 50/50. The anchor can strand itself (activity restart, distance running backwards, inputs dropping out), so there are three recovery paths — `onTimerReset()`, the negative-`distDiff` re-seed, and the `GRADE_STALL_LIMIT` counter in `ageGradeWindow()`. All three exist because of real bugs; don't remove one as redundant.

## Conventions

- Metrics are unit-converted once in `compute()` and stored ready-to-display; `onUpdate` does no conversion. `mIsMetric` (speed/distance) and `mIsElevationMetric` (altitude/ascent) are separate device settings and are read independently, as is `settings.temperatureUnits`.
- Dark/light is driven by `getBackgroundColor()`; colors are chosen at the top of `onUpdate` from the `isDark` flag rather than hardcoded per draw call.
- Never commit `developer_key`/`*.der`/`*.pem`, `bin/`, or `*.prg` — already covered by `.gitignore`.
