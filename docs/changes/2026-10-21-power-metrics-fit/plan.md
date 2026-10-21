# Plan: power training metrics and W′ balance in the FIT file

Status: **Implemented; manual simulator proof (items 3, 4, 6) pending.** Date: 2026-10-21. Implements `spec.md` (R1–R5). Read the spec's "Areas of
concern" first.

## Files

| File | Change |
|---|---|
| `source/PowerMetrics.mc` | **new**: the R1 engine, a pure class |
| `source/PowerMetricsTest.mc` | **new**: `(:test)` functions for R1 |
| `source/DashView.mc` | owns a `PowerMetrics`; settings, compute, timer hooks, FIT fields, panel formatters |
| `resources/properties/properties.xml` | `cp`, `wPrime`, `powerPanelStat` |
| `resources/settings/settings.xml` | the three settings, `powerPanelStat` as a `list` |
| `resources/strings/strings.xml` | setting titles, list entries, FIT labels/units |
| `resources/fitcontributions/fitcontributions.xml` | **new**: R4 metadata |
| `manifest.xml` | `FitContributor` permission |
| `CLAUDE.md`, `readme.md` | R5 |

## Order of work

### 1. `PowerMetrics.mc`

The class holds: a 30-entry `Array<Number>` ring buffer, its running sum, and a fill count;
`mSum4 as Double`, `mNpCount`, `mSeconds`, `mJoules as Double`; `mWbal`, `mMinWbal`, `mLapMinWbal`
as Float; and `mFtp`, `mCp`, `mWPrime`. Public API: `setThresholds`, `addSample(power, dtMs)`,
`reset`, `startLap`, and getters `np() as Number?`, `intensity() as Float?`, `tss() as Float?`,
`kilojoules() as Number`, `wbal() as Float`, `wbalPercent() as Number`, `minWbal() as Float`,
`lapMinWbal() as Float`, `hasSamples() as Boolean`.

`addSample` implements the dt rules from R1 and loops `n` times over a private `step(power)`, which
does the NP window, the joules and the W′bal update. Use `const E = 2.718281828` with `Math.pow`,
because the SDK has no `Math.exp`. Write the comments in the style of `DashView.mc`: say why, and
name the bug that a guard prevents.

### 2. `PowerMetricsTest.mc`, written before the class is finished (TDD)

These are global `(:test)` functions, each taking a `Logger` and returning a Boolean. Floats are
compared with a tolerance. Cases:

1. 3600 × 200 W, FTP 200 → NP 200, IF 1.00, TSS 100.0, kJ 720.
2. Fewer than 30 samples → `np()` is null, and IF and TSS are null.
3. 30 s at 400 W then 30 s at 0 W → NP > the 200 W average (the fourth-power weighting works).
4. W′ 20000, CP 250: 60 × 350 W → wbal 14000 J. Then 300 × 150 W → wbal is between 14000 and
   20000 and rising every step. It never exceeds W′.
5. 300 × 450 W with CP 250, W′ 20000 → wbal is negative, minWbal equals wbal, and
   `wbalPercent()` is negative.
6. `dtMs` of 0 and of −1000 → no change to anything. `dtMs` of 9000 → ignored. `dtMs` of 3000
   → three samples.
7. `power == null` → no change, and the window does not advance.
8. `startLap()` after a dip → `lapMinWbal` equals the current wbal and `minWbal` keeps the
   older, lower value.
9. `reset()` → everything is back to its initial value, and wbal equals W′.
10. `setThresholds` mid-ride with a smaller W′ → wbal is clamped to the new W′, and kJ is kept.

Build them with `--unit-test` and run them with `monkeydo … /t` (see Proof). Confirm they fail
against a stub before writing the real `step()`.

### 3. Settings and resources

Add the properties, the settings (`powerPanelStat` as `settingConfig type="list"` with six
`listEntry`s) and the strings. In `DashView.readSettings()`: read `cp` and `wPrime` (falling back to
the defaults if they are invalid; CP 0 → `mFtp`), read `powerPanelStat` (0–5, otherwise 0), and call
`mPowerMetrics.setThresholds(mFtp, cp, wPrime)`. That call has to come after `mFtp` is resolved.

### 4. Wire into `compute()` and the timer hooks

- Add `mPowerMetrics` (created in `initialize()` before `readSettings()`) and `mLastTimerMs as Number?`.
- In `compute()`, after the power block: compute `dt = info.timerTime - mLastTimerMs` when both
  are non-null, call `mPowerMetrics.addSample(mPower3s, dt)`, then set `mLastTimerMs`. Use
  `info.timerTime` rather than wall-clock time, so that pauses are excluded for free.
- `onTimerReset()`: call `mPowerMetrics.reset()` and set `mLastTimerMs = null`, next to the
  existing grade reset.
- New `onTimerLap()`: call `mPowerMetrics.startLap()`.

### 5. FIT fields

- Add the `FitContributor` permission to `manifest.xml`, and `import Toybox.FitContributor` to the view.
- In `initialize()`, after `DataField.initialize()`, create the three fields per R4 with
  `createField(...)`. Store them as `FitContributor.Field?`.
- In `compute()`, when `mHasPowerData` is true: set `w_bal` to wbal/1000, `w_bal_min` to minWbal/1000,
  and `w_bal_min_lap` to lapMinWbal/1000.
- Write `resources/fitcontributions/fitcontributions.xml` with ids 0–2, `displayInChart` true only on
  id 0, `displayInActivitySummary` on id 1, `displayInActivityLaps` on id 2, and fillColor `#9900FF`
  (`COLOR_POWER`).

### 6. On-screen (`:full` only)

- Add `RIGHT_PANEL_STAT_LABELS = ["AVG", "NP", "W'BAL", "TSS", "IF", "KJ"]` as a class constant.
- `rightPanelStatLabel()` and `rightPanelStatString()` sit beside `rightValueString()`. With no
  power data they return `"AVG"` and the AVG cadence, as today.
- In `drawPanels`, replace the right panel's hardcoded `"AVG"` and its ternary value with those
  two calls. No coordinate changes. Nothing on the `:compact` path changes.
- Measure the width budget: add a temporary `(:debug)` `System.println` of
  `getTextWidthInPixels` for `"1999"`, `"-100%"` and `"0.85"` at FONT_MEDIUM. Run it on the
  edge1040, edgeexplore2 and edge850. Apply the `-99%` display clamp if R3 requires it, then
  remove the println.

### 7. Docs

Update `CLAUDE.md` (the "no test suite" line is now stale, plus the permission list, a power
metrics section and the test command) and `readme.md`.

## Proof

Each item records its actual output in the PR.

1. **Unit tests**: build with `monkeyc … -d edge1050 -l 2 --unit-test -o bin/DashTest.prg`, then
   run `monkeydo bin/DashTest.prg edge1050 /t`. All tests pass. Repeat on **edge830**, the
   oldest CIQ target (3.3.1).
2. **Type-check build**: `-l 2`, zero warnings, for all 13 products. A script loops over the
   `<iq:product>` ids.
3. **Simulator, power ride**: replay a FIT file with power (Simulation → FIT data) on the edge1050,
   edge1040, edgeexplore2, edge850 and edge1030. Cycle `powerPanelStat` through all 6 values
   with the app settings editor and screenshot each, in dark and light. Compare the AVG row's
   position against a screenshot from `main`.
4. **Native comparison**: on the same replay, compare Dash's NP/TSS with the simulator's native
   values. They should be within 3%.
5. **Simulator, no-power ride**: the right panel shows cadence, and the stat setting has no effect.
6. **FIT output**: record a ride in the simulator, save it, and open it in **Monkey Graph** together
   with the exported `.iq`. Check that the W′bal chart renders and that the summary and lap
   values appear. Repeat on a no-power recording and confirm **there is no empty W′bal chart**
   (spec concern 3). If there is one, apply the fallback and amend this plan.
7. **`:compact` unchanged**: screenshots of the edge830 and edge840 are pixel-identical to `main`.

## What it could break

- **Every rider's store listing** gains the `FitContributor` permission. This is low risk, but it
  is visible.
- **No-power riders** could get an empty chart in Connect (step 5). This is the riskiest step,
  because it only shows up after a real upload, so Monkey Graph is the gate.
- **The right-panel AVG row on narrow `:full` screens** could overflow with a wide stat. Step 6
  measures it.
- **The 1 Hz path** gains up to 5 inner steps per `compute()`. Each is a few float ops and one
  `Math.pow` for the recovery branch, which is negligible next to the 44 `drawArc`s per frame.
- **Memory**: one object, a 30-element array and three Field handles. This is small against the
  131072-byte data-field limit, but check the peak in the simulator's memory view on the edge830.

## Rejected alternatives

- **Writing NP/IF/TSS/kJ as FIT developer fields** would duplicate the native session values
  (spec concern 1).
- **Integral (Skiba 2012) W′bal** needs the full power history, an O(n) memory cost on a
  1-hour-plus ride. The differential form is O(1) and is what most head units use.
- **A new on-screen slot or profile keys for the stats** would mean re-tuning `:full` geometry on
  six devices. The setting-driven AVG row reuses a slot that is already tuned.
- **Putting the computation inline in `DashView`** would leave nothing that can be unit-tested,
  and nothing that can be lifted into a Pro build later.

## Departures from this plan (recorded during build)

- **Test helpers**: `(:test)` global functions must take a `Logger` and return a `Boolean`, so the
  shared helpers (`feed`, `near`, `newMetrics`) live in a `(:test)` module, `PowerMetricsTestKit`.
- **Step 2, case 6**: the `kilojoules() == 0` check after three seconds at 300 W was dropped.
  0.9 kJ rounds to 1, so the check tested rounding, not the dt rules.
- **Step 6 width probe**: the `"1999"` limit was the wrong test (see spec R3, amended). The check
  was done on screen with a temporary worst-case override (`"-100%"` / `"W'BAL"`), which has since
  been removed. No clamp was needed.
- **Memory**: the simulator showed 25.8 of 124.5 kB on the 1040, Explore 2 and 850.
