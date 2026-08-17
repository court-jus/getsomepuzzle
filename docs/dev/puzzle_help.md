# Puzzle help

In-game reminder of the rules used by the current puzzle. Players
coming back to the game after a while do not remember every
constraint; the top bar carries a **help** button (next to the hint
button) that opens a scrollable modal listing the constraints of the
puzzle currently on screen, with the same per-constraint explanations
as the onboarding modal (`NewConstraintDialog`).

## Current feature

- **Entry point**: an `IconButton` in the top bar (`AppBar.actions` in
  `lib/main.dart`), placed immediately before the hint (lightbulb)
  button. Same visibility guard as the hint button:
  `game.currentPuzzle != null && !shouldChooseLocale`. The button is
  always enabled while a puzzle is shown — it is pure reference
  material, unlike the hint button whose enablement depends on the hint
  stage.
- **Modal**: a dismissible `AlertDialog` titled **"Puzzle help"**
  ("Aide du puzzle" / "Ayuda del puzzle"), implemented in
  `lib/widgets/constraint_help_dialog.dart`.
- **Body**, in order:
  1. an intro paragraph naming the number of distinct constraint types,
     e.g. *"This puzzle uses 3 constraints, here is a quick reminder of
     them."* (pluralised with the count);
  2. one section per constraint, exactly like the onboarding modal: the
     constraint icon, the localised constraint name as a header, then
     the localised explanation paragraph.
- **Scrolling**: the body is wrapped in a `SingleChildScrollView`, so
  puzzles with many constraints (e.g. 5+ types) stay readable on small
  screens. Same pattern as `NewConstraintDialog`.
- **Dismissal**: `barrierDismissible` stays at the default (`true`) —
  this is an optional reference dialog, unlike `NewConstraintDialog`
  whose mandatory-read semantics require `barrierDismissible: false`.
  Closing is done by tapping outside or via a single OK action.

## How it works

### Building the slug list

The top-bar handler `_showConstraintsHelp` in `main.dart` reads the
current puzzle's regular constraints from
`game.currentPuzzle!.constraints` (`List<Constraint>` in
`lib/getsomepuzzle/model/puzzle.dart`); each constraint exposes its
`slug` getter. The slugs are filtered for empty entries (the base
`Constraint.slug` defaults to `''`) and collapsed via
`collapseMergedRules` (below) before the modal is shown.

Using the parsed constraint list instead of re-parsing the v2 line has
three consequences:

- `Puzzle` already aggregates duplicate same-type entries while parsing
  (LetterGroup merge, Parity same-axis merge), so the slug set matches
  what the player actually sees on the grid.
- The legacy tutorial `TX:` slug is dropped at parse time (puzzle.dart),
  so it never leaks into the modal.
- Complicities (`puzzle.complicities`) are deliberately **not**
  listed — they are cross-constraint deductions, not player-facing
  rules.

### Counting "constraints"

The modal counts **distinct constraint types** (unique slugs after
merging row/column pairs), not raw rule entries. A puzzle declaring two
`FM:` rules uses 1 constraint type. This matches the dedup semantics of
`NewConstraintDialog` (which renders each slug section once per puzzle).

### Merging row/column pairs

`RC`/`CC`, `JR`/`JC` and `RT`/`CT` are the same concept seen from a
different axis; they are collapsed to a single display slug so the
player is not shown the same explanation twice with different headers.
The collapse is done through the shared helper `collapseMergedRules` in
`lib/getsomepuzzle/constraints/registry.dart` (the reverse of the
existing `expandMergedRules`): `RC→CC`, `JR→JC`, `CT→RT`, unmapped
slugs pass through unchanged.

### Reuse of explanation text

Names come from `constraintNameForSlug` and bodies from
`constraintExplanationForSlug` (both in
`lib/widgets/constraints/registry.dart`), the exact functions used by
the onboarding modal and the Apprentissage page. Each section also
renders the constraint's icon through `ConstraintIcon` (same file),
matching the onboarding modal. The per-section rendering itself is
shared through the `ConstraintExplanationList` widget in
`lib/widgets/new_constraint_dialog.dart`, used by both
`NewConstraintDialog` and `ConstraintHelpDialog` — one source of truth,
no drift between the two surfaces. The one deliberate divergence: the
onboarding modal passes `showLearnMore: true`, so each of its sections
additionally renders a "Learn more" button opening the detailed online
explanation page for that slug
(`https://leveque.cc/getsomepuzzle/doc/{en,fr,es}/<SLUG>.html`) in the
system browser; the puzzle-help modal stays a pure in-app reminder.

## Localization

Three keys in `lib/l10n/app_en.arb`, `app_fr.arb`, `app_es.arb`
(bindings regenerated with `flutter gen-l10n`):

| Key               | Type  | Purpose                                      | EN example                                                       |
| ----------------- | ----- | -------------------------------------------- | ---------------------------------------------------------------- |
| `tooltipPuzzleHelp` | plain | Tooltip of the top-bar button                | `Puzzle help` (`Aide du puzzle` / `Ayuda del puzzle`)            |
| `puzzleHelpTitle`   | plain | Modal title                                  | `Puzzle help` (`Aide du puzzle` / `Ayuda del puzzle`)            |
| `puzzleHelpIntro`   | plural (`int count`) | Intro paragraph before the rule list | `This puzzle uses {count, plural, =1{1 constraint, here is a quick reminder of it.} other{{count} constraints, here is a quick reminder of them.}}` |

The intro uses ICU plural placeholders (same mechanism as
`statsImportSuccess` / `learningPlayCount` in the ARB files).

## Outside of this feature

- Complicity deductions (`GS+QA`, `SY+FM`, …) are not listed in the
  modal — they are engine-internal cross-rule effects, not constraints.
- General "how to play" help is a separate surface: `HelpPage`
  (`lib/widgets/help_page.dart`, menu entry "Help"). It carries a
  "Visit online player guide" button opening
  `https://leveque.cc/getsomepuzzle/doc/{en,fr,es}/index.html` in the
  system browser, next to the existing privacy-policy link.
- The Apprentissage page's per-rule "Refresh my memory" button is
  independent: it re-opens `NewConstraintDialog` per slug.