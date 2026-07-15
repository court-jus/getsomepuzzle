# Theming (Light / Dark mode)

## Overview

The app supports light and dark themes plus a "follow system" mode. Puzzle
colors are carried by a `ThemeExtension` so widgets read them off
`Theme.of(context)` instead of hardcoding `Color` literals.

**Files:**

- `lib/getsomepuzzle/model/app_theme.dart` — `PuzzleColors` extension, the
  `puzzleColorsLight` / `puzzleColorsDark` palettes, `lightTheme` / `darkTheme`
  `ThemeData`, and `resolveThemeMode`.
- `lib/getsomepuzzle/model/settings.dart` — `ThemeModeType` enum + persistence.
- `lib/main.dart` — wires `themeMode` into `MaterialApp` and reacts to changes.
- `lib/widgets/settings_page.dart` — the theme selector UI.

## `PuzzleColors` extension

`PuzzleColors extends ThemeExtension<PuzzleColors>` holds every puzzle-specific
color as a `final Color`, and implements the required `copyWith` and `lerp`
(component-wise `Color.lerp`, enabling animated theme transitions). Two `const`
instances are declared — `puzzleColorsLight` and `puzzleColorsDark` — and each is
attached to its `ThemeData` via `extensions: const [...]`.

Consume it in a widget with:

```dart
final pc = Theme.of(context).extension<PuzzleColors>()!;
```

Cell colors are resolved through the helpers `constraintColors` and
`oppositeColors` declared in `app_theme.dart`.

### Field groups

- **Cell colors:** `constraintColors`, `oppositeColors`.
- **Semantic:** `highlight`, `forbidden`, `mandatory`.
- **Grid:** `gridBorder`.
- **UI chrome:** `drawerHeaderBg`, `bottomBarBg`, `validateButtonBg`,
  `pauseOverlayBg`, `dialogAccent`.
- **Constraint states:** `constraintValid`, `constraintInvalid`,
  `constraintGrayed`.

## Theme mode setting

`ThemeModeType { system, light, dark }` is stored in `Settings.themeMode`
(default `system`), persisted under the `SharedPreferences` key
`settingsThemeMode` (round-tripped by enum `.name`).

`resolveThemeMode(ThemeModeType)` maps it to Flutter's `ThemeMode`. `main.dart`
holds the active mode in `_MyAppState._themeMode`, loads it once in `initState`
via `_loadThemeMode`, and exposes `setAppTheme` so the settings page can update
the whole app live. `MaterialApp` receives `theme: lightTheme`,
`darkTheme: darkTheme`, `themeMode: resolveThemeMode(_themeMode)`.

Note: `_loadThemeMode` reads `settingsThemeMode` directly from
`SharedPreferences` in addition to `Settings.load`, so the two paths must keep
the same key/default in sync.

## Coverage

Dark mode is wired through `PuzzleColors` across the puzzle surfaces:

- **Constraint validity indicators** — `constraintValid` / `constraintInvalid`
  in the constraint widgets (`bounding_box.dart`, `quantity.dart`, `chain.dart`,
  `group_count.dart`, `motif.dart`, `group_size.dart`, `symmetry.dart`,
  `eyes.dart`, `neighbor_count.dart`). `constraintInvalid` is `deepOrange` in
  light (matching the previous fixed color) and a soft red in dark.
- **Mandatory ring / background** — `mandatory` in the count and line/edge
  widgets, and in `different_from_painter.dart` (passed in as `fillColor` since
  a `CustomPainter` has no `BuildContext`).
- **Forbidden-motif background** — `forbidden` in `motif.dart` and the editor's
  `motif_dialog.dart`.
- **Dialog accent** — `dialogAccent` for the celebration/new-constraint icons in
  `welcome_dialog.dart`, `onboarding_complete_dialog.dart`,
  `new_constraint_dialog.dart`.
- **Highlight** — `highlight` is the single source everywhere. The constraint
  glyphs, the highlighted cell, the DF/IM/MJ painters and `to_flutter.dart` all
  read `pc.highlight`; painters that lack a `BuildContext` receive it as a
  constructor argument (`ImplicationPainter.highlightColor`,
  `MajorityZonePainter.highlightColor`, `DifferentFromPainter.highlightColor`,
  and `constraintToFlutter`'s required `highlightColor` parameter). The former
  `constants.highlightColor` / `forbiddenColor` / `mandatoryColor` literals have
  been removed from `constants.dart`.

The between-puzzles screen (`lib/widgets/between_puzzles.dart`) has no dedicated
background field: it is a `Stack` over the already-themed `Scaffold` background,
with semantic sentiment buttons (red = dislike, green = like) that intentionally
keep fixed colors.

When adding new themed surfaces, prefer a `PuzzleColors` field over a `Color`
literal so light and dark stay defined in one place; for a `CustomPainter`,
thread the color in from a caller that has a `BuildContext`.
