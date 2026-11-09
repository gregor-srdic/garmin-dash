# Intent: selectable metric for the main gauge

Status: **accepted 2026-11-09**

> dodaj nastavitev, ki bo omogočala, da se v glavnem gauge namesto hitrosti prikazuje power (oz. kadenca, če power ni na voljo) ali srčni utrip.
> v primeru, da je za glavni gauge izbrano nekaj drugega, naj se hitrost prikazuje na manjšem gauge, kjer se sicer prikazuje tista vrednost.

## Problem

The large central gauge always shows speed. A rider training to power or heart rate has to read their target metric off a small side gauge, while speed, which matters less to them on an interval or a climb, takes the most prominent spot on the screen. Today there is no way to change this.

## Proposed outcome

A new app setting, **Main Gauge**, with three values:

| Value | Main gauge shows | Small gauge that gives up its slot | That slot now shows |
|---|---|---|---|
| Speed (default) | speed (current behaviour, unchanged) | — | — |
| Power | power, or cadence when there is no power data (the same fallback the right gauge uses today) | right (PWR/CAD) | speed |
| Heart rate | heart rate | left (HR) | speed |

So the main and small gauges **swap**. No metric disappears and no metric appears twice.

Decided in brainstorming (2026-11-09):

1. **Crown AVG/MAX pair** shows AVG/MAX of the metric now in the main gauge (avg/max power, cadence or HR). It does not keep showing speed.
2. **Main arc colour** is the zone colour of the metric, as the small gauge colours it today. Cadence stays orange. When speed moves to a small gauge it keeps its current blue.
3. **Avg/max markers on the main arc** follow the metric in the main gauge and are still toggled by the existing `visualizeSpeedIndicator` setting. Accepted consequence: the power scale is FTP or the session max, whichever is higher, so once max power exceeds FTP the MAX marker sits at the end of the arc.
4. **All devices.** The setting applies to both `:full` and `:compact`. On `:compact` speed moves into the horizontal bar.
5. **Small gauge carrying speed** fills against `speedGaugeMax`. On `:full` its AVG row shows average speed. Its label is the speed unit.

## Affected users and systems

- **Riders:** anyone who installs Dash. The default stays Speed, so existing users see no change until they change the setting.
- **`DashView.mc`:** all four gauge draw paths (`drawSpeedGauge`, `drawPanels`, `drawCompactSpeedGauge`, `drawCompactBars`), plus new fields for max HR and max cadence (`info.maxHeartRate`, `info.maxCadence`).
- **Resources:** `properties.xml`, `settings.xml`, `strings.xml`.
- **Docs:** `readme.md` ("What's on screen") and `CLAUDE.md` (Architecture: the right panel is no longer always HR/PWR).

## Constraints

- No layout XML. Everything is drawn imperatively in the existing band functions (per `CLAUDE.md`).
- Read the setting in `readSettings()` and cache it, never on the 1 Hz path. A change must apply mid-ride through `onSettingsChanged()`.
- Keep the arithmetic in one place: `hrFillRatio` / `rightFillRatio` / zone colour already serve both render paths. The new speed ratio and the main-gauge ratio should use the same pattern rather than adding a third copy.
- Nullable metrics (HR, power, cadence) still print `"--"` when the sensor drops out, also in the main gauge.
- `:compact` text is at its limit: the crown pair is sized for a two-digit speed (`"88.8"`). A four-digit max power (`"1200"`) is wider and must be measured on the 840 and 830.
- Draw cost on the 830: no more `drawArc` calls per frame than today.
- Verification is by building for several devices (`-l 2`) and checking in the simulator. There is no test suite.

## Open questions (resolved 2026-11-09)

1. **Unit label under the main number:** `PWR` / `CAD` / `HR`, the same labels the small gauges use. When speed sits on a small gauge, its label is `KMH` / `MPH`.
2. **Four-digit max power in the `:compact` crown:** accept the overrun and document it beside the existing ones. No font change.
3. **Four-digit power in the main readout:** accept the overrun. No font step-down.
4. **Small speed gauge on `:full`:** the AVG row shows average speed.
5. **Naming:** "Main Gauge" with values Speed / Power (Cadence) / Heart Rate.
