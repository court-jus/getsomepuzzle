# Conventions

## Code style
- Dart: `analysis_options.yaml` enforced (flutter_lints defaults); use records `({String slug, …})`, switch expressions, collection-if/for spreads (`.indexed`).
- Widgets: `StatelessWidget` preferred; private helpers/constants get `_` prefix; class-per-concept files under `lib/widgets/` mirroring `lib/getsomepuzzle/` names.
- Long/mostly-verbatim doc comments on widgets explaining invariants and caller responsibilities (e.g. side effects belong to the caller, why a flag exists).

## UI patterns
- `AlertDialog` with title `Row[Icon, SizedBox(8), Expanded(Text)]`; per-surface accent via `Theme.of(context).extension<PuzzleColors>()!.dialogAccent`.
- Constraint sections shared via `ConstraintExplanationList` (in `new_constraint_dialog.dart`): icon+name header, explanation body; optional per-section buttons gated by flags (`showLearnMore`, `showSkipButton`).
- External links: `TextButton.icon` + `launchUrl(Uri, mode: LaunchMode.externalApplication)`; icon `Icons.open_in_new` for external-link affordance.
- URL constants: file-private `const _…BaseUrl`, one per file (help_page, stats_page, main.dart each define their own; no shared URL module).

## Localization
- New strings: add key+`@key`(description) to `app_en.arb` (template), plain value to `app_fr.arb`/`app_es.arb`, then run `flutter gen-l10n`. Getter names camelCase; description must be written for translators.
- Locale plumbing: `help_page.dart` receives `locale` param ('en'/'fr'/'es', from main.dart prefs "locale"); other widgets derive via `Localizations.localeOf(context).languageCode` with `'en'` fallback for anything else.
- ICU plurals for counts (e.g. `puzzleHelpIntro`, `learningPlayCount`).

## Dialogs & side effects
- Mandatory-read dialogs: `barrierDismissible: false`; optional reference dialogs: true.
- Dialog widgets stay dumb: callers perform persistence/side effects after dismissal.
- Set-based slug dedup for constraint lists (a puzzle repeats slugs across rules); merged row/column pairs collapsed before display.

## Docs
- `docs/dev/` mirrors subsystems one file each; update the relevant page when changing behavior of a surface (checklist in `docs/dev/index.md`; e.g. `puzzle_help.md`, `onboarding.md`, `ready_to_publish.md` checklist items).