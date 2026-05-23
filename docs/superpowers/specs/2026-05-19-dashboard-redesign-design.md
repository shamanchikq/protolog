# Dashboard Redesign — "Lab Sheet" Direction

Date: 2026-05-19
Status: Approved for implementation
Source design: `ProtoLog_redesign/` (Protocol Tracker.html + screens-b.jsx)

## Scope

Rebuild the **Dashboard** tab to match the "Lab Sheet" visual direction provided in the redesign canvas. Ship the new app shell (top tabs + floating "+") alongside it. Calendar / Library / Reminders / Add-Injection screens are out of scope this session and continue to use their existing UI; only their access route changes (bottom nav → top tabs).

## Non-goals

- Light theme. Redesign defines a light palette; defer to a later session.
- Redesign of Calendar / Library / Reminders / Add-Injection.
- Settings affordance for protocol cycle (Week N / day Y of Z framing dropped).
- Changes to PK math, data models, persistence, notification scheduling.

## Design tokens (`lib/ui/theme.dart`, new)

Single `AppTheme` class exposing static const Colors and Google Fonts text styles.

**Palette (dark):**

| Token         | Hex        | Use                                             |
| ------------- | ---------- | ----------------------------------------------- |
| `bg`          | `#0B0C0E`  | Scaffold background                             |
| `surface`     | `#13151A`  | Cards                                           |
| `surface2`    | `#191C22`  | Active chip background, embedded bars           |
| `paper`       | `#F2E8D2`  | LoadHero left panel + Calendar today cell       |
| `paperInk`    | `#1A1612`  | Text on paper                                   |
| `border`      | `#23272F`  | Card borders                                    |
| `borderSoft`  | `#1B1E25`  | Inner dividers, grid lines                      |
| `fg`          | `#ECECEC`  | Primary text                                    |
| `fgMute`      | `#9AA0A8`  | Secondary text, tab labels                      |
| `fgDim`       | `#5C626C`  | Tertiary captions, axis ticks                   |
| `accent`      | `#7DD3D0`  | FAB, active tab underline, "on" toggle          |
| `accentDeep`  | `#3A6F6D`  | Active toggle track                             |
| `warm`        | `#E0B870`  | "Due" state, custom badge                       |
| `warn`        | `#D27A6B`  | "Overdue", negative delta                       |

**Typography** via `google_fonts`:
- Sans (default body): **Inter** weights 400/500/600/700.
- Serif (hero numbers only): **Fraunces** weights 400/500.
- Mono (numeric values, axis ticks, "21d back · 7d ahead" caption): **JetBrains Mono** weights 400/500/600.

**Geometry:**
- Sharp corners everywhere — no `BorderRadius`.
- 1px borders define cards; cards fill with `surface` on `bg`.
- 14px horizontal screen padding, 18px top, 90px bottom (FAB clearance), 18px gap between cards.

## App shell change

`_MainScreenState` in `lib/main.dart`:

- Remove `BottomNavigationBar` and its 5-item config.
- Tab indexing changes from 0–4 (with center "Add") to 0–3 (Today / Calendar / Library / Reminders). The Add action moves to a FAB.
- Each tab body is wrapped by a new `Scaffold`-like shell that renders the top-nav strip directly inside (matching the design — the strip is part of the screen, not a global app bar). The shell widget is `ProtoLogShell(activeTab, child)` in `lib/ui/widgets/top_nav.dart`.
- FAB rendered as a `Positioned` child inside each shell, bottom-right 18/18, 56×56, `accent` fill, opens `AddInjectionWizard` via a full-screen modal route. Wizard route unchanged.

Calendar / Library / Reminders bodies render their existing widgets unchanged inside the new shell — they will look visually inconsistent (still card-rounded, still dark-blue palette) until their own redesign sessions. This is acceptable for one or two sessions.

## Dashboard composition

`Dashboard` widget body (in `lib/main.dart`) becomes a vertical `Column` inside a `SingleChildScrollView`:

1. `LoadHero`
2. `PKChartCard`
3. `SwimlaneCard`

All three receive the same `ComputedGraphData` the dashboard already refreshes via `compute(calculateGraphData, input)`. No changes to data flow.

## `LoadHero` widget (`lib/ui/widgets/load_hero.dart`, new)

Two-column row, gridTemplateColumns `1.3fr / 1fr`, single 1px outer border.

**Left panel (paper):**
- Background: `paper`. Ink: `paperInk`.
- Decorative grid: SVG-equivalent painted via `CustomPainter` — 20 horizontal + 20 vertical lines, stroke `paperInk` opacity 0.05.
- Top label: "Total load" — Inter 11px, opacity 0.6.
- Big number: **current total active mg across all compounds** (sum of `calculateActiveLevel(c, now)` for every compound that has at least one in-window injection). Rendered Fraunces 48 weight 500 (integer) + 28 weight 400 (".X" fractional) + Inter 12 weight 400 "mg" suffix opacity 0.55.
- Tagline: `"Last 7 days · {arrow} {signed delta}"` Inter 11px, opacity 0.7.
  - Delta = `(avg active steroid mg, last 7 days) − (avg active steroid mg, days 8–21 ago)`, both computed by sampling `calculateActiveLevel` at daily intervals.
  - `arrow` is `↗` when delta ≥ +0.05, `↘` when delta ≤ −0.05, `→` (or omitted) otherwise.
  - Sign rendered as `+` for positive, `−` for negative, formatted to 1 decimal.

**Right panel (surface):**
- Top 3 compounds by current active mg (across all types). For each:
  - Inter 11px label: `"{base} · {esterCode}"` (e.g. "Test · Cyp"); when no ester, just base name.
  - Mono 11px value: current active mg rounded to integer.
  - 2px high bar: `surface2` track, filled `width = share_of_total * 100%` in compound color.

If fewer than 3 compounds active, render only what exists; if zero, render an empty placeholder ("No active compounds").

## `PKChartCard` widget (`lib/ui/widgets/pk_chart_card.dart`, new)

1px border, `surface` background.

- **Header** (14/16 padding): "Pharmacokinetics" Inter 13 weight 600 on left; range pills on right.
- **Pills**: existing 4 ranges (Zoom 7d / Standard 28d / Cycle 90d / Year 365d) styled per redesign — active pill has `surface2` background and `fg` color weight 600; inactive is transparent text `fgMute` weight 400. 4/10 padding, 4px radius. (Yes radius is allowed here specifically; the design uses radius 4 for pills only.)
- **Body**: existing `PKGraphPainter` rendered with `skipPeptides: true` and theme-driven colors. Injection markers stay (drawn on curves at `yLevel`). Right oral axis stays.
- Modification: add `skipPeptides` bool to `PKGraphPainter` constructor; when true, the painter does not draw the peptide swimlane section and the chart fills the full vertical area. All other math unchanged.

## `SwimlaneCard` widget (`lib/ui/widgets/swimlane_card.dart`, new)

A standalone Bateman-driven swimlane visualization for peptides + ancillaries.

**Timeline:** fixed 28-day window with 21 days of history + 7 days of future. Today cursor at 75% across (day 21 of 28). Origin is `now - 21 days at midnight`.

**Layout** (1px border, `surface`):

1. **Header row** (12/14 padding): "Peptides & ancillaries" Inter 13 weight 600; right caption "21d back · 7d ahead" Mono 10 `fgMute`.
2. **Day axis row** (8/14 padding, `borderSoft` divider above and below): same 3-col grid as lanes (94 / flex / 42), middle column has 5 mono 8.5px ticks at days 0/7/14/21/28 labeled "−21d" / "−14d" / "−7d" / **"NOW"** / "+7d". NOW is `accent` weight 600.
3. **Group sections** (one per group: "Peptides", "Ancillaries"):
   - Group label row: 10/14 padding, Inter 9.5 weight 600 uppercase letter-spaced 1.2, `fgDim`.
   - One lane per compound in the group, ordered by recency of last injection (most recent first).
4. **Legend row** (8/14 padding, `borderSoft` divider): gradient swatch + "active window", dot + "event", spacer, today cursor + "today". Inter 10 `fgMute`.

**Lane row** (6/14 padding):
3-col grid `94px / 1fr / 42px`, 10px gap.

- **Label column:**
  - Top row: type glyph (3×1px bar for window lanes / 5px dot for event lanes) in compound color + name Inter 11.5 weight 500 truncated.
  - Bottom row: sub Inter 9.5 `fgDim` 15px left-indent, e.g. "0.5 mg · weekly" or "250 mcg · daily" — derived as `"{dose} {unit} · {schedule_summary}"`. Schedule summary derived from injection cadence over the last 28 days (heuristic: if interval std-dev < 1d, "every Nd"; if doses always on same weekdays, list weekday codes; fallback "irregular").
- **Track column** (relative, height 26):
  - Week gridlines (vertical 1px) at days 7/14/21 in `borderSoft` opacity 0.7.
  - **Window lane**: behind-track bg (`bg` opacity 0.5), then gradient strip drawn via `CustomPainter` — 80 samples across the window of `calculateActiveLevel` (or equivalent compound-aware Bateman sum), max-normalized per lane, fill = `Color.fromRGBO(r, g, b, intensity)`. Track height 14, vertically centered.
  - **Event lane**: 1px baseline rule in `borderSoft` at vertical center.
  - **Dose markers**:
    - Window: 1×4px tick in lane color above the strip at each dose timestamp; future doses opacity 0.5.
    - Event: 6px filled dot in lane color at dose timestamp; future doses 5px outlined (border lane color, fill `surface`).
  - **Today cursor**: 1px vertical line in `fg` opacity 0.55, spanning 3px above and below the track (top:-3, bottom:-3).
- **Value column** (right-aligned):
  - Mono 11 weight 500: current active value at NOW. For window lanes, the bateman intensity (rounded to int if ≥100 else 1dp). For event lanes, time since last dose ("4h", "1d", "3d"). Renders empty string if no doses fall in window.
  - Inter 8.5 `fgDim`: unit, e.g. "mg", "IU", "ago".

**Lane classification heuristic** (in widget):
- `isWindow = compound.type == peptide && compound.halfLifeDays > 0.5 && compound.timeToPeakDays > 0`; ancillaries are window when same conditions hold; otherwise event.
- This is a runtime-only decision based on `CompoundDefinition` fields — no schema changes.

## Stats helpers (`lib/engine/dashboard_stats.dart`, new)

Top-level functions, isolate-safe (mirrors `compute_engine.dart` conventions):

- `double currentTotalActiveMg(List<CompoundDefinition>, List<Injection>, DateTime now)` — sum across compounds.
- `List<({CompoundDefinition c, double mg})> topActiveCompounds(...)` — sorted descending by current active mg, limited to N.
- `double averageActiveMgOverRange(CompoundType filter, List<CompoundDefinition>, List<Injection>, DateTime start, DateTime end, {int samplesPerDay = 1})`.
- `double deltaSteroidLast7vsPrior14(...)` — wrapper computing the LoadHero delta in one call.

All call into existing `calculateActiveLevel` from `compute_engine.dart` so the Bateman math is single-sourced.

## File layout

**New files:**
- `lib/ui/theme.dart`
- `lib/ui/widgets/top_nav.dart` (top tabs + shell wrapper)
- `lib/ui/widgets/protolog_fab.dart`
- `lib/ui/widgets/load_hero.dart`
- `lib/ui/widgets/pk_chart_card.dart`
- `lib/ui/widgets/swimlane_card.dart`
- `lib/engine/dashboard_stats.dart`

**Modified files:**
- `lib/main.dart` — replace BottomNavigationBar with new shell; replace Dashboard body with 3-card stack; remove the old in-line dashboard scaffolding that the new widgets supersede.
- `lib/ui/widgets/pk_graph_painter.dart` — add `skipPeptides` constructor flag.
- `pubspec.yaml` — add `google_fonts: ^6.x` (latest compatible with current SDK constraint).

**Untouched:**
- `lib/engine/compute_engine.dart`, `lib/models.dart`, `lib/data.dart`, `lib/utils.dart`.
- `lib/ui/views/add_injection_wizard.dart`, `lib/ui/views/compound_manager.dart`, `lib/ui/views/reminders_page.dart`.
- All notification / SharedPreferences code.

## Testing

After implementation:
1. `flutter analyze` — no new warnings/errors.
2. Hot-reload onto the running Pixel 6 emulator.
3. Click through all 4 top tabs — Today shows new dashboard; the other three open their existing screens (visually inconsistent, acceptable).
4. FAB opens AddInjectionWizard, complete a test injection, return to dashboard, verify LoadHero number updates.
5. Switch between range pills on PK chart — verify x-axis updates.
6. Verify swimlane gradient intensity changes when an injection is added/removed for a peptide.
7. Verify existing reminders fire (no regression in notification code).

## Open questions

None remaining at design time. Spec ready for implementation planning.
