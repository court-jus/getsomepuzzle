# Task completion checklist

A coding task in this repo is done when ALL of these pass (use `rtk` prefix):

1. `rtk flutter analyze` — zero issues (Project-level diagnostic: "No issues found!").
2. `rtk flutter test` — full suite green (currently ~1033 tests). If the change is UI-only, at minimum run the affected widget tests, e.g. `test/constraint_icons_ui_test.dart`; full suite is the CI gate.
3. If `.arb` files were touched: `rtk flutter gen-l10n` was run and its output committed (app_localizations*.dart regenerated).
4. Dev docs kept in sync: update the relevant `docs/dev/*.md` page when a documented surface/behavior changed (e.g. `puzzle_help.md`, `onboarding.md`, `ready_to_publish.md` checklists).
5. No stray/debug files: `rtk git status` shows only intended changes.