# getsomepuzzle — source map & invariants

Flutter app "Get Some Puzzle": fill a grid black/white (or 3-color) satisfying constraints. Repo root: /home/ghislain/perso/getsomepuzzle. Branch: develop.

## Top-level layout
- `lib/getsomepuzzle/` — engine: `model/` (puzzle, database, onboarding, constraint_progress), `constraints/` (one class per slug + engine registry), `generator/`, `autopilot/`, `hint_worker*.dart` (platform-conditional hint solver), `level.dart`.
- `lib/widgets/` — UI: `constraints/` (per-slug indicator widgets + UI registry with name/explanation lookups), dialogs (`new_constraint_dialog.dart` = onboarding "New rule!" modal, `constraint_help_dialog.dart` = in-game puzzle help, `onboarding_complete_dialog.dart`, `welcome_dialog.dart`), pages (`help_page.dart`, `learning_page.dart`, `open_page.dart`, `create_page/`), `main_drawer.dart`, `puzzle.dart`.
- `lib/l10n/` — ARB l10n (`app_{en,fr,es}.arb` + generated `app_localizations*.dart`). Template = `app_en.arb`. Regenerate with `flutter gen-l10n` (config in `l10n.yaml`).
- `bin/` — Dart CLI tools (generators, corpus scripts: `extract_onboarding.dart`, `maintain.dart`, `describe_puzzle.dart`, `query_corpus.dart`, `solve.dart`).
- `assets/` — puzzle collections (`1-easy.txt`…), help/privacy markdown (`help.{en,fr,es}.md`, `privacy.{en,fr,es}.md`), onboarding bank `1-easy_onboarding.txt`.
- `test/` — unit+widget tests; `integration_test/` — device tests (NOT run by CI), helpers in `integration_test/helpers/harness.dart`.
- `docs/dev/` — per-subsystem references mirroring the code; README before touching a subsystem. `docs/scenario/` — autopilot scenario files.

## Key invariants
- Constraint slugs: FM PA RC RT GS LT QA SY DF SH CC JC CH CT GC MJ NC EY IM JR BB. Row/column pairs merged for display: RC↔CC, JR↔JC, RT↔CT (`collapseMergedRules`/`constraintCatalogueSlugs` in `lib/widgets/constraints/registry.dart`).
- UI strings for constraints come from `constraintNameForSlug` / `constraintExplanationForSlug` (l10n keys `constraintExplain*`), shared by onboarding modal, puzzle-help modal, Learning page, help-page catalogue.
- Locale: 'en'|'fr'|'es', persisted by the app under prefs key `"locale"`; `HelpPage(locale:)` takes it as a widget param. `AppLocalizations.of(context)` gives the rest.
- Online docs: `https://leveque.cc/getsomepuzzle/doc/{en,fr,es}/index.html` (player guide) and `…/{en,fr,es}/<SLUG>.html` (per-constraint pages). Privacy policy hosted separately at `court-jus.github.io/getsomepuzzle/privacy.{locale}.html`. External links open via `url_launcher` `LaunchMode.externalApplication`.
- Onboarding: strict phases (`model/onboarding.dart`) introduce slugs in order FM NC PA CC GS EY DF LT QA …; `NewConstraintDialog` fires per unseen slug set, mandatory-read (`barrierDismissible: false`), side effects (`noteSeen`) applied by caller after dismissal.
- `flutter analyze` must stay clean; CI only runs `flutter test`.

## References
- Conventions for code style/l10n: `mem:conventions`.
- Commands: `mem:suggested_commands`.
- Done criteria: `mem:task_completion`.
- See also `docs/dev/index.md` (entry point to the dev docs) and `AGENTS.md` (RTK command prefix rule).