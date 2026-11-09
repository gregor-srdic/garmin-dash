# Plan: selectable metric for the main gauge

Status: **accepted 2026-11-09**, amended A1 (A2 and A3 are spec-only; see Implementation notes)
Intent: [intent.md](intent.md) (accepted 2026-11-09). Spec: [spec.md](spec.md) (signed off 2026-11-09).

Requirement and concern numbers (R1-R4, concern 1-7) refer to `spec.md`. Line numbers refer to `source/DashView.mc` at commit `6ab6687`. They will drift as soon as step 4 starts, so match on the function name, not the number.

## Files that change

| File | Change |
|---|---|
| `resources/properties/properties.xml` | + `mainGauge` property |
| `resources/settings/settings.xml` | + list setting for it |
| `resources/strings/strings.xml` | + 4 strings |
| `source/DashView.mc` | metric helpers; main-gauge and small-gauge draws parameterised by metric; 2 new fields |
| `readme.md` | "What's on screen" + new setting |
| `CLAUDE.md` | rename references; right panel no longer fixed to PWR/CAD |
| `docs/changes/2026-11-09-main-gauge-metric/plan.md` | updated if the implementation departs from this plan |

`DeviceProfiles.mc`, `DashApp.mc`, `GlobalBackgroundService.mc` and `manifest.xml` do **not** change. No new profile keys and no new permissions.

## Order of work

### 0. Branch

`git switch -c feat/main-gauge-metric` from `main`. Never commit to `main`.

### 1. Baseline build (before any source change)

The pixel-identical check (spec R2, verification 2) needs a reference rendered from the *same* data. The simulator's "Simulate Data" is random, so pin the data with a fixture:

- `git worktree add ../Dash-baseline main`.
- In **both** trees, add the same temporary fixture: a `(:debug) private function applyFixture() as Void` that overwrites every `m*` metric field with fixed values, called as the last statement of `compute()`. Values: speed 34.6, avg 27.3, max 52.8, HR 152 (avg 138), power 245 (avg 198, max 812), cadence 88 (avg 84), `mHasPowerData` true, temp 18.5, grade 4.2, elevation 412, ascent 860, distance 48 230, elapsed 1 h 42 m 10 s, calories 1 240, gear "2:7". In the feature tree it also sets `mMaxHeartRate` 176 and `mMaxCadence` 112. A second variant sets `mHasPowerData` false and `mPower` null, for the no-power screenshots.
- **The fixture is never committed.** Keep it as `<scratchpad>/fixture.patch`, apply it with `git apply`, and remove it with `git apply -R` before step 9.
- Build the baseline `.prg` for each of the 7 profiles (edge1050, edge1040, edge1030, edge850, edgeexplore2, edge840, edge830) into `<scratchpad>/baseline/`.

### 2. Resources (R1)

- `properties.xml`: `<property id="mainGauge" type="number">0</property>`, with a comment that the values 0/1/2 are also the `METRIC_*` ids.
- `settings.xml`: a list setting placed after `powerAveraging`, with entries `0` → `@Strings.mainGaugeSpeed`, `1` → `@Strings.mainGaugePower`, `2` → `@Strings.mainGaugeHr`.
- `strings.xml`: `mainGaugeTitle` = "Main Gauge", `mainGaugeSpeed` = "Speed", `mainGaugePower` = "Power (Cadence)", `mainGaugeHr` = "Heart Rate".

### 3. Data (R1, R4)

In `DashView.mc`:
- Constants `METRIC_SPEED = 0`, `METRIC_RIGHT = 1`, `METRIC_HR = 2`.
- Fields `mMainGauge as Number = METRIC_SPEED`, `mMaxHeartRate as Number = 0`, `mMaxCadence as Number = 0`.
- `readSettings()`: read `mainGauge`. If it is not a `Lang.Number` in `0..2`, use `METRIC_SPEED`.
- `compute()`: `if (info.maxHeartRate != null) { mMaxHeartRate = info.maxHeartRate; }`, and the same for `maxCadence`, next to the existing avg reads.

### 4. Metric helpers (spec "Design")

Put these where `hrFillRatio` … `rightZoneColor` live now (around l.263-345), replacing them:

- `leftMetric()`: `METRIC_SPEED` if `mMainGauge == METRIC_HR`, else `METRIC_HR`.
- `rightMetric()`: `METRIC_SPEED` if `mMainGauge == METRIC_RIGHT`, else `METRIC_RIGHT`.
- `currentValue(m) as Numeric?`: speed → `mSpeed`; right → `mHasPowerData ? mPower : mCadence`; HR → `mHeartRate`.
- `avgValue(m) as Numeric`: `mAvgSpeed`, power/cadence avg (by `mHasPowerData`), `mAvgHeartRate`.
- `maxValue(m) as Numeric`: `mMaxSpeed`, `mMaxPower` / `mMaxCadence`, `mMaxHeartRate`.
- `metricRatio(m, value as Numeric?) as Float`: null → 0.0. Speed: `value / mSpeedGaugeMax`. Right: the body of today's `rightFillRatio` applied to `value`. HR: the body of today's `hrFillRatio` applied to `value`. Everything goes through `clampRatio`.
- `metricColor(m) as Number`: speed → `COLOR_SPEED`; right → today's `rightZoneColor()` body; HR → `zoneColor(hr ?: 0, mHrZoneBoundaries, COLOR_HR)`.
- `metricString(m, value as Numeric?) as String`: null → `NO_VALUE`; speed → `format("%.1f")`; otherwise `format("%d")`. This gives the same output as `toString()` for the Number values printed today.
- `avgString(m)` / `maxString(m)`: speed → `%.1f`, otherwise `%.0f` (today's avg format).
- `metricLabel(m)`: speed → `mIsMetric ? "KMH" : "MPH"`; right → `mHasPowerData ? "PWR" : "CAD"`; HR → `"HR"`.

Remove `hrFillRatio`, `rightFillRatio`, `rightZoneColor` and `rightValueString`. `cadenceString` stays, because the middle row and the compact footer use it.

### 5. Main gauge draws (R3)

- Rename `drawSpeedGauge` → `drawMainGauge` and `drawCompactSpeedGauge` → `drawCompactMainGauge`, and update the calls in `onUpdate`.
- In both, `var m = mMainGauge;` and then:
  - `ratio`/`avgRatio`/`maxRatio` = `metricRatio(m, currentValue(m) / avgValue(m) / maxValue(m))`. The three inline clamp blocks are deleted.
  - Fill colour `metricColor(m)` instead of `COLOR_SPEED`.
  - Marker guards `avgValue(m) > 0` / `maxValue(m) > 0` instead of `mAvgSpeed > 0.0` / `mMaxSpeed > 0.0`.
  - Crown values `avgString(m)` / `maxString(m)`, central readout `metricString(m, currentValue(m))`, and the unit label `metricLabel(m)`.
- Geometry, fonts, segment counts and the `drawArc` count do not change.

### 6. Small gauge draws (R3)

- `drawPanels` → a loop body extracted into `drawPanel(dc, layout, metric, isLeft)`. `drawPanels` calls it twice: `(leftMetric(), true)` and `(rightMetric(), false)`. Per side:
  - text X: `layout[:panelLeftX]` / `layout[:panelRightX]`
  - start angle: `180 + sweep/2` / `360 - sweep/2`
  - segment step: `-` / `+`
  - arc direction: `ARC_CLOCKWISE` / `ARC_COUNTER_CLOCKWISE`
  - the label, lit count `litSegments(metricRatio(...), segCount, m == METRIC_HR && currentValue(m) != null)`, colour `metricColor(m)`, value `metricString` and AVG `avgString`.

  The `segStart`/`segEnd` maths per side must match today's exactly. Copy it, do not re-derive it.
- `drawCompactBars` → `drawCompactBar(dc, layout, metric, isLeft)`. Per side:
  - label X/justify: `lX0` LEFT / `rX1` RIGHT
  - value X/justify: `lX1` RIGHT / `rX0` LEFT
  - segment x: `lX1 - segLen - i*(segLen+segGap)` / `rX0 + i*(segLen+segGap)`

  `labelY` and the shared layout reads stay in `drawCompactBars`, passed through or recomputed. Recomputing is cheap.
- Update the comments above both functions: the slots are now "left/right per `mMainGauge`".

### 7. Build gate

Build the feature tree **with** the fixture for all 7 profiles at `-l 2` into `<scratchpad>/feature/`. Zero warnings is the bar, the same as `main`.

### 8. Visual proof

1. **Mode 0 identity (R2).** For each profile: run the baseline `.prg` in the simulator, capture the device screen region, then do the same for the feature `.prg` with `mainGauge` = 0. Use the same window position and a dark background. Capture is a PowerShell `System.Drawing` `CopyFromScreen` of the simulator window, with the script in the scratchpad. Compare pixel-for-pixel, also in PowerShell. **The pass criterion is 0 differing pixels.** Repeat once in light mode on edge1050 and edge830.
2. **Modes 1 and 2.** Set `mainGauge` in the simulator (*File → Edit Persistent Storage → Edit Application.Properties data*). Screenshot each profile × {power fixture, no-power fixture} × {1, 2}. Check R2/R3 by eye: the swap, labels, zone colours, avg/max markers and crown values. Iterate on anything that is wrong.
3. **Widths (concerns 1-3).** Add a temporary `(:debug)` println in `computeLayout` of `getTextWidthInPixels` for:
   - `"88.8"` in `:panelValueFont` (`:full`) or `:barValueFont` (`:compact`), and in `FONT_MEDIUM`
   - `"1250"` in `:speedFont` and `:crownValueFont`
   - the available width: panel spacing on `:full`, and `barsLeftX1 - barsLeftX0` minus the `KMH` width on `:compact`

   Run it on all 7 profiles. If `"88.8"` does not fit in a small slot on any device, **stop and take it back to the spec for sign-off** (the `%d` fallback). Otherwise write the numbers for the accepted overruns into the comment above `drawMainGauge` / `drawCompactMainGauge`, the same way `drawCompactTopBar` does. Remove the println.
4. **Memory (concern 5).** Run edge830, mode 1, for a minute with *View → Memory* and record the peak. The limit is 131 072 B (see `docs/plan-edge-830-840-850.md`).

### 9. Clean up and document

- `git apply -R` the fixture, then rebuild all 7 profiles at `-l 2`. This is the final build output to show.
- `git worktree remove ../Dash-baseline`.
- `readme.md`: describe the Main Gauge setting under "What's on screen", in sections 2 and 4 and in the compact section.
- `CLAUDE.md`: in "Rendering", replace `drawSpeedGauge`/`drawCompactSpeedGauge` with the new names. In "Zones and gauges", replace `hrFillRatio`/`rightFillRatio`/`rightZoneColor`/`rightValueString` with the metric helpers, and add one line saying that slot assignment follows `mainGauge` (R2). Check that the file has not grown by more than a few lines.
- Update this plan wherever the work departed from it.

### 10. Commit

One commit on `feat/main-gauge-metric` (`feat(gauges): selectable main gauge metric`). **No push and no PR without explicit approval.**

## Risks

| What could break | Why | Caught by |
|---|---|---|
| Speed-mode rendering moves by a pixel | `drawPanel`/`drawCompactBar` extraction re-orders arithmetic or float/int mixing (e.g. `180.0 + sweep/2.0` vs integer division) | step 8.1, 0-pixel diff |
| HR in the left panel loses its "one segment when alive" floor | the floor flag moves into a per-metric expression | the 152 bpm fixture never reaches the floor, so step 8.1 adds one extra baseline/feature pair on edge1050 with HR = 40 (below every zone floor → 1 lit segment) |
| Type-check warnings at `-l 2` | `Numeric?` returns from if/else chains; `format` on `Numeric` | step 7 |
| Cadence → power label flip mid-ride looks like a glitch | existing latch (concern 7) now drives the big gauge | accepted in spec; no check |
| Small-slot speed does not fit | concern 2 | step 8.3, which stops on failure |
| The fixture leaks into a commit | forgotten `git apply -R` | step 9 rebuild + `git diff --stat` before commit shows no `applyFixture` |

**Riskiest step: 6.** It is the only step that rewrites code the default mode depends on. The other steps either add code or swap an expression for one that gives the same result. That is why step 1 exists and why the bar in step 8.1 is zero differing pixels rather than "looks the same".

## Alternatives rejected

- **A separate branch per metric inside each existing draw function.** This adds no refactor risk to mode 0, but it gives four draw functions with three branches each and copies the HR/PWR blocks again. That runs against the `CLAUDE.md` "metric arithmetic in one place" rule, and it means more code on the 830.
- **A per-frame Dictionary describing the slot (label, ratio, colour, strings).** It is the cleanest to read, but it allocates on every frame on the 1 Hz path. Plain helper calls cost nothing to allocate.
- **New profile keys for main-gauge fonts per metric.** The spec accepts the overruns instead, so there is nothing to tune, and every new key has to be added to all 7 profiles.
- **Eyeballing mode 0 instead of a pixel diff.** A 1 px shift in a panel arc is invisible on screen but still a regression. The fixture plus diff costs about 15 minutes.

## Implementation notes

Departures from the plan so far:

- The fixture also pins the clock (`FIXTURE_CLOCK`, "10:10"). The top-bar clock would otherwise make mode-0 screenshots differ by minute.
- The fixture is called from `onUpdate` right after the colour block, and a `FIXTURE_MAIN` constant selects the mode per build, instead of editing properties in the simulator.
- The work was split into tasks T1-T5 run by subagents (run dir `.agent-runs/main-gauge-metric`, gitignored).
- `.gitignore` gained `.agent-runs/`.
- `source/DeviceProfiles.mc`: the orchestrator edited two comment lines (`drawSpeedGauge` -> `drawMainGauge`), a departure from "DeviceProfiles.mc does not change". No keys changed.
- A2: the setting title is renamed to "Visualize average/max values" (`strings.xml` and `readme.md`, done by the orchestrator).
- A3: the current speed in a small slot prints without decimals (`slotString`, `%.0f`) after review round 1 found that T4's width measurement used the panel arc's pen centre instead of its inner edge ("88.8" was about -0.5 px on the 1050/1060). The width table above `drawMainGauge` is corrected and `readme.md` says whole numbers.
- T7 verification: 7 devices build at `-l 2` with no warnings; mode-0 identity vs baseline 0 differing pixels on 1050 and 830 with indicators off; modes 1 and 2 checked by eye on 6 devices; fixture removed, final build exit 0 (see the T7 result file).

## Amendment A1: AVG markers on the small gauges (spec R5, R6)

Added after T1-T5 were dispatched. This runs as task **T6**, after T4 has finished and reverted its fixture, because both T4 and T6 edit `source/DashView.mc`.

1. In `drawPanel`: after the 10 segments, if `mShowSpeedIndicators && avgValue(m) > 0`, draw the R5 arc marker in `mValuesColor`, pen `barW + 4`, `ARC_CLOCKWISE` from `angle + 2` to `angle - 2`. Restore `setPenWidth(barW)` is not needed after it, because nothing after it in the function draws arcs. Check this.
2. In `drawCompactBar`: after the 10 rectangles, the R5 rectangle in `mValuesColor`.
3. In `drawMainGauge` / `drawCompactMainGauge`: change the AVG marker colour to `mValuesColor`. `COLOR_AVG_INDICATOR` becomes unused, so remove it.
4. Fixture: add `FIXTURE_NO_INDICATORS` (forces `mShowSpeedIndicators = false` in `applyFixture`). Rebuild the **baseline** (main) mode-0 variants with it on, rebuild the feature mode-0 variants with it on, and pixel-diff them. Pass = 0 differing pixels.
5. Visual check with indicators on: modes 0, 1 and 2 on edge1050, edge1040, edge850, edgeexplore2, edge840 and edge830. On every small slot the marker must sit at the AVG value's position: HR 138 on the zone span; power 198 against max(FTP 200, 812) → 0.24; cadence 84/150; speed 27.3/60. It must be visible on both lit and unlit segments and in light mode.
6. Update `readme.md` / `CLAUDE.md` where they describe the markers (and the `drawArc` count, 44 → 46).

- T6 (A1): `drawPanel` / `drawCompactBar` draw the AVG marker; main AVG marker is `mValuesColor` and `COLOR_AVG_INDICATOR` is gone. Identity with indicators off: 9/9 pairs (dark x7, light 1050/830) 0 differing pixels; markers checked by eye on 6 devices x modes 0-2, light and no-power. No departure from the plan; the `drawArc` figure in CLAUDE.md is counted as 24 + 20 + 2 = 46 static calls (before main fill/markers), same basis as the old 44.
