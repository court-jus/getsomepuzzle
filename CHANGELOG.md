# Changelog

All notable changes to **Get Some Puzzle** are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Per-store "What's New" entries are derived from this changelog and
localised under
`marketing/play_store/<locale>/changelogs/default.txt` and
`marketing/app_store/<locale>/release_notes.txt`.

## [Unreleased]

## [1.7.0] — TBD

First public release on Google Play and the App Store.

## [1.6.16] — 2026-05-26

- **Privacy policy** authored in en/fr/es and reachable from the help page; deployed under gh-pages so the store privacy URL fields can point to it.
- **No more outbound network calls**: stats are never sent automatically. The `ShareData` setting was removed (it had become meaningless), and the Android `INTERNET` permission is stripped from the release manifest. Help pages scrubbed of obsolete telemetry mentions.
- User help refreshed.

## [1.6.15] — 2026-05-23

- **Onboarding filter fix**: the playlist no longer surfaces puzzles that conflict with the filters configured for the active onboarding phase.

## [1.6.14] — 2026-05-22

- **New constraint: Chain** (CH) — a marked cell must belong to a group whose cells form a single chain (no T-junction, no 2×2 block).
- **New constraint: Majority** (MJ) — inside a bounded zone, the indicated color must hold the majority of cells.
- **Smarter hint suggestions**: a new GS/QA complicity is detected, so hints can surface cells that only fall when GroupSize and Quantity are reasoned about together.
- **Onboarding scenarios** for path-based puzzles and the Symmetry prefill, smoother phase transitions, and onboarding/OpenPage filters now stay in sync.
- Fixes for manual validation, undo, puzzle rotation, Android display glitches and the onboarding message in the Open page.

## [1.6.13] — 2026-05-18

- **Help pages** updated with more details about the UI.
- **Onboarding tightened**: during strict phases, the playlist now only surfaces puzzles that contain the constraint being introduced. Refresh-only puzzles using just previously-learned constraints no longer dilute the 30-puzzle teaching budget.
- **Hint constraints skipped when useless**: the background pass that searches for a constraint to suggest no longer runs when the puzzle is already fully solvable without one, saving CPU and battery.
- **Most useful hint first**: when adding a constraint hint, the candidate that unlocks the most cells in one step is now offered first, instead of being picked at random among the useful pool.
- **Drag stays inside the grid**: dragging past the side of the grid no longer "jumps" the paint to a cell on a different row through index wrap-around.

## [1.6.12] — 2026-05-16

- **Group Count fix**: a deduction bug in the GC constraint that could mark valid states as impossible has been resolved.
- **Onboarding reset** now actually resets onboarding progress instead of leaving stale state behind.
- **Open page UX** improvements.
- Corpus cleanup: bad puzzles dropped, additional onboarding puzzles added.

## [1.6.11] — 2026-05-14

- **Onboarding overhaul**: more puzzles dedicated to learning each constraint, and a smoother phase progression.
- **Reset buttons** added in the Open page so filters can be brought back to defaults in one click.
- **Constraint hint bug fixes** so suggestions no longer flicker or duplicate.
- New launcher icons.
- ~10K new puzzles added since 1.6.6.

## [1.6.10] — 2026-05-11

- **Stats no longer erased** by app updates, and a manual import option lets you bring stats over from another device.

## [1.6.9] — 2026-05-11

- **Data collection removed** and a privacy policy prepared for store listings.
- Missing Spanish / French translations filled in.

## [1.6.8] — 2026-05-06

- **Welcome dialog** on first launch to introduce new players to the game.
- **Burger menu reorganized** for easier navigation between game, settings, stats, and learning.
- **Auto-rotation**: puzzles now rotate automatically to match the screen orientation.
- Default puzzle-rating value tweaked.

## [1.6.7] — 2026-05-05

- **Onboarding can now be reset or skipped** from settings.
- Wording and widget fixes for GroupSize, NeighborCount and Eyes constraints.

## [1.6.6] — 2026-05-04

- **New constraint: Row Count** (RC) — restricts how many cells of a given color appear in each row, complementing Column Count.
- ~3K new puzzles added.

## [1.6.5] — 2026-05-02

- **Onboarding redesigned**: new players follow a guided sequence of phases that introduces one constraint at a time.
- **Drag-end fix**: phantom drag-end events that left cells half-painted no longer fire.
- **Stability**: concurrent stats writes are now serialized; level / skill tracking corrected.
- ~3K new puzzles added.

## [1.6.4] — 2026-05-02

- **Level collections**: the shipped catalog is split into six difficulty levels (1-easy → 6-mad) instead of a single bucket.
- **Letter Group fix**: a constraint-mutation gap that broke LT aggregation in some grids was closed.
- **Stats sharing on Linux** now works.
- **Stable layout**: the puzzle no longer shifts down when a hint is displayed.

## [1.6.3] — 2026-05-01

- **Save and resume**: in-progress puzzles can now be paused and resumed later.
- **Share a puzzle** from the app, including deep-link support on Linux desktops.
- **Combined-constraint hints**: hints can now point to *pairs of constraints* that together force a cell, not only single constraints.
- **Auto-pause on menu** so the timer doesn't run while you're navigating settings.
- Smarter Symmetry and GroupSize solvers.

## [1.6.2] — 2026-04-29

- **Smarter Eyes and Groups** deductions: live-check spots Eyes-driven implications and inter-group path constraints it used to miss.
- **Adapt-to-player recalibrated** so the inferred level anchors around 50 instead of drifting toward extremes.

## [1.6.1] — 2026-04-28

- **New constraint: Eyes** (EY) — an "eye" cell must see exactly the indicated number of cells of its color along the four orthogonal directions, stopping at the grid edge or the opposite color.
- **Improved adapt-to-player**: the level-tracking algorithm now reacts more reliably to your completion times.
- **Hint system improvements** including a race-condition fix in hint cancellation.
- New puzzles added to the catalog.

## [1.6.0] — 2026-04-24

- **Four new constraints**: Shape (every group of a color must match a given shape, rotations and mirrors allowed), Column Count (the number of cells of a color in a column), Group Count (the number of distinct groups of a color), and Neighbor Count (a marked cell must have an exact count of orthogonal neighbors of a given color). Each comes with its own widget and explanation modal.
- **Constraint hints**: when stuck, the hint button can now suggest a *new constraint* to graft onto the grid rather than a single forced cell. Suggestions are filtered to ones that actually unlock progress.
- **Adaptive level**: the puzzle sampler tracks your completion times and gradually shifts toward puzzles matched to your inferred level.
- **Auto-pause** when the app loses focus or after a stretch of inactivity, so the timer doesn't keep running while you're away.
- **Quality-of-life UI**: completed constraints are grayed out, right-click drag-and-drop works on desktop / web, and the Symmetry widget got a clearer redesign.
- ~2K new puzzles added.

## [1.5.0] — 2026-04-10

- **Create your own puzzles**: a built-in editor lets you craft puzzles by hand, and a built-in generator produces new puzzles to your spec. Both feed a dedicated "custom" collection alongside the shipped ones.
- **Hint arrow**: hints now show a directional arrow on the suggested cell, and a second click fills the cell automatically.
- **Smarter live-check**: improvements to the Symmetry and Groups solvers mean live-check spots more deductions and stops flagging false errors.
- **Less spoilery hints**: hints that would require deep reasoning are deliberately less precise, so the helper guides rather than solves for you.
- Many small fixes around hint interaction, menu navigation, and symmetry edge cases.

## [1.4.0] — 2025-12-14

- **Drawer menu**: the main menu moved into a side drawer for easier access across platforms.
- **Live-check mode**: an opt-in mode that highlights cells as you play and shows the running error count, alongside the existing manual-check workflow.
- **Drag and drop** to paint multiple cells in one gesture.
- **5-level rating** (replacing binary like/dislike), and the ability to undo or restart even after completing a puzzle.
- **Single difficulty filter**: the old easy / medium / hard / harder / evil collections were merged into one collection with a complexity slider in the Open page. A "no-network" opt-out was added and stats sharing was simplified.

## [1.3.0] — 2025-11-14

- **Spanish translation** added alongside English and French. The app asks for the preferred language at first launch and remembers it.
- **Settings persistence**: the last collection played and the shuffle preference are restored between sessions.
- **Web stability**: per-puzzle stats now save and load correctly on the web version.
- **UI polish**: icons unified through FontAwesome, the main view becomes scrollable on small screens, and Android keeps the screen on while playing.
- Tutorial text rendered as Markdown for clearer formatting.

## [1.2.0] — 2025-11-09

- **New constraint: Symmetry** (SY) — a cell marked with one of five symbols (⟍, |, ⟋, ―, 🞋) requires the group it belongs to to be symmetric along the indicated axis; central symmetry (🞋) is a half-turn rotation.
- **Multiple puzzle collections**: the catalog is split into themed playlists you can switch between from the Open page.
- **Open page redesign**: the long puzzle list became a single "play next" button; filter sliders were replaced by plus/minus widgets that also show how many puzzles match.
- **Secondary-tap support**: right-click now marks the opposite color on desktop and web.
- Playlist shuffle is applied whenever a playlist is prepared, not just on explicit request.
- ~3K new puzzles added.

## [1.1.0] — 2025-11-02

- **Playlist shuffle**: an opt-in switch to randomize the order in which puzzles are surfaced.
- **Cleaner corpus**: duplicates and puzzles that consistently get disliked were dropped from the shipped collection.
- **More robust loading**: imported puzzles that came without their stored solution now import cleanly, and the puzzle database reloads correctly after settings changes.

## [1.0.2] — 2025-09-06

- First "real" version using Flutter.

## [0.1.0] — 2025-08-24

- After many iterations and various working versions, this one is a bit of a milestone.

## [0.0.1] — 2025-08-13

- First commits.
