# Spec: MAX value beside AVG on the small gauges

Status: signed off 2026-11-16 (user proceeded to plan and implementation
without amending it). Concern 1 resolved as recommended: Explore 2 takes
`FONT_SMALL`.
Intent: [`intent.md`](intent.md) (accepted 2026-11-16).

## Areas of concern

Read these first; each is either a decision this spec makes for you to
confirm, or a risk carried into the plan.

1. **Explore 2 needs a smaller font for the AVG / MAX row (decision to
   confirm).** Measured, with `FONT_MEDIUM` the worst case leaves **1.3 px**
   between the AVG and MAX values in one panel. Two everyday situations hit
   that worst case, not just a rare one: any ride with a peak above 999 W
   (`"1250"` beside a three-digit AVG), and *every* ride with `mainGauge` set
   to HR or power, because speed then sits in a small slot and both of its
   values carry a decimal (`"28.5"` / `"65.2"`, as wide as `"88.8"`).
   `FONT_SMALL` (19 px against 22) gives 8.3 px there. **Recommendation:
   `FONT_SMALL` on the Explore 2 only**, through a new profile key
   `:panelStatFont`. The cost is that the Explore 2's AVG value also shrinks
   by one step, which it does today in `FONT_MEDIUM`. AVG/MAX are values you
   check, not glance at, so that is the right place to give up size. The
   alternative is `FONT_MEDIUM` everywhere and accepting values that nearly
   touch on the Explore 2.

2. **The default rendering changes on every `:full` device.** #14 kept
   `mainGauge` = 0 pixel-identical. This change deliberately does not: the AVG
   value moves out of the centre of its panel to make room for MAX.

3. **The AVG / MAX pair is not centred under the big panel value.** The big
   value sits at `:panelLeftX` / `:panelRightX`, which is the midpoint of the
   panel at the arc's *widest* height. The AVG row sits lower, where the arc
   has curved in by ~20 px on the 1050. Centred under the big value, the pair
   does not fit on any device: it hits the arc on the outer side. So the pair
   is centred on the room that is actually free at its own row, which puts its
   centre 21 px (1050) to 10 px (Explore 2) closer to the screen centre than
   the big value. This needs the visual check in the simulator. If it reads
   as misaligned, the fallback is the quarter-point placement (see Design),
   which balances the pair better but groups it worse.

   **Resolved after the visual check (2026-11-16):** it read as misaligned,
   so the big value and its HR / PWR label now move to the pair instead —
   `centerX ∓ 0.5 × reach`, layout key `:panelValueDX`, replacing
   `:panelLeftX` / `:panelRightX` (which also removes concern 7's 4 px
   asymmetry). That brings the two panels' big values closer together; the
   widest pair that can show at once, `"188"` beside `"1250"` in
   `:panelValueFont`, must keep 8 px (`PANEL_VALUE_MIN_GAP`) between them.
   Gap when exactly centred: 1050 −12.2, 850 53.7, 1030 22.8, 1040 21.3,
   Explore 2 3.6. Value widths on the 1050: 53 px per digit (fixed-width),
   `"188"` 159, `"1250"` 212; 850 90 / 120; 1030 / 1040 / Explore 2 72 / 96.

   **Revised after a second visual check (2026-11-16):** a first version
   floored the offset to keep the 8 px, which left the value ~10 px outward
   of the pair's centre on the 1050 / 1060 (~1.3 px on the Explore 2) on every
   frame — visibly off-centre even for `"--"`. The value is now **always**
   exactly centred, and the gap is kept per frame instead: `drawPanels`
   measures the two strings actually shown, and when
   `leftW + rightW > 4 × :panelValueDX − 2 × PANEL_VALUE_MIN_GAP` the wider one
   is drawn one `FONT_NUMBER_*` step smaller (`smallerNumberFont`), then the
   other too if still needed. Three digits beside three digits always fit
   (`"888"` + `"888"`: 1050 318 of 330.7 allowed, Explore 2 144 of 162.8), so
   in practice only a four-digit power steps down, and only on the 1050 /
   1060 (`FONT_NUMBER_HOT` 109 px → `FONT_NUMBER_MEDIUM` 82 px, `"1250"` 212 →
   160 px, gap 13.8) and the Explore 2 (`FONT_NUMBER_MEDIUM` 48 → `MILD` 41,
   96 → 72 px, gap 17.4). The 850, 1030 and 1040 never step down. The value is
   drawn `TEXT_JUSTIFY_VCENTER`, so the smaller face stays on the same centre
   line. Cost: two `getTextWidthInPixels` per frame on `:full`.

4. **Grouping of four numbers in one row.** The row reads, left to right,
   `AVG MAX | AVG MAX`. If the four values are evenly spaced, nothing shows
   which pair belongs to which panel. The column positions below are chosen
   so the gap between the two panels is about twice the gap inside a panel
   on the 1050 and 1040, and at least 1.6× everywhere.

5. **1030 font metrics differ from the 1040.** The two share a 282×470 panel,
   but measured `FONT_MEDIUM` is 29 px on the 1030 (all three variants) against
   22 px on the 1040, `FONT_SMALL` 26 against 19, `FONT_XTINY` 16 against 13.
   The CLAUDE.md font table has no 1030 column, and the spec's numbers are
   per device for this reason. Add the 1030 column to CLAUDE.md as part of
   this change.

6. **Accepted worst case outside the measurements:** a max speed of 100 km/h
   or more in a small slot (`"100.0"`, five characters) is wider than
   `"88.8"` and is not covered. Descents past 100 km/h are rare, and the
   overlap would be with the panel's own AVG, not with another panel.

7. **Asymmetry already in the layout.** `:panelRightX` is not the mirror of
   `:panelLeftX` (rBarX uses `0.038 × width`, lBarX `0.021 × width`, which puts
   it ~4 px off on the 1050). The arcs themselves are symmetric. The new
   columns are placed symmetrically about `centerX` from the arc geometry, not
   from `:panelRightX`, so this does not spread into the new row. It is left
   as it is for the big value; out of scope.

## Requirements

- **R1.** On the `:full` layout, each small panel shows two values in the row
  that holds AVG today: the slot metric's AVG and its MAX, each under its own
  `FONT_XTINY` label, `AVG` and `MAX`.
- **R2.** AVG is the left column and MAX the right column, **in both panels**
  (not mirrored).
- **R3.** The values come from the existing `avgString(metric)` /
  `maxString(metric)` for the panel's metric (`leftMetric()` /
  `rightMetric()`): max HR, max power, max cadence when there is no power
  data, max speed when speed is in a small slot. Whole numbers except speed,
  which keeps one decimal, as the main gauge's crown already prints it.
- **R4.** Always drawn — not controlled by any setting. "Visualize
  average/max values" keeps controlling only the markers.
- **R5.** No vertical change: the AVG/MAX label row and value row stay at the
  y positions the AVG label and value use today. The panel band does not grow.
- **R6.** No change to the arcs: no MAX marker, no change to the power,
  heart-rate, cadence or speed scales, no extra `drawArc`.
- **R7.** The `:compact` path (840 / 830 / 540 / 530) is untouched.
- **R8.** Worst-case strings, measured on every `:full` device, must not
  touch the arc (AVG marker included) or the neighbouring value. Clearance
  targets: ≥ 2 px to the arc, ≥ 6 px between the two values of a panel, and
  the gap between panels larger than the gap inside a panel.

## Design

### Where the room is

The small arcs are two sides of one circle centred on `centerX` /
`:panelCenterY`. Below the arc centre, the further down a row is, the closer
the arc comes in. The binding row is the **bottom of the value box**.
Measured `reach`, the horizontal distance from `centerX` to the nearest arc
pixel on that row:

- measured against the **AVG-marker pen**, `barW + 4` wide, reaching 2° past
  the sweep, which is tighter than the track itself;
- identical for the label row plus value row and for the value row alone on
  every device, so the value box's bottom edge is what binds.

| Device | Screen | reach (marker) | reach (track) | current AVG x (L / R) |
|---|---|---|---|---|
| 1050 / 1060 | 480×800 | 173.2 | 178.6 | 132.5 / 343.5 |
| 850 / 550 | 420×600 | 158.4 | 162.7 | 115.5 / 301.0 |
| 1040 | 282×470 | 105.3 | 107.5 | 77.0 / 202.5 |
| 1030 / Plus / Bontrager | 282×470 | 106.7 | 110.2 | 77.0 / 202.5 |
| Explore 2 | 240×400 | 87.6 | 89.8 | 66.0 / 172.0 |

The 1060 and 550 measured identical to the 1050 and 850, as CLAUDE.md
predicts.

### Column positions

The x of each column centre is a fixed fraction of `reach`, measured from
`centerX`:

| | Left panel | Right panel |
|---|---|---|
| AVG | `centerX − 0.73 × reach` (outer) | `centerX + 0.27 × reach` (inner) |
| MAX | `centerX − 0.27 × reach` (inner) | `centerX + 0.73 × reach` (outer) |

Labels and values are centre-justified on those x positions. `reach` is
derived in `computeFullLayout` from the arc geometry and the stat font's
measured height, the way `:speedAvgColOffset` is derived on `:compact`. It is
not a profile key, so a future `:full` device needs no tuning for it. All of
its inputs are static, so it belongs in the cached layout.

Placements considered, with the worst clearance across all four slot
configurations (default, main = HR, main = power, no power meter):

| outer / inner | Effect |
|---|---|
| 0.75 / 0.25 (quarter points) | Most balanced inside each panel, but the four values are evenly spaced: no grouping by panel (1050: 23.6 inside, 28.1 between). Explore 2 `FONT_MEDIUM` touches the arc (−0.1 px). |
| **0.73 / 0.27** | **Chosen.** Gap between panels ≈ 2× gap inside a panel on 1050 / 1040; every device meets R8 with the Explore 2 on `FONT_SMALL`. |
| 0.70 / 0.28 and tighter | Better grouping, but the gap inside a panel drops to 3.5 px on the 850 and 2.8 px on the 1030. |

### Measured clearance at 0.73 / 0.27

Worst case over the slot configurations. The widest strings are a
three-digit HR, `"350"` / `"1250"` for power, `"95"` / `"150"` for cadence and
`"88.8"` / `"88.8"` for speed. Values in px; **bold** is the font this spec
ships.

| Device | Font | Arc clearance | Gap inside panel | Gap between panels |
|---|---|---|---|---|
| 1050 / 1060 | **medium** | 10.8 | 16.7 | 35.0 |
| 850 / 550 | **medium** | 6.8 | 9.9 | 27.0 |
| 1040 | **medium** | 8.4 | 13.4 | 24.4 |
| 1030 (all) | **medium** | 4.8 | 7.1 | 18.6 |
| Explore 2 | medium | 1.6 | **1.3** ✗ | 11.3 |
| Explore 2 | **small** | 5.6 | 8.3 | 17.8 |

Measured string widths (px):

| Device | Font | `"95"` | `"188"` | `"88.8"` | `"1250"` | xtiny `AVG` / `MAX` |
|---|---|---|---|---|---|---|
| 1050 / 1060 / 850 / 550 | medium | 36 | 54 | 63 | 72 | 34 / 36 |
| 1040 | medium | 20 | 30 | 35 | 40 | 19 / 20 |
| 1030 | medium | 24 | 36 | 42 | 48 | 22 / 24 |
| Explore 2 | medium | 22 | 33 | 39 | 44 | 21 / 23 |
| Explore 2 | small | 18 | 27 | 32 | 36 | |

Column centres this produces for the left panel, AVG / MAX: 1050 113.6 /
193.2, 850 94.4 / 167.2, 1040 64.1 / 112.6, 1030 63.1 / 112.2, Explore 2
56.1 / 96.4. The right panel mirrors them about `centerX`.

### Profile and layout changes

- **New profile key `:panelStatFont`** (`Graphics.FontType`), the font for the
  AVG and MAX values in the panels. `FONT_MEDIUM` on every `:full` profile
  except the Explore 2, which takes `FONT_SMALL`. It replaces the
  `Graphics.FONT_MEDIUM` hard-coded in `drawPanel`. Documented in the key list
  above `forDevice`. `:full` only; the `:compact` profiles do not carry it.
- **New layout keys** in `computeFullLayout`, documented in the key list above
  it: the two column offsets from `centerX` (outer and inner), derived from
  `reach`.
- `drawPanel` draws two labels and two values where it draws one of each
  today, at the same y. Draw cost: +2 `drawText` per panel, 4 per frame. No
  new `drawArc`.

### Unchanged

The arcs and their markers; the big panel value's font and its HR / PWR
label's font (their x moves — see concern 3); every y coordinate; `metricRatio` and every scale; the settings; the whole
`:compact` path.

## Verification

1. Build all 13 targets at `-l 2` with no new warnings.
2. In the simulator, on every `:full` device (1050, 1060, 850, 550, 1040,
   1030, 1030 Plus, 1030 Bontrager, Explore 2), with a temporary `(:debug)`
   override that forces the worst-case values, take screenshots of:
   - the default mode (HR left, power right, MAX power 1250 W);
   - `mainGauge` = HR (speed `"88.8"` / `"88.8"` on the left);
   - `mainGauge` = power (speed on the right);
   - no power meter (cadence on the right);
   - light and dark backgrounds.
   Compare each screenshot to the clearances above, and check concern 3
   (alignment under the big value) by eye.
3. Screenshot the 840 and 830 to show the `:compact` path is unchanged.
4. Remove the override before the change is committed.

## Measurement method

The values above were measured on 2026-11-16 with SDK 9.3.0. A temporary
`(:debug)` function in `DashView.onUpdate` computed `reach` per row from the
layout and printed `getFontHeight` / `getTextWidthInPixels` for the candidate
fonts and strings. Each device was then run under `monkeydo` and the output
read from the console. The function was removed afterwards; the same method
re-measures a future device.
