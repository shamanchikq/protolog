# ProtoLog 🧬

ProtoLog is a mobile tracking app built with **Flutter** for managing and visualizing protocols for anabolic compounds, peptides, and ancillaries. It estimates active blood-serum levels over time with a pharmacokinetic (PK) plotter based on the Bateman equation.

The interface uses a custom **"Lab Sheet"** design system (near-black surfaces + warm cream paper accents, top-tab navigation with a floating action button) applied across all four screens — **Dashboard, Calendar, Library, and Reminders**.

## 🚀 Features

- **Pharmacokinetic plotter**
    - Ester release curves via the Bateman equation.
    - Handles blends like **Sustanon** and **Tri-Tren**.
    - **Dual-axis graphing** — oral steroids scaled separately from injectables.
    - **Peptide / ancillary swimlanes** — active-window saturation bars or simple event markers.
- **Dose logging**
    - Steroids (injectable/oral), peptides, and ancillaries.
    - Concentration → dose volume calculator; precise date & time.
    - Logging from the Calendar pre-fills the day you have selected.
- **Compound library**
    - Pre-loaded compounds with accurate half-lives and ester weights.
    - Create custom compounds, or **edit built-ins** — behind a caution banner, with reset-to-default and an option to retroactively rewrite past logs.
- **Reminders**
    - **Interval** schedules (including fractional, e.g. every 3.5 days) anchored to a first dose, or **custom weekday** schedules.
    - Per-reminder state — **Overdue / Due / On / Paused** — with a next-dose estimate and a 7-day agenda strip.
    - **Log now / Skip** row actions; logging a dose can advance the matching reminder automatically.
    - Local notifications via `flutter_local_notifications` (timezone-aware).
- **Local persistence** — history, custom library, and reminders are saved on-device with `shared_preferences`.

## 🛠️ Project Structure

State is managed with `setState` + `shared_preferences` (no external state-management package). PK math lives in top-level functions so it can run inside `compute()` isolates.

- `lib/main.dart` — entry point and `MainScreen` shell (tab routing, dashboard body, persistence, notification scheduling).
- `lib/models.dart` — data models, enums, and JSON serialization.
- `lib/data.dart` — static compound library, ester definitions, blend constants.
- `lib/utils.dart` — small shared helpers (date formatting, etc.).
- `lib/engine/` — pure, unit-tested logic:
    - `compute_engine.dart` — Bateman PK math (isolate-safe).
    - `dashboard_stats.dart` — active-load sum, trend, lane sampler.
    - `library_stats.dart` — catalog, protocol, and display helpers.
    - `compound_edits.dart` — retroactive snapshot rewrite for edited compounds.
    - `reminder_schedule.dart` — next occurrence, state, advance, schedule formatting, week agenda.
- `lib/ui/theme.dart` — "Lab Sheet" design tokens (palette, fonts, per-compound colors).
- `lib/ui/widgets/` — shared components: `ProtoLogShell`, `LoadHero`, `PKChartCard`, `SwimlaneCard`, `PKGraphPainter`, the `Lab*` primitives, `LibrarySection`, `LibraryRow`.
- `lib/ui/views/` — full-screen views: `CalendarPage`, `LibraryPage`, `CompoundDetailPage`, `CompoundEditorPage`, `RemindersPage`, `ReminderEditorPage`, `AddInjectionWizard`.

See [`CLAUDE.md`](CLAUDE.md) for architecture details and conventions.

## 🧪 Tests

```
flutter test test/engine    # pure-logic unit tests (PK, stats, schedule, edits)
flutter analyze             # static analysis
```

The `test/engine/` suites cover the engine layer; the views have lightweight widget smoke tests under `test/`.

## 📦 Getting Started

1. **Prerequisites:** Install the [Flutter SDK](https://docs.flutter.dev/get-started/install).
2. **Install dependencies:**

    ```
    flutter pub get
    ```

3. **Run the app:**

    ```
    flutter run
    ```

    *For a release build on Android:*

    ```
    flutter run --release
    ```

## 📱 Dependencies

- `flutter`: SDK
- `shared_preferences`: local storage for persistence.
- `flutter_local_notifications` + `timezone`: scheduled, timezone-aware dose reminders.
- `google_fonts`: Inter / Fraunces / JetBrains Mono for the "Lab Sheet" UI.
- `flutter_launcher_icons`: (dev) app icon generation.

## 🎨 Customization

- To modify default compounds, edit `BASE_LIBRARY` in `lib/data.dart` — or edit built-ins in-app.
- PK math (half-life → active level) lives in the top-level functions in `lib/engine/compute_engine.dart`.
- Visual tokens (palette, fonts, per-compound colors) live in `lib/ui/theme.dart`.
