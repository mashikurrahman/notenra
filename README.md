# Notenra

**Notenra** is the clinician-facing mobile app for ambient clinical documentation:
record a consultation, a scribe writes the note, the clinician reviews, edits or
approves it. Flutter, Android + iOS.

- Android application id / iOS bundle id: `com.notenra.notenra`
- Backend: the Anot Health REST API (`https://app.anot.health/api` by default —
  see `lib/api/api_config.dart`). The **backend is unchanged**; only the app's
  own identity was rebranded.

## App structure

Three tabs, ordered by how often a clinician needs them:

| Tab | Screen | Purpose |
| --- | --- | --- |
| **Today** | `lib/screens/today_screen.dart` | Home. Who's next (with the record action), what's waiting on you, what's left of the day. |
| **Schedule** | `lib/screens/patient_list_screen.dart` | Day-by-day planning: browse days, search, add and reschedule patients. |
| **Notes** | `lib/screens/review_queue_screen.dart` | Note history and work queue, filtered by workflow stage. |

Pushed from there: `patient_visit_screen.dart` (the recorder),
`note_review_screen.dart` (read / edit / request changes / approve),
`add_patient_screen.dart`, `profile_screen.dart`.

## Design system

Everything visual is defined in four places — screens compose from these rather
than styling themselves:

- `lib/theme.dart` — the `Nx` token set (colour, spacing, radius, elevation,
  gradients) and `buildNotenraTheme()`.
- `lib/widgets/nx.dart` — shared primitives: `NxCard`, `StatusPill`,
  `SectionHeader`, `NxBanner`, `NxEmptyState`, `NxAvatar`, `NxPillButton`.
- `lib/widgets/notenra_header.dart` — `NotenraHeader` (and `.titled`), the brand
  gradient panel every screen is topped with.
- `lib/status_ui.dart` — the single mapping from `VisitStatus` to its label,
  colour and icon, so a note's state reads identically on every screen.

Colour rules worth knowing: **blue** (`Nx.primary`, the logo blue) is structure
and navigation; **green** (`Nx.accent`, the pulse in the mark) means live capture,
"ready for you", and approval; **red** is reserved for real failures and the stop
control.

## Brand assets

`assets/images/notenra_logo.svg` and `notenra_mark.svg` are the source of truth.
The PNGs the app ships are rendered from them:

```bash
node tool/render_brand.js          # logo + mark + launcher-icon source
node tool/render_launch_images.js  # native (pre-Flutter) launch screens
dart run flutter_launcher_icons    # platform launcher icons
```

Both scripts rasterize via headless Chrome, so there's no native SVG toolchain to
install. Set `CHROME=/path/to/chrome` to override the browser.

## Running

```bash
flutter pub get
flutter run
flutter analyze
flutter test
```

Release signing for Android reads `android/key.properties` (not committed); a
checkout without it falls back to debug signing so the project still builds.
iOS release/TestFlight builds run on Codemagic — see `codemagic.yaml` and
`iOS_SETUP.md`.
