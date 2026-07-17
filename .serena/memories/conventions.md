# getsomepuzzle — Conventions

## Code style & formatting

- **Formatter**: `dart format` is mandatory after editing any `.dart` file
- **Linting**: `flutter_lints` (via `package:flutter_lints/flutter.yaml`) with `avoid_print: ignore`
- **Imports**: use relative package imports (`package:getsomepuzzle/...`)

## State management

- No external state lib — `StatefulWidget` + `setState` exclusively
- App state lives in `_MyHomePageState` (main.dart); game state in `GameModel`

## Constraint contract (`Constraint` subclass in `lib/getsomepuzzle/constraints/`)

- `verify(puzzle)` → **false** only when constraint is **definitely violated** (now or unreachable). Incomplete-but-still-reachable returns **true**.
- `apply(puzzle)` → may be more aggressive than verify. Returns `Move` or `Move(isImpossible: this)`.
- `isCompleteFor(puzzle)` → grayout signal: return true only when no future play can make `apply` fire again.
- Every new constraint: paired regression tests (reachable-incomplete → verify true, unreachable-incomplete → verify false).

## Move system (`lib/getsomepuzzle/model/cell.dart`)

- `Move` is a sealed class with subtypes: `SetValue`, `RemoveOption`, `Impossible`.
- Pattern-match on subtype; accessor getters exist for test convenience.

## Testing

- Framework: `flutter_test`
- Each test must be necessary, clear, well-commented.
- Prefer edge cases and real bugs over happy paths already covered.
- Tests encode *why* behaviour matters, not just *what* it does.

## Localization

- ARB files in `lib/l10n/` (source: `app_en.arb`, targets: `app_es.arb`, `app_fr.arb`)
- After editing any ARB, run `flutter gen-l10n` to regenerate Dart code.
- Generated files (`app_localizations*.dart`) are committed.

## Naming

- Files: snake_case for `.dart` files
- Types: PascalCase
- Variables/functions: camelCase
- Constraint slugs: uppercase 2-letter codes (FM, PA, GS, ...)

## Git

- Tags auto-created by CI on master push (format: `vX.Y.Z` from pubspec.yaml version minus build number)
- CI commits use `github-actions[bot]`
