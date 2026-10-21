# Spec: power training metrics and W′ balance in the FIT file

Status: **Signed off 2026-10-21.** Date: 2026-10-21. Follows `intent.md`.

## Areas of concern (read first)

1. **Native duplicates.** Edge devices already compute NP, IF, TSS and total work and write them to
   the FIT session, and Connect displays them. Writing them again as developer fields would
   show the same metric twice in Connect, with slightly different values. **Decision:** the FIT
   file gets W′bal only. NP/IF/TSS/kJ are on-screen only.
2. **On-screen values will not match native ones exactly.** Connect IQ's `Activity.Info` does
   not expose native NP/TSS, so Dash computes its own. Differences come from the FTP source
   (Dash uses the profile FTP where the API exists, otherwise the app setting, while the device
   uses its own), from how zeros are averaged (Garmin's "include zeros" setting is not readable),
   and from how dropouts are handled. Target: within 3% on a steady ride. This is a known
   limitation and will be documented in the readme.
3. **No-power rides and the FIT chart.** FIT fields have to be created in `initialize()`, before
   it is known whether a power meter is present. If a field that is never written still produces
   an empty or flat chart in Connect, that is a visible regression for every rider without
   power. **This must be checked in the simulator plus Monkey Graph before the field ships.** If
   it does produce one, the fallback is to drop the RECORD field and keep only the
   SESSION and LAP minimums.
4. **Precision.** The NP fourth-power sum reaches about 1e15 on a long ride, which is beyond a
   32-bit Float's 24-bit mantissa. It is accumulated in a `Double`.
5. **`Math.exp` does not exist** in the SDK, which has `pow`/`ln`/`log`/`sqrt` only. W′ recovery
   uses `Math.pow(E, x)` with a local `E` constant.
6. **First tests in the repo.** `CLAUDE.md` says there is no test suite, and this change makes that
   stale. The tests use Run No Evil `(:test)` functions, which are stripped from debug and
   release builds.
7. **Carried forward from intent:** the accumulators reset when the field is recreated mid-ride
   (accepted for v1), negative W′bal is displayed as negative, and VAM/grade are out of scope.

## Requirements

### R1 — Metric engine (`PowerMetrics`)

A pure class with no `WatchUi`/`Activity` dependency, so it can be unit-tested.

- `addSample(power as Number?, dtMs as Number)` is called from `compute()` with the timer delta
  since the last call.
  - `dtMs <= 0` (timer paused or stopped): ignored.
  - `dtMs > 5000`: ignored and re-anchored. This prevents a single huge step after a gap.
  - `power == null` (dropout): no change to NP, kJ or W′bal. The rolling window does not advance.
  - Otherwise the sample is taken as `n = max(1, round(dtMs / 1000))` one-second samples of `power`.
- **NP**: a 30-sample rolling mean of power, raised to the fourth power and accumulated (Double).
  `NP = (Σ⁴ / count)^(1/4)`. It is null until the first 30 s window fills.
- **IF** = NP / FTP. **TSS** = `seconds × NP × IF / (FTP × 3600) × 100`, where seconds counts the
  samples taken.
- **kJ** = Σ(power × dt) / 1000.
- **W′bal** (Skiba 2015 differential form), per one-second step with `P`:
  - `P > CP`: `wbal -= (P − CP)`
  - `P ≤ CP`: `wbal = W′ − (W′ − wbal) × E^(−(CP − P) / W′)`
  - It starts at W′. There is no lower clamp (the value can go negative). It is clamped at W′ above.
  - `minWbal` and `lapMinWbal` are tracked.
- `reset()` sets everything back. `startLap()` resets `lapMinWbal` to the current W′bal.
- `setThresholds(ftp, cp, wPrime)` can be called mid-ride. NP, kJ and the sample count are kept,
  W′bal is clamped to the new W′, and IF/TSS use the new FTP immediately.

### R2 — Settings

| Property | Type | Default | Range | Meaning |
|---|---|---|---|---|
| `cp` | number | 0 | 0–600 | Critical power in W. 0 = use the resolved FTP. |
| `wPrime` | number | 20000 | 5000–60000 | W′ in joules. |
| `powerPanelStat` | number (list) | 0 | 0–5 | 0 AVG, 1 NP, 2 W′BAL, 3 TSS, 4 IF, 5 KJ |

All three are read in `readSettings()` only. A value that is invalid or out of range falls back to
its default, in the same way `mFtp` does.

### R3 — On-screen (`:full` only)

- In `drawPanels`, the right panel's xtiny label (`"AVG"`) and its FONT_MEDIUM value come from
  two new formatters, `rightPanelStatLabel()` / `rightPanelStatString()`.
- Labels: `AVG`, `NP`, `W'BAL`, `TSS`, `IF`, `KJ`. These are ASCII; the `′` glyph in FONT_XTINY is
  not verified on every device.
- Formats: NP `%d`; W′bal `%d%%` of W′ (for example `73%`, `-8%`); TSS `%d`; IF `%.2f`;
  kJ `%d`. If the value is null, `NO_VALUE`.
- No power data (`mHasPowerData == false`): the right panel is the cadence gauge, and the
  setting is ignored (AVG cadence as today).
- The left (HR) panel, the `:compact` path, and all geometry and profile keys are unchanged.
- **Width budget:** the widest value must be no wider than today's worst AVG value, `"1999"` at
  FONT_MEDIUM. The candidates are `"-100%"` and `"0.85"`. They are measured on the 1040, the
  Explore 2 and the 850 (the three narrowest panels). If `"-100%"` is wider, negative W′bal is
  clamped to `-99%` for display only.
  - **Amended during build:** the `"1999"` limit turned out to be the wrong test. Every
    W′bal value, including `"100%"` at ride start, is wider than `"1999"` (by 5–8 px), so the
    `-99%` clamp would not have helped. The real limit is clearing the gauge arc, and
    screenshots show `"-100%"` under `"W'BAL"` clearing it with room to spare on all three
    devices. No clamp was applied.

### R4 — FIT developer fields (all devices)

| id | name | mesgType | type | units | Connect display |
|---|---|---|---|---|---|
| 0 | `w_bal` | RECORD | FLOAT | kJ | chart "W′ Balance", precision 1 |
| 1 | `w_bal_min` | SESSION | FLOAT | kJ | summary "Min W′ Balance", precision 1 |
| 2 | `w_bal_min_lap` | LAP | FLOAT | kJ | laps "Min W′ Balance", precision 1 |

- Fields are created in `DashView.initialize()` and written from `compute()`, only once
  `mHasPowerData` is true.
- `onTimerLap()` calls `startLap()`. `onTimerReset()` calls `reset()`.
- The permission `FitContributor` is added to `manifest.xml`.
- Metadata goes in `resources/fitcontributions/fitcontributions.xml`, with strings in `strings.xml`.

### R5 — Tests and docs

- `(:test)` functions cover R1 (see plan, step 2).
- `CLAUDE.md`: the build section gets the test command; the conventions get the permission list and
  the new settings; the architecture gets a short "Power metrics" section.
- `readme.md`: the feature list and the known limitation from concern 2.

## Out of scope

Persisting the accumulators across a mid-ride restart; `:compact` on-screen display; VAM; grade or
NP/IF/TSS/kJ in the FIT file; a Pro build split.
