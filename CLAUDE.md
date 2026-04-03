# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Get Some Puzzle is a cross-platform grid-based logic puzzle game built with Flutter (Dart) for the frontend and Python for puzzle generation. Players color cells black or white according to constraint rules (forbidden patterns, group sizes, parity, letter groups, quantity).

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
  - `generator.dart` — In-app puzzle generator (Dart port of Python algorithm)
  - `generator_worker.dart` — Background execution for generation (Isolate/web)
  - `settings.dart` — User preferences with enums: `ValidateType`, `ShowRating`, `ShareData`, `LiveCheckType`
- **`widgets/`** — UI layer: puzzle grid, cell rendering, puzzle selection (`open_page.dart`), puzzle generation (`generate_page.dart`), settings, stats, help, between-puzzle rating screen
- **`utils/`** — Platform-conditional sharing (`share_html.dart`/`share_io.dart`/`share_stub.dart`)
- **`l10n/`** — ARB translation files (en, es, fr). Localization configured in `l10n.yaml`.

### In-App Puzzle Generator (`lib/getsomepuzzle/generator*.dart`)

The app includes a Dart port of the Python generation algorithm:
- `generator.dart` — `PuzzleGenerator` class: generates puzzles using random grid fill + iterative constraint addition + solve loop. Also includes `findSolutions()` for uniqueness verification via backtracking.
- `generator_worker.dart` — Platform-adaptive background execution: uses `Isolate` on native, chunked async on web.
- `constraints/other_solution.dart` — `OtherSolutionConstraint`: excludes known solutions during uniqueness checking.

The `Puzzle` class (`puzzle.dart`) includes a full solver: `applyConstraintsPropagation()` (constraint propagation), `applyWithForce()` (forced deduction), `solve()` (combined loop), and `solveWithBacktracking()` (MRV backtracking). A shared `_applyLoop()` method is used by both the UI hint system (`applyAll()`) and the solver.

Generated puzzles are stored in a "custom" collection at `ApplicationDocumentsDirectory/getsomepuzzle/custom.txt` (or `SharedPreferences` on web).

### Python Puzzle Generator (`src/getsomepuzzle/`)

Separate Python engine for generating and solving puzzles:
- `engine/puzzle.py` — Puzzle representation
- `engine/generate.py` — Puzzle generation
- `engine/solver/` — Solving algorithms
- `engine/cli.py` / `engine/cli4.py` — CLI tools
- `engine/constraints/` — Constraint implementations (parallel to Dart versions)

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

## Testing Guidelines

- Each test must be **necessary** (not a duplicate of another test), **clear** (title and code match exactly), and **well commented** (explain what is being tested and why)
- Do not create temporary files to immediately read them back — test the logic directly
- Do not add boilerplate around already-tested functions — if `countSolutions` is tested in one file, don't retest it in another
- Prefer testing edge cases and real-world bugs over happy paths that are already covered
