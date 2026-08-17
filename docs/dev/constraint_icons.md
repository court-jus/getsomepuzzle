# Constraint icons

The same glyphs that appear on the board and in the in-editor
constraint-type picker are reused across the UI and exported as static
PNGs for surfaces that cannot run Flutter widgets.

## In the app

Every player-facing constraint slug has an entry in the UI registry
`lib/widgets/constraints/registry.dart` with a `buildPreview(fgcolor,
size)` callback. The shared `ConstraintIcon` widget wraps that callback:

- resolves the foreground from `Theme.of(context).colorScheme.onSurface`
  so the glyph adapts to light/dark themes;
- centers the preview inside a fixed square box so every slug renders at
  the same footprint.

`ConstraintIcon` is used by:

- `lib/widgets/new_constraint_dialog.dart` — the onboarding explanation
  modal (one icon per new slug);
- `lib/widgets/learning_page.dart` — the "Apprentissage" reference page
  (icon per row, dimmed + lock badge while the constraint is unseen);
- `lib/widgets/help_page.dart` — the constraints catalogue that replaced
  the old `## Constraints` prose section of `assets/help.{en,fr,es}.md`.

The catalogue uses the same localised strings as the onboarding dialog:
`constraintNameForSlug()` and `constraintExplanationForSlug()` (both
defined in the UI registry), so the two surfaces cannot drift apart.

The catalogue lists one row per *concept* in teaching order via
`constraintCatalogueSlugs()`: the strict-onboarding phase introducers
first (FM, NC, PA, CC, GS, EY, DF, LT, QA — the order the player learns
them), then every remaining slug in registry order. Row/column pairs
that share one explanation — RC/CC, JC/JR, RT/CT — are collapsed to a
single row (same pairing as the model registry's `mergedRuleGroups`),
so the help page no longer duplicates identical text. Each collapsed
pair uses a single orientation-neutral name key — `cells per line`
(RC/CC), `line majority` (JC/JR), `transition` (RT/CT) — so label and
explanation stay in sync with what the onboarding dialog shows.

The help-page markdown keeps a placeholder `## Constraints` heading
(localised per file); `HelpPage` splits the document around it
(`_splitAroundConstraints`) and inserts the widget catalogue between the
two markdown halves. `flutter_md` cannot render images, which is why the
per-constraint prose moved out of the markdown entirely.

## Static PNGs for the website

The website (`leveque.cc/www/getsomepuzzle`) cannot run Flutter
widgets. `integration_test/constraint_icons_test.dart` renders every
`constraintUIRegistry` entry to PNGs; `bin/build_constraint_icons.sh`
wraps it (headless CI machines get `xvfb-run` automatically):

```bash
bin/build_constraint_icons.sh
```

Output, committed to git under `assets/constraint_icons/` (not listed in
`pubspec.yaml` `assets:`, so it never ships in the app bundle):

- `assets/constraint_icons/<slug>.png`        — light theme, 64dp at 2× = 128px
- `assets/constraint_icons/<slug>-dark.png`   — same, dark theme

The PNGs are transparent-backed, so the website can drop them on any
surface.

## Regenerating

Run `bin/build_constraint_icons.sh` after:

- changing a preview widget in `lib/widgets/constraints/`, or
- adding a new constraint slug to `constraintUIRegistry`.

Requires a Linux Flutter desktop device (same requirement as the
marketing screenshots, see `marketing/README.md`).