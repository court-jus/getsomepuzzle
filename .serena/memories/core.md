# getsomepuzzle — Core

A cross-platform logic-grid puzzle game (Flutter/Dart). Players fill cells black/white according to visual constraints (~15 types).

## Source map

```
lib/
  main.dart                   — App root, game state (_MyHomePageState)
  getsomepuzzle/
    model/                    — Puzzle, Cell, Database, GameModel, Settings, Stats, AppTheme, levels
    constraints/              — Constraint subclasses + registry, complicities (pair synergies)
    generator/                — In-app puzzle generator (Isolate/web worker)
    utils/                    — Connected-component groups, rotation, SAF
  widgets/                    — UI: puzzle grid, cell rendering, drawers, dialogs, pages
    constraints/              — Per-constraint widget renderers
    create_page/              — In-app puzzle editor
  utils/                      — Platform-conditional sharing (html/io/stub)
  l10n/                       — ARB files + generated Dart (en, es, fr)
bin/generate.dart             — CLI: generate/validate/sort puzzles
test/                         — Dart tests (flutter_test)
docs/dev/                     — Design docs per constraint, algorithm, hints, etc.
assets/                       — Puzzle data files (*.txt), help/privacy docs (en/es/fr .md)
src/                          — Stale Python (Beeware) — only pycache remains, no source
```

## Invariants

- No state management lib — `StatefulWidget` + `setState`.
- `dart format` required after any Dart file change.
- Constraint slugs (canonical): `FM`, `PA`, `GS`, `LT`, `QA`, `SY`, `DF`, `CC`, `GC`, `NC`, `EY`, plus `SH` (shape), `BB` (bounding box), `CH` (chain), `TR` (transition), `MJ` (majority), `CM` (column majority), `RM` (row majority), `RC` (row count). See `lib/getsomepuzzle/constraints/registry.dart`.
- Puzzle data format: single-line text, `v2_DOMAIN_WxH_state_CONSTRAINTS`.
- CI auto-tags on master push; builds APK, AAB, Windows, Web; deploys web to GitHub Pages.

## Key memories

- `mem:tech_stack` — SDK versions, dependencies, platform targets
- `mem:conventions` — code style, constraint contract, testing patterns
- `mem:suggested_commands` — dev/test/lint/build commands
- `mem:task_completion` — verification commands
