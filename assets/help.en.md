# Get Some Puzzles

In this game, your aim is to color the cells of the grid in black or white.

To know which cell has to be which color, you have to follow some constraints (rules are explained below).

Click (or touch on mobile) a cell to change its color. A click cycles through colours: free → black → white → free. On desktop, right-click cycles in the opposite direction (free → white → black → free); on mobile, a long press does the same. Dragging paints several cells in a row with the cycle's colour.

Some puzzles use a third colour, purple, with small coloured dots underneath the free cells showing which colours are still possible. On those puzzles the cycle includes purple: a click is free → black → white → purple → free, and a right-click (or long press) is free → purple → white → black → free — so a single right-click is enough to reach purple.

Some cells can be already filled and you won't be able to change them, they are indicated by a thicker inside border.

You will not be shown when you make a mistake but when the grid is filled, your solution is checked. If you won, another puzzle will start immediately. If you made a mistake, the corresponding constraint will be highlighted and you will be able to change your solution.

If you are stuck, several buttons are available in the top bar: **Hint** (the lightbulb icon, see the Hints section below), **Undo** (reverts your last move), **Restart** (resets the grid to its initial state) and **Pause**. In manual validation mode, a **Validate** button on a green background also appears once the grid is filled.

While playing, your timing is recorded (see the Stats section below). If needed, the game can be paused and resumed.

There are about 25,000 puzzles bundled within the app. The puzzles you already solved won't show up anymore, and you'll see your progress below the puzzle.

The main menu (icon in the top-left) also offers, while a puzzle is in progress: **Next puzzle** (skip to the next one), **Save progress** (set this one aside in a dedicated playlist to resume later) and **Share puzzle** (send the current puzzle to someone).

## Learning

When you launch the game for the first time, a learning sequence introduces the constraints one at a time. Each new rule is shown in a short dialog the first time you meet it, and the game then keeps offering puzzles centered on that rule until you have played enough of them (5 puzzles by default) before moving on to the next one. You can skip the whole sequence at any time with the "Skip learning" button in the rule dialog, or restart it from scratch from the Settings page.

The **Learning** page, reachable from the main menu, lists every constraint with its description and the date you first met it. The "Refresh my memory" button next to each rule launches a short playlist of puzzles centered on that rule — handy to come back to a constraint you have not seen in a while.

## Constraints

## The Open page

The Open page is where you pick what to play. At the top, the *Collection* dropdown lists the difficulty levels (Easy → Mad), followed by your own puzzles and any playlists you have created. Next to it, the `+` button creates a new playlist, the file button imports puzzles from a file, and the trash button deletes the current playlist if you own it.

The *Shuffle* toggle plays puzzles in random order. Below it, filters let you narrow the list: grid size, the constraint types you want to see or avoid, and whether to keep puzzles you have already played or skipped. The number shown above the Play button tells you how many puzzles match the active filters, and a small reset button next to each filter brings the default value back.

## Custom puzzles

### Generating puzzles

Open the menu and tap "Generate" to make new puzzles on the fly. Pick the grid dimensions, the constraint types to include or exclude, a time limit per puzzle, and how many puzzles to produce. Choose the playlist that will receive them, then tap "Generate" — the progress bar shows how many have been made. Generation runs in the background; you can stop early at any time and keep what has been produced so far.

### Creating puzzles

Open the menu and tap "Create" to design your own puzzle by hand. Pick the grid dimensions and tap "Start" to enter the editor. Tap a cell to open a menu that lets you fix it black or white, or attach a constraint centered on that cell; the added constraint appears, and you can tap it to remove it. The app tries to solve the puzzle as you make changes. Cells with a green border can be found by direct reasoning, those with an orange border by elimination. The bottom bar shows the current dimensions, the number of constraints, and a rough difficulty score. "Test" lets you play through the puzzle to check it works, and "Save" stores it in the chosen playlist.

### Playlists

Generated and created puzzles are saved to playlists. The default playlist is "My puzzles", but you can create your own playlists from the Open page. You can also import puzzles from a file.

## Hints

If you get stuck, the hint button gives you a progressive nudge — each tap reveals a little more. From the settings menu, you can choose how the game helps you.

The first tap is the same in both modes:

- If you've made a mistake, it highlights the broken constraint, or the wrong cell when no constraint catches it directly.
- If everything you've filled so far is correct, it just confirms it.

What the next taps do depends on the mode you've chosen.

### Deducible cell

The default mode. After the error check, the next taps walk you through one specific deduction:

- Second tap: highlights a cell you can deduce.
- Third tap: also highlights the constraint that justifies the deduction, with an arrow linking the two.
- Fourth tap: fills the cell in for you.

Useful when you want a small push without spoiling the rest: stop at the second tap if you'd rather find the reason yourself.

### Add constraint

Instead of pointing at a cell, the second tap adds a brand-new constraint to the puzzle. The new rule is consistent with the solution and gives you extra information to work from — the puzzle becomes easier without anyone telling you which cell to fill.

After a constraint is added, the next tap restarts the cycle at the error check.

## Keyboard shortcuts

On desktop, these keys control a puzzle while you play:

- **U** — undo the last move
- **R** — restart the puzzle
- **P** — pause or resume
- **H** — show a hint
- **N** — skip to the next puzzle
- **Enter** — validate (when manual validation is on)
- **Esc** — open the menu
- **Space** — on 3-colour puzzles, switch between setting a colour and removing an option

## Settings

The settings page tunes how the game checks your work and asks for help.

**Language**: choose the app's display language (English, French or Spanish).

**Theme**: choose between Light, Dark, or follow the system setting (default).

**Validation**: choose whether the grid is checked manually (you tap a button) or automatically (as soon as it is fully filled).

**Live check**: how errors are surfaced while you play — show every wrong cell, just an error count, or wait until the grid is complete.

**Show rating**: whether the rating screen appears between puzzles so you can rate what you just played on a five-level scale (very negative → very positive).

**Hint type**: how the hint button helps — by pointing at a cell you can deduce ("Deducible cell"), or by adding a fresh constraint that simplifies the puzzle ("Add constraint"). See the Hints section above for details.

**Idle timeout**: when no input arrives for the chosen delay (or the app loses focus), the timer auto-pauses so it does not keep running while you are away.

**Player level** (0-100): nudges the puzzles you are offered toward your reasoning speed. Higher means harder.

**Auto level**: when on, your level is updated automatically from your completion times. Turn it off to set the level by hand.

**Replay onboarding**: restart the new-player onboarding sequence from phase 0 — useful if you want to revisit the rule-introduction dialogs.

**Clear stats**: wipe the locally stored per-puzzle stats. The action is irreversible and asks for confirmation.

## Stats

The game records how much time has passed before a puzzle is solved and how many failures were made. This data stays on your device — nothing is collected automatically. If you solve a bunch of puzzles I'd love it if you sent your stats over: I use them to sort the puzzles by difficulty, and that helps a lot.

The Stats page is reachable from the main menu, under the **Progress** section. At the top, a selector lets you switch between the current collection and all collections. The **Share** button (or **Open** on desktop) exports the stats to send them over, and the **Import** button lets you re-inject a previously exported stats file.

You can also synchronise your stats between devices by pointing the app to a shared folder and using a file-sync tool like Syncthing or Dropbox — see the [cross-device stats guide](https://leveque.cc/getsomepuzzle/doc/en/crossplay.html) for instructions.

> Thank you very much.
