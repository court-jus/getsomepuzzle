# Keyboard shortcuts

Desktop keyboard control of an in-progress puzzle. All handling lives in
`_MyHomePageState` in `lib/main.dart`; there is no separate shortcut layer.

## Wiring

`build()` wraps the home `Scaffold` in a single
`Focus(autofocus: true, onKeyEvent: _handleKeyEvent)`. The grid cells are
`GestureDetector`s (not focus nodes), so primary focus stays on this node
during play and `_handleKeyEvent` receives the key events directly. Pushed
routes (settings, editor, open page) and the navigation drawer take focus
onto their own routes, so they naturally suppress these shortcuts while open.

`_scaffoldKey` (a `GlobalKey<ScaffoldState>`) lets the handler open and close
the drawer for the Menu shortcut without a `Scaffold.of(context)` lookup.

## Key map

`_handleKeyEvent` acts only on `KeyDownEvent` and ignores everything while
`!initialized || shouldChooseLocale`.

| Key | Action | Availability |
|-----|--------|--------------|
| `Esc` | Open / close the navigation drawer (Menu) | always |
| `P` | Pause / resume (`togglePause`) | `database != null` |
| `U` | Undo last move (`game.undo`) | playing, history non-empty |
| `R` | Restart — pause + confirmation overlay (`_confirmingRestart`) | playing, history non-empty |
| `H` | Show a hint (`showHelpMove`) | playing |
| `N` | Skip to next puzzle (`loadPuzzle(skipped: true)`) | playing |
| `Enter` / numpad `Enter` | Manual validate (`_manualValidate`) | playing, manual mode, grid complete |
| `Space` | Toggle `_removeOptionMode` (setValue ↔ removeOption) | playing, domain length > 2 |

`Esc` and `P` stay available while paused; the rest require
`playing = currentPuzzle != null && !paused && !betweenPuzzles`. Each branch
mirrors the enable condition of its topbar button.

## Notes

- `Space` is the 3-colour set/remove toggle, not pause — pause is `P`. On
  2-colour puzzles `Space` is ignored (the paint-bucket button is hidden too).
- `_manualValidate()` is the single source shared by the topbar Validate
  button and the `Enter` shortcut.
- A focused topbar button consumes `Enter`/`Space` itself (its own
  `ActivateIntent`) before the ancestor `Focus` sees them; single-letter
  shortcuts are unaffected.
- The player-facing list lives in `assets/help.{en,fr,es}.md` under the
  "Keyboard shortcuts" section.

Regression coverage: `integration_test/keyboard_shortcuts_test.dart`
(`U`, `P`, `Esc` against a real loaded puzzle).
