# getsomepuzzle — source map & invariants

Flutter app `Get Some Puzzle`: fill a grid black/white (or 3-color) satisfying constraints.

## Top-level layout
- `lib/getsomepuzzle/` — engine: `model/`, `constraints/`, `generator/`, `autopilot/`, hint solver, `level.dart`.
- `lib/widgets/` — UI, dialogs, pages, constraint widgets.
- `lib/l10n/` — ARB templates and generated localization bindings.
- `bin/` — Dart CLI tools.
- `assets/` — puzzle collections and help/onboarding files.
- `test/` — unit/widget tests; `integration_test/` — device tests.
- `docs/dev/` — subsystem references.

## Invariants
- Constraint slugs include FM PA RC RT GS LT QA SY DF SH CC JC CH CT GC MJ NC EY IM JR BB SZ RE MI.
- UI strings come from constraint registry localization lookups.
- `Puzzle.addConstraint` aggregates same-key LT and SZ constraints and merges compatible PA constraints.
- `getGroups` returns cached sorted 4-connected same-colour groups; cell mutations invalidate the cache.
- CI runs `flutter test`; `flutter analyze` must stay clean.

## References
- Code style/l10n: `mem:conventions`.
- Commands: `mem:suggested_commands`.
- Done criteria: `mem:task_completion`.
- See `docs/dev/index.md`.