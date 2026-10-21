# Intent: power training metrics and W′ balance in the FIT file

Status: **Accepted 2026-10-21** (open questions resolved as proposed). Date: 2026-10-21. No ticket.

## Problem

Dash shows live and average power but nothing a structured-training rider uses to pace or
judge a ride: no Normalized Power, Intensity Factor, TSS, kJ, and in particular no W′ balance
(how much anaerobic capacity is left). Riders who want these today run a second data field or
a different app. These are also the features riders are most likely to pay for, so they are the
core of a possible paid tier later.

## Proposed outcome

1. **On screen (`:full` layout only).** A new setting, "Power panel stat", picks what the row
   under the power gauge shows: AVG power (default, today's behaviour), NP, W′bal %, TSS, IF
   or kJ. Layout geometry does not change. The `:compact` screen (830/840/530/540) stays
   exactly as it is.
2. **In the FIT file (all devices).** W′ balance is recorded every second, so Garmin Connect
   draws it as a chart after the ride. The session and each lap also record the lowest W′ balance
   reached.
3. **Settings.** New CP (0 = use FTP) and W′ (joules) settings, alongside the existing FTP setting.
4. **Packaging.** Everything ships in Dash itself, switched on for everyone. The code is kept
   self-contained (one new class) so it can be moved behind a Pro build later without
   rewriting it.

Success looks like this: on a power ride, NP/IF/TSS on screen agree with the Edge's native values
to within a few percent; W′bal goes down above CP and recovers below it; and the W′bal chart shows up
in Garmin Connect. On a ride with no power meter, nothing changes and the ride's Connect page
shows no empty W′bal chart.

## Affected users and systems

- Riders with a power meter on any `:full` device: the new setting and the panel row.
- Every rider: one new permission (`FitContributor`) on the store listing, and three new settings.
- Garmin Connect: one new chart and two new summary values per activity.
- Code: `DashView.mc`, a new `PowerMetrics.mc`, resources, `manifest.xml` and `CLAUDE.md`.
  This is the first time the repo has unit tests.

## Constraints

- CIQ 3.2 minimum: any API not available at 3.2 must be guarded with `has`.
- Nothing new on the 1 Hz path that reads settings or Storage (see `CLAUDE.md` conventions).
- `:full` geometry is tuned to the pixel, so the new values must fit the existing AVG slot. No new
  profile keys.
- `:compact` must not change: its overrun tables were measured and should not have to be redone.
- The Edge already writes NP, IF, TSS and work to the FIT session natively. Dash must not write
  duplicates of them.

## Open questions

1. When the field is recreated mid-ride (crash, app update), the accumulators restart from zero.
   Is that acceptable for v1, or should they be persisted to Storage? *Proposed: accept it for
   v1.*
2. Should negative W′bal (CP/W′ set too low) show as a negative %, or be clamped at 0%?
   *Proposed: show it as negative. It tells the rider their settings are wrong.*
3. VAM and grade in the FIT file were listed in the original idea. *Proposed: out of scope.*
   Grade is already recorded natively, and VAM belongs with the climb-view idea.
