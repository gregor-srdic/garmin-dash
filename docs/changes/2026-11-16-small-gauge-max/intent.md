# Intent: MAX value beside AVG on the small gauges

Status: draft — awaiting correction / acceptance.

Original request: *"kako in na katerih napravah oz. zaslonih lahko najbolje
prikažemo max vrednosti tudi v manjših dveh gauges (srčni utrip in
power/cadence)?"* — refined to: *"ne bi dodal markerja na sam gauge, ampak samo
prikaz številke poleg avg vrednosti"*.

## Problem

The main gauge shows both AVG and MAX for its metric, but the two small gauges
(heart rate on the left, power / cadence on the right in the default mode) show
only the current value and AVG. A rider who wants the ride's peak heart rate or
peak power has to look elsewhere.

## Proposed outcome

On the `:full` layout, each small panel shows the ride's MAX value as a number
**beside** its AVG value, in the same row — AVG and MAX side by side, each under
its own `AVG` / `MAX` label. Nothing is added to the arcs themselves: no MAX
marker, no change to the gauge scale.

The value shown follows whatever the slot displays (`leftMetric()` /
`rightMetric()`): max HR, max power, max cadence when there is no power data,
or max speed when `mainGauge` has moved speed into a small slot. The existing
`maxValue(metric)` / `maxString(metric)` already cover all of these.

## Affected users and systems

- **Devices that get the change (`:full`):** Edge 1050, 1060, 850, 550, 1040,
  1030 / 1030 Bontrager / 1030 Plus, Explore 2.
- **Devices that stay as they are (`:compact`):** Edge 840, 830, 540, 530. The
  zone-bar band has no row for it — `:compact` already drops the AVG HR and AVG
  power text for lack of room.
- **Code:** `drawPanel` in `source/DashView.mc`; possibly new keys in
  `source/DeviceProfiles.mc` if per-device tuning is needed.

## Constraints

- **No vertical growth of the panel band.** The panel band absorbs all slack in
  `:full`; the 1050 already has ~4 px of text-box overlap and the 850/550 was
  recovered with `:panelTextYOffset` -10. MAX goes into the existing AVG row,
  not into a new row.
- **Horizontal room is narrowest at the bottom of the panel**, where the arc
  curves in. Estimated from geometry (to be measured, not trusted): ~175 px
  per panel on the 1050, ~100 px on the 1040 / 1030, ~90 px on the Explore 2.
  Worst-case pair is a four-digit power, `"1250"`, beside a three-digit value in
  `FONT_MEDIUM` — on the Explore 2 that is ~85 px, at the limit.
- Widths must be measured in the simulator with a `(:debug)`
  `getTextWidthInPixels` print, per CLAUDE.md — font metrics are not derivable.
- **The default-mode rendering changes on purpose.** #14 treated
  "`mainGauge` = 0 renders unchanged" as the regression bar; this change moves
  the AVG value off the panel's centre line in the default mode too.
- No new `drawArc` calls; the 1 Hz path and draw cost stay as they are.

## Decisions

1. **Always shown, no setting** — like the AVG text today. The "Visualize
   average/max values" setting keeps controlling only the markers.
2. **`:compact` stays without MAX.** 840 / 830 / 540 / 530 are untouched.
3. **AVG on the left, MAX on the right, in both panels** — the same reading
   order on both sides, not mirrored.

## Open questions

1. **Explore 2 overflow** (carried to `spec.md`, decided after measuring). If
   `"1250"` beside `"188"` does not fit, what gives: a smaller font for that
   row on the Explore 2 only, or accept the rare four-digit overlap (as
   `:compact` already does for its crown)?
