# Plan: MAX value beside AVG on the small gauges

Status: accepted for implementation 2026-11-16.
Intent: [`intent.md`](intent.md) · Spec: [`spec.md`](spec.md). The spec was
signed off with concern 1 resolved as recommended: the Explore 2 takes
`FONT_SMALL`.

## Files that change

| File | Change |
|---|---|
| `source/DeviceProfiles.mc` | New key `:panelStatFont` on every `:full` profile; documented in the key list. |
| `source/DashView.mc` | `computeFullLayout` derives the AVG/MAX column offsets; `drawPanel` draws two columns. |
| `CLAUDE.md` | 1030 column in the font table; a paragraph on the panel AVG/MAX row. |
| `docs/changes/2026-11-16-small-gauge-max/plan.md` | This file, updated if implementation departs from it. |

Nothing else changes: no resources, no settings, no `:compact` code.

## Order of work

### T1 — `:panelStatFont` profile key (`source/DeviceProfiles.mc`)

Add `:panelStatFont => Graphics.FONT_MEDIUM` to the 850/550, 1050, 1030 and
1040 (fallback) profiles, and `:panelStatFont => Graphics.FONT_SMALL` to the
Explore 2 profile. Place it next to `:panelValueFont` in each. Add it to the
key list comment above `forDevice`, next to `:panelValueFont`:

> `:panelStatFont` (Graphics.FontType) — font for the AVG and MAX values
> under the HR and power panels. FONT_MEDIUM except on the Explore 2, where
> FONT_SMALL is what lets "1250" or "88.8" sit beside the panel's AVG without
> touching it — see drawPanel. [full only]

The `:compact` profiles do not get it. Because a `:full` profile carries
every key, update the comment's statement of how many keys `:compact` carries
only if it would otherwise become false (it does not: `:compact` still
carries nine).

### T2 — Layout and drawing (`source/DashView.mc`), after T1

**`computeFullLayout`** — after the existing panel values, derive `reach`,
the horizontal distance from `centerX` to the nearest pixel the panel arc's
**AVG-marker pen** covers, over the rows of the AVG/MAX label and value boxes:

- Inputs, all static, so the result belongs in the cached layout:
  `panelCenterY` and `panelRadius` as already computed, `barW`, `xtinyH`,
  `panelLabelOffset`, the profile's `:panelArcSweep`, `:avgLabelOffset`,
  `:panelAvgValueOffset`, `:panelTextYOffset`, and
  `dc.getFontHeight(mDeviceProfile[:panelStatFont])`.
- Rows: from the label top,
  `panelCenterY + panelLabelOffset - xtinyH - 1 + avgLabelOffset + panelTextYOffset`,
  to the value box bottom,
  `panelCenterY + panelLabelOffset + panelAvgValueOffset + avgLabelOffset + panelTextYOffset + statFontH`.
  These are the y positions `drawPanel` already uses for the AVG label and
  value.
- Pen: inner radius `rIn = panelRadius - (barW + 4) / 2`, outer
  `rOut = panelRadius + (barW + 4) / 2`, half-angle
  `h = (panelArcSweep / 2 + 2)` degrees. The +4 and +2° are the AVG marker's
  pen width and its ±2° overhang past the sweep.
- At row offset `dy = y - panelCenterY`: `rho = max(rIn, |dy| / sin h)`; if
  `rho > rOut` the pen does not reach the row, so skip it. Otherwise the arc
  is `sqrt(rho² - dy²)` from `centerX`. `reach` is the minimum over the rows.
  If no row is reached, `reach = rIn`. A per-row loop (~60 iterations, once
  per layout) or the closed form are both fine.
- New layout keys, added to the key list above `computeFullLayout` under
  band 4:
  - `:panelStatOuterDX => 0.73 * reach`
  - `:panelStatInnerDX => 0.27 * reach`

  The 0.73 / 0.27 split, and why, is a comment beside it pointing at
  `docs/changes/2026-11-16-small-gauge-max/spec.md`.

Expected `reach` (measured with `FONT_MEDIUM` height; the Explore 2's
`FONT_SMALL` is 3 px shorter, so its reach comes out slightly *larger* than
listed, which only adds clearance): 1050/1060 173.2, 850/550 158.4, 1040
105.3, 1030 106.7, Explore 2 ≥ 87.6.

**`drawPanel`** — replace the single `AVG` label and the AVG value, both at
`panelCenterX`, with two columns at the same two y positions:

| | label | value |
|---|---|---|
| AVG x | left panel `centerX - :panelStatOuterDX`, right panel `centerX + :panelStatInnerDX` | same x |
| MAX x | left panel `centerX - :panelStatInnerDX`, right panel `centerX + :panelStatOuterDX` | same x |

- Labels: `FONT_XTINY`, `mLabelsColor`, `"AVG"` / `"MAX"`, centre-justified.
- Values: `mDeviceProfile[:panelStatFont]` (replacing the hard-coded
  `Graphics.FONT_MEDIUM`), `mValuesColor`, `avgString(metric)` /
  `maxString(metric)`, centre-justified.
- Always drawn: no `mShowSpeedIndicators` check on the text.
- Update the comment above `drawPanel` ("label, 10-segment arc with the AVG
  marker across it, value, then AVG with its value") to describe the AVG/MAX
  row.

The arc and the AVG marker stay exactly as they are. **Drift (2026-11-16):**
the big value and its HR/PWR label no longer stay at `:panelLeftX` /
`:panelRightX`; they centre over the AVG/MAX pair via `:panelValueDX`
(`0.5 × reach`, never floored). `drawPanels` resolves both value strings and
passes each `drawPanel` its text and font; when the two would come within 8 px
of each other the wider steps down one number font (`smallerNumberFont`).
See spec concern 3 for the measurements. A first version floored
`:panelValueDX` instead, which left the 1050 values ~10 px off-centre; it was
replaced after the simulator check.

### T3 — `CLAUDE.md`, parallel with T1

- Add a **`1030` column** to the font table. The heights
  measured so far are `xtiny` 16, `small` 26, `medium` 29. Measure the rest
  (`tiny`, `large`, `numberMild`, `numberMedium`, `numberHot`,
  `numberThaiHot`) on the 1030 in the simulator. Do this from a **copy of the
  project outside the repo**, with a temporary `(:debug)` print of
  `dc.getFontHeight` for each font, and run it with `monkeydo`. Measure the
  1030 Plus and 1030 Bontrager too; if they match, the column header is
  `1030 / Plus / Bontrager`. Do not edit `source/` in the repo.
- In the Rendering section, after the paragraph about the AVG marker, add a
  short paragraph:
  - `:full` panels print AVG and MAX side by side under the arc, AVG left and
    MAX right in both panels, always shown.
  - The column offsets are derived from the arc's reach at that row
    (`:panelStatOuterDX` / `:panelStatInnerDX`).
  - The value font is `:panelStatFont`: FONT_SMALL on the Explore 2,
    FONT_MEDIUM elsewhere.
  - `:compact` has no AVG/MAX text.
  - Link the spec for the measurements.
- Keep it short; CLAUDE.md is long already.

## Proof

1. **Build:** `.agent-runs/small-gauge-max/build-all.ps1` builds all 13
   manifest targets at `-l 2` and fails on any `WARNING`. Baseline before the
   change: `ALL 13 OK`.
2. **Layout values:** a scratch copy of the changed project with a `(:debug)`
   print of `reach`, `:panelStatOuterDX` and `:panelStatInnerDX` from
   `computeFullLayout`, run on each `:full` device. `reach` must match the
   expected values above within 1 px (Explore 2: ≥ 87.6).
3. **Visual:** from the same scratch copy, with a `(:debug)` override in
   `compute()` that forces worst-case values (AVG/MAX HR 188/220, power
   350/1250, speed 88.8/88.8, cadence 95/150), take simulator screenshots on
   1050, 850, 1040, 1030 and Explore 2:
   - in the default mode, `mainGauge` = HR and `mainGauge` = power;
   - plus one 840 and one 830 screenshot to show `:compact` is unchanged.

   Check: no value touches the arc or its neighbour; the gap between panels
   is wider than the gap inside each; the pair's offset from the big value
   (spec concern 3) reads acceptably.
4. The repo never contains the debug override; it lives only in the scratch
   copy.

## Risks

- **What it could break:** every `:full` device's panel row. A wrong y in
  `reach` (for example the label row instead of the value bottom) would
  overstate the room and let the outer value hit the arc on the 1030 and
  Explore 2 first: they have the least slack, 4.8 and 5.6 px.
- **Riskiest step:** T2's `reach` derivation. It is new geometry code on the
  `:full` path, which has so far been offsets only. Proof step 2 exists to
  catch it numerically before anyone looks at a screenshot.
- **Runtime null:** if any `:full` profile lacked `:panelStatFont`,
  `drawPanel` and `getFontHeight` would get `null`, which crashes at runtime
  but compiles cleanly. T1 covers all five `:full` branches, and proof step 3
  runs each one.
- **Cost:** +4 `drawText` per frame, 0 `drawArc`; negligible.

## Rejected alternatives

- **MAX marker on the arc:** rejected in the intent; it would also have
  needed a fixed power scale.
- **Quarter-point columns (0.75 / 0.25):** the four values would be evenly
  spaced with no grouping by panel, and the Explore 2 touches the arc.
- **Pair centred under the big value (`:panelLeftX`):** it hits the arc on
  every device, because the arc has curved in by the AVG row. The big value
  is moved over the pair instead.
- **Per-profile pixel offsets for the columns:** the derived `reach` needs no
  tuning for a new device and cannot drift from the arc geometry.
- **A second row for MAX:** the panel band has no vertical slack (1050 ~4 px
  overlap already, 850 recovered with -10).

## Implementation notes

- Implemented as planned (T1 `DeviceProfiles.mc`, T2 `DashView.mc`, T3
  `CLAUDE.md`). One detail beyond the plan: T2 truncates the label-top and
  value-bottom rows to whole pixels before scanning them. That makes `reach`
  up to 0.4 px larger than the spec's measurement (1050 173.3 vs 173.2, 1040
  105.7 vs 105.3), well inside the 1 px tolerance in Proof step 2.
- Runtime `reach` on the Explore 2 is 89.4: the `FONT_SMALL` row is 3 px
  shorter, as the plan predicted.
- T3 measured the 1030, 1030 Plus and 1030 Bontrager fonts as identical
  (xtiny 16, tiny 22, small 26, medium 29, large 48, numberMild 42,
  numberMedium 49, numberHot 66, numberThaiHot 81).
- Proof: `build-all.ps1` ALL 13 OK. Worst-case screenshots were taken on
  1050, 850, 1040, 1030 and Explore 2 (default, main = HR, main = power; no
  power meter and light background on a subset) and on the 840 / 830; no
  value touches the arc or a neighbour, and `:compact` is unchanged.
  Review round 1: accept (two minor findings, both fixed: comment wording in
  `computeFullLayout`, spec status line).
