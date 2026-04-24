# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Get Some Puzzle is a cross-platform grid-based logic puzzle game built with Flutter (Dart). Players color cells black or white according to constraint rules (forbidden patterns, group sizes, parity, letter groups, quantity).

## Build & Run Commands

```bash
# Install dependencies
flutter pub get

# Run the app (debug)
flutter run

# Build targets
flutter build apk --release                        # Android
flutter build web --base-href=/getsomepuzzle/       # Web (GitHub Pages)
flutter build windows                               # Windows
flutter build linux                                 # Linux
flutter build macos                                 # macOS
flutter build ios                                   # iOS

# Run tests
flutter test                    # All tests
flutter test test/widget_test.dart  # Single test file

# Analyze code
flutter analyze
```

## Architecture

### Flutter App (`lib/`)

- **`main.dart`** — App root and main game state (`_MyHomePageState`). Manages puzzle lifecycle, periodic stats saving (60s interval), optional network telemetry, and locale support (en/es/fr).
- **`getsomepuzzle/`** — Core game logic:
  - `puzzle.dart` — `Puzzle` class (grid state, constraint checking, hint system via `findAMove()`), `Stats`, `PuzzleData`
  - `database.dart` — `Database` class loads puzzles from `assets/default.txt`, `assets/tutorial.txt`, and local `custom.txt`, handles filtering (`Filters`), playlist management, and stats persistence
  - `constraint.dart` — Base `Constraint` and `CellsCentricConstraint` classes
  - `constraints/` — Implementations: `groups.dart`, `parity.dart`, `symmetry.dart`, `motif.dart`, `quantity.dart`, `other_solution.dart`
  - `generator.dart` — In-app puzzle generator
  - `generator_worker.dart` — Background execution for generation (Isolate/web)
  - `settings.dart` — User preferences with enums: `ValidateType`, `ShowRating`, `ShareData`, `LiveCheckType`
- **`widgets/`** — UI layer: puzzle grid, cell rendering, puzzle selection (`open_page.dart`), puzzle generation (`generate_page.dart`), settings, stats, help, between-puzzle rating screen
- **`utils/`** — Platform-conditional sharing (`share_html.dart`/`share_io.dart`/`share_stub.dart`)
- **`l10n/`** — ARB translation files (en, es, fr). Localization configured in `l10n.yaml`.

### In-App Puzzle Generator (`lib/getsomepuzzle/generator*.dart`)

The app includes a puzzle generation engine:
- `generator.dart` — `PuzzleGenerator` class: generates puzzles using random grid fill + iterative constraint addition + solve loop. Also includes `findSolutions()` for uniqueness verification via backtracking.
- `generator_worker.dart` — Platform-adaptive background execution: uses `Isolate` on native, chunked async on web.
- `constraints/other_solution.dart` — `OtherSolutionConstraint`: excludes known solutions during uniqueness checking.

The `Puzzle` class (`puzzle.dart`) includes a full solver: `applyConstraintsPropagation()` (constraint propagation), `applyWithForce()` (forced deduction), `solve()` (combined loop), and `solveWithBacktracking()` (MRV backtracking). A shared `_applyLoop()` method is used by both the UI hint system (`applyAll()`) and the solver.

Generated puzzles are stored in a "custom" collection at `ApplicationDocumentsDirectory/getsomepuzzle/custom.txt` (or `SharedPreferences` on web).

### Dart CLI (`bin/generate.dart`)

Command-line tool for batch puzzle operations (pure Dart, no Flutter dependency):
- Generate puzzles: `dart run bin/generate.dart -n 100 -o puzzles.txt`
- Validate puzzles: `dart run bin/generate.dart --check assets/default.txt`
- Sort by difficulty: `dart run bin/generate.dart --read-stats <stats_dir>`

### Puzzle Data Format

Puzzles are stored as single-line text in `assets/default.txt` (~5000 puzzles):
```
v2_12_4x7_2210000010000000212100200100_FM:12.21;PA:25.top;GS:1.2...
```
Fields: version, domain, dimensions, cell state, constraint definitions.

## Key Conventions

- Linting uses `flutter_lints` with `avoid_print` disabled (see `analysis_options.yaml`)
- State management is via StatefulWidget (`setState`) — no external state management library
- CI is GitHub Actions (`.github/workflows/ci.yml`) — manual trigger, builds APK/Windows/Web

## Coding Rules

- **Always run `dart format` after modifying Dart files**

## Constraint invariants

When adding or modifying a `Constraint` subclass in
`lib/getsomepuzzle/constraints/`:

- **`verify(puzzle)`** returns `false` **exactly** when the current state
  already violates the constraint — either directly (broken *now*) or by
  making future satisfaction unreachable. An incomplete-but-still-reachable
  state returns `true`. Do not import `apply()`-flavoured forcing conditions
  (e.g. `have + free == target`) into `verify`: those are deduction
  conditions, not violation conditions.
- **`apply(puzzle)`** may be more aggressive than `verify` about forcing
  cells. It returns a `Move` or `Move(..., isImpossible: this)` on
  contradiction. It must not report a cell value that the current state
  already contradicts.
- **`isCompleteFor(puzzle)`** is the grayout signal: return `true` only
  when no future play can ever make `apply` fire again.
- Every new constraint needs paired regression tests: a reachable-but-
  incomplete state → `verify == true`, an unreachable-but-incomplete state
  → `verify == false`. See `NeighborCountConstraint.verify` in
  `test/constraints_test.dart` for a minimal template.

## Testing Guidelines

- Each test must be **necessary** (not a duplicate of another test), **clear** (title and code match exactly), and **well commented** (explain what is being tested and why)
- Do not create temporary files to immediately read them back — test the logic directly
- Do not add boilerplate around already-tested functions — if `countSolutions` is tested in one file, don't retest it in another
- Prefer testing edge cases and real-world bugs over happy paths that are already covered
