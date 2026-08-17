# Commands (run from repo root)

All shell commands must be prefixed with `rtk` per AGENTS.md (token-optimized passthrough; e.g. `rtk git diff`). Use `workdir=/home/ghislain/perso/getsomepuzzle`.

- Analyze: `rtk flutter analyze` (must be clean).
- Test (unit+widget, what CI runs): `rtk flutter test` (≈1000+ tests, ~30s; failure-only output via rtk).
- Single test file: `rtk flutter test test/<name>.dart`.
- Integration tests: `rtk flutter test integration_test/<name>_test.dart -d linux` (needs a device/display; not part of CI — skip unless explicitly asked).
- Regenerate l10n bindings after editing `.arb` files: `rtk flutter gen-l10n` (uses `l10n.yaml`).
- Solvers/descriptors: `dart run bin/solve.dart <url|v2>`, `dart run bin/describe_puzzle.dart`, `dart run bin/query_corpus.dart --playlist N`.
- Corpus maintenance: `dart run bin/maintain.dart` (6-step pipeline incl. `extract_onboarding.dart`), `dart run bin/onboarding_stats.dart`, `dart run bin/check_phase_coverage.dart`.
- Git: `rtk git status`, `rtk git diff`, `rtk git log` (rtk filters save context).
- Serena memory integrity: `serena memories check` from project root.