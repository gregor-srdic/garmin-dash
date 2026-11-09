# Spec: selectable metric for the main gauge

Status: **signed off 2026-11-09**, amended A1-A3
Intent: [intent.md](intent.md), accepted 2026-11-09.

## Areas of concern

These come first because each one either conflicts with a documented rule in `CLAUDE.md` or rests on something that has not been measured yet.

1. **Accepted text overruns (decided, documented).** A four-digit power (`"1250"`) is wider than the `"88.8"` the main readout was sized for. A four-digit max power in the `:compact` crown is wider than the `"99.9"` that `:speedAvgColOffset` is derived from, and on the 840 it will clip the arc. Intent Q2/Q3 accepted both. The spec requires measuring them and tabulating the result in the comment above the draw function, the same way `drawCompactTopBar` and `drawCompactFooter` already record theirs. `computeCompactLayout` keeps measuring `"99.9"`, so the layout does not change between modes.
2. **Speed in the small slots is unmeasured.** `"35.2"` (`%.1f`) is four glyphs, and the HR/power values it replaces are at most three in normal riding. It has to fit:
   - the `:full` panel at `:panelValueFont`, centred in a panel. Tightest case: Explore 2 and 850, `FONT_NUMBER_MEDIUM`.
   - the `:compact` bar, right-justified at `barsLeftX1` or left-justified at `barsRightX0`, in `FONT_NUMBER_MILD`, sharing the line with the `KMH` label at the outer edge. Half the bar row is about 111 px.
   The worst case to measure is `"88.8"`. If it does not clear, the fallback is to print speed in the small slot with `%d`. That is a spec change and comes back for sign-off; the code does not pick it silently.
3. **The `:full` panel AVG row with speed** is `"35.2"` in `FONT_MEDIUM`, where it used to be a two- or three-digit number. Measure it on the 850 (shortest `:full` aspect).
4. **The MAX marker pins on power.** The power scale is `max(FTP, session max power)`, so once max power exceeds FTP the MAX marker sits at the end of the arc for the rest of the ride. Intent decision 3 accepts this. It is not a bug.
5. **Code size on the 830 / 530.** Old data fields have a tight memory budget. The design keeps one draw function per gauge type, parameterised by metric, rather than copying the draw functions. It allocates nothing per frame: no Dictionaries or Arrays, only Strings that are already built today. Verify by running a ride on the 830 in the simulator with *View → Memory* open and checking that peak memory stays under the limit.
6. **Cadence appears twice.** In Power mode without a power meter, cadence is in the main gauge and still in the `:full` middle row (`CAD`). That is already true today for the right panel, so this is not a new conflict. The `:compact` footer is unchanged: it shows `ASC` instead of `CAD` when there is no power data, which still avoids the duplicate.
7. **The label flips CAD → PWR mid-ride.** The first time any power is seen, `mHasPowerData` latches true and the main gauge switches from cadence to power, label and scale together. This is the same behaviour the right panel has today, and the spec keeps it.

## Requirements

### R1 Setting

- New property `mainGauge` (`type="number"`), default `0`.
- List setting titled **Main Gauge**, with entries `0` Speed, `1` Power (Cadence), `2` Heart Rate.
- Read in `readSettings()` into `mMainGauge`. Any value that is not a Number in `0..2` falls back to `0`. A change applies on the next frame through `onSettingsChanged()`.

### R2 Slot assignment

There are three slots: **main**, **left** (`:full` left panel / `:compact` left bar) and **right** (`:full` right panel / `:compact` right bar). There are three metrics: **SPEED**, **RIGHT** (power, or cadence while `mHasPowerData` is false) and **HR**.

| `mMainGauge` | main | left | right |
|---|---|---|---|
| 0 Speed | SPEED | HR | RIGHT |
| 1 Power | RIGHT | HR | SPEED |
| 2 Heart Rate | HR | SPEED | RIGHT |

With `mMainGauge == 0` every pixel must be identical to the current build.

### R3 What each metric shows, per slot

| | SPEED | RIGHT (power) | RIGHT (no power → cadence) | HR |
|---|---|---|---|---|
| Current value string | `mSpeed` `%.1f` | `mPower` or `--` | `mCadence` or `--` | `mHeartRate` or `--` |
| Fill ratio | speed / `mSpeedGaugeMax` | power / max(FTP, max power) | cadence / 150 | across HR zone span, or 0-200 |
| Lit colour | `COLOR_SPEED` | power zone colour | `COLOR_CADENCE` | HR zone colour |
| Main-gauge unit label | `KMH`/`MPH` | `PWR` | `CAD` | `HR` |
| Small-gauge label | `KMH`/`MPH` | `PWR` | `CAD` | `HR` |
| AVG value | `mAvgSpeed` `%.1f` | `mAvgPower` | `mAvgCadence` | `mAvgHeartRate` |
| MAX value (crown only) | `mMaxSpeed` `%.1f` | `mMaxPower` | `mMaxCadence` (new) | `mMaxHeartRate` (new) |
| Small-gauge "floor to one lit segment" | no | no | no | yes, when not null |

- **Main arc:** keeps its 24 (`:full`) / 12 (`:compact`) segments and its smooth partial fill. Only the fill ratio and the lit colour change. The colour is computed once per frame from the current value.
- **Main arc markers:** AVG/MAX use the same ratio function as the fill, applied to the avg/max values. Drawn when the value is `> 0` and `mShowSpeedIndicators` is on. The setting keeps its key and its title (`visualize average/max speed`). Renaming the title is a nit and out of scope.
- **Crown:** labels stay `AVG` / `MAX`, and the values come from the table above.
- **Small slot on `:full`:** the label above, the 10-segment arc, the value, and `AVG` with the avg value below.
- **Small slot on `:compact`:** the label, the value and the 10-segment bar. There is no AVG, as today.
- Fonts, positions and profile keys are unchanged. No new `DeviceProfiles` keys.

### R4 New data

`compute()` also stores `info.maxHeartRate` → `mMaxHeartRate` and `info.maxCadence` → `mMaxCadence`. Both are non-nullable `Number = 0` and keep their last value, like the other cumulative stats. Both fields exist on `Activity.Info` since API 1.0, so they need no `has` guard.

## Design

Metric ids are class constants: `METRIC_SPEED = 0`, `METRIC_RIGHT = 1`, `METRIC_HR = 2`. They deliberately share their numbers with the setting values, so the main slot's metric is `mMainGauge` and `leftMetric()` / `rightMetric()` derive the other two per R2.

The metric arithmetic stays in one place (the `CLAUDE.md` rule). It is generalised from "the current value" to "a given value":

- `metricRatio(metric, value as Numeric?) as Float`: holds the scaling that `hrFillRatio` / `rightFillRatio` hold today, plus speed. `hrFillRatio()` and `rightFillRatio()` are removed and their callers use `metricRatio(m, currentValue(m))`.
- `metricColor(metric) as Number`: generalises `rightZoneColor()` and the inline HR `zoneColor` call. Speed returns `COLOR_SPEED`.
- `currentValue(metric) as Numeric?`, `avgValue(metric) as Numeric`, `maxValue(metric) as Numeric`.
- `metricString(metric, value as Numeric?) as String`: `%.1f` for speed, integer otherwise, `--` for null. Replaces `rightValueString()`.
- `metricLabel(metric) as String`: `KMH`/`MPH`, `PWR`/`CAD`, `HR`.

Draw functions:

- `drawSpeedGauge` → `drawMainGauge`, `drawCompactSpeedGauge` → `drawCompactMainGauge`. Both read `mMainGauge` and go through the helpers. Geometry is untouched.
- `drawPanels`: the HR and PWR blocks become one `drawPanel(dc, layout, metric, isLeft)`. The only per-side differences are centre X, start angle and arc direction, which are what the two blocks differ in today.
- `drawCompactBars`: same treatment, `drawCompactBar(dc, layout, metric, isLeft)`. Per side, the bar direction and the label/value justification differ.

This removes the HR/PWR duplication in both panel functions rather than adding a third branch to each. With `mMainGauge == 0` the call sequence and every coordinate must match today's, which is what R2's "pixel-identical" check verifies.

## Out of scope

- Renaming `visualizeSpeedIndicator` or its title.
- A per-metric full-scale setting (for example HR max or power scale). The existing scales are reused.
- Swapping the `:full` middle-row `CAD` or the `:compact` footer slots.

## Verification

1. `monkeyc -l 2` builds clean for edge1050, edge1040, edge1030, edge850, edgeexplore2, edge840 and edge830. Show the output.
2. Simulator, each of those devices, `mainGauge` = 0: compare screenshots against the `main` build with the same simulated data. They must be identical.
3. Simulator, `mainGauge` = 1 and 2, with a FIT playback that has power, HR and cadence, and one without power. Screenshot each device and mode, and check the swap, labels, colours and markers per R3.
4. A temporary `(:debug)` println of text widths for `"88.8"` in `:panelValueFont` / `:barValueFont` / `FONT_MEDIUM`, and for `"1250"` in `:speedFont` / `:crownValueFont`, per device. The results go into the overrun comments (concerns 1-3).
5. 830 memory peak in the simulator's memory view (concern 5).
6. `readme.md` "What's on screen" and the settings list are updated. `CLAUDE.md` is updated where it says the right panel is HR/PWR (Architecture, "Zones and gauges") and where it names `drawSpeedGauge` / `drawCompactSpeedGauge` / `rightValueString` / `hrFillRatio` / `rightFillRatio`.

## Amendment A1 (2026-11-09, requested by the user after sign-off)

> dodaj indikator povprečne vrednosti na oba manjša gauges (uporabi obstoječo nastavitev za vklop prikaza). pri manjših ne vključuj max vrednosti, samo avg

Decisions from the follow-up questions: the AVG marker colour is the values colour (white on dark, black on light) **everywhere**, including the main gauge, whose MAX marker stays green (later changed to red, A4); the compact bars get the marker too.

### R5 AVG marker on the small gauges

- Both small slots, on both layouts, draw an AVG marker for whatever metric the slot holds (HR, power/cadence or speed, per R2). No MAX marker on the small slots.
- Shown when `mShowSpeedIndicators` is on and `avgValue(m) > 0` — the same rule as the main gauge.
- Position uses `metricRatio(m, avgValue(m))`, i.e. the same scale as the slot's fill. Continuous along the gauge, not snapped to a segment.
- `:full` panel: a short arc at that angle on the panel radius, ±2° like the main marker, pen `barW + 4`. Left panel angle `180 + sweep/2 - ratio × sweep`, right `360 - sweep/2 + ratio × sweep`.
- `:compact` bar: a filled rectangle 3 px wide, `barH + 4` tall (2 px above and below the bar), centred on `lX1 - ratio × barLen` (left) / `rX0 + ratio × barLen` (right), where `barLen` is the bar's full extent including gaps.
- Colour `mValuesColor`.

### R6 Main gauge AVG marker colour

The main gauge AVG marker (both layouts) changes from `COLOR_AVG_INDICATOR` (orange) to `mValuesColor`. MAX stays `COLOR_MAX_INDICATOR`, recoloured red (0xff0000) on 2026-11-09 at the user's request (A4).

### Consequences for earlier sections

- **R2 "pixel-identical with mode 0" no longer holds with markers on**, because R6 recolours the main AVG marker and R5 adds markers. The identity check now runs with indicators **off** (fixture constant), where neither R5 nor R6 draws anything, so the refactor is still proven to 0 pixels. Markers are checked visually with indicators on.
- `:full` issues 46 `drawArc` calls per frame instead of 44 (two panel markers). `:compact` adds two `fillRectangle` calls, and its arc count is unchanged.
- **Concern 8:** the setting title "visualize average/max speed" now also controls the markers on HR, power and cadence. The title is a user-facing string and is now inaccurate. Renaming it is still out of scope unless the user asks.

## Amendment A2 (2026-11-09, user request)

Concern 8 is resolved: the setting title `visualizeSpeedIndicatorTitle` is renamed from "visualize average/max speed" to **"Visualize average/max values"**. Only the string changes. The property key `visualizeSpeedIndicator` and the field `mShowSpeedIndicators` stay, so a rider's saved value is kept.

## Amendment A3 (2026-11-09, user decision after review round 1)

Review round 1 found that concern 2 had been measured wrongly. The margins were taken from the panel arc's pen centre instead of its inner edge, and on the 1050/1060 `"34.6"` in `:panelValueFont` touches the arc. The user chose: **the current speed in a small slot prints without decimals (`%.0f`, rounded) on every device and both layouts.** The small slot's AVG row (`:full`) stays `%.1f`. Speed in the main gauge and in the crown is unchanged (`%.1f`).
