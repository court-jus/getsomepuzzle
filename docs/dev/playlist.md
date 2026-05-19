# Playlist generation — full pipeline & known bugs

This document maps every way the in-memory `Database.playlist` gets
built, across all collection types and onboarding states. It is meant to
let any future reader answer the question *"why did the player just get
puzzle X instead of Y?"* without re-reading `database.dart` end-to-end.

The reference implementation lives in
`lib/getsomepuzzle/model/database.dart`. The single dispatcher is
`Database.preparePlaylist` (≈ line 862 today); every other entry point
that mutates the playlist ultimately routes through it (with the lone
exception of the generator's "play just-generated puzzles" shortcut —
see §5.3).

---

## 1. Vocabulary

- **Collection** — the bucket of puzzle lines currently loaded into
  `Database.puzzles`. Selected via `loadPuzzlesFile(key)` and persisted
  in `SharedPreferences` under `collectionToLoad`. Three families exist:
  - **Built-in level collections** (`1-easy`, `2-player`, `3-advanced`,
    `4-strong`, `5-expert`, `6-mad`) — read-only assets shipped in
    `assets/<key>.txt`. They are the only collections that participate
    in the level-adaptive sampler and the onboarding gating.
  - **`custom`** — the bucket that receives puzzles imported by the
    user via "Open page → Open file" *into the default playlist*,
    plus puzzles produced by the in-app generator when no user
    playlist was targeted. Stored on disk at
    `<documents>/getsomepuzzle/custom.txt` (native) or in
    `SharedPreferences['custom_puzzles']` (web).
  - **User playlists** (`user_<slug>`) — named playlists the user
    created from the Open page or by importing a file. Stored at
    `<documents>/getsomepuzzle/playlist_<slug>.txt`.
- **Filters** — the `Filters` instance held at
  `Database.currentFilters`. Includes the size/prefilled ranges, the
  *wanted/banned rule slugs* (e.g. `bannedRules = {"FM"}`) and the
  *wanted/banned flags* (`played`, `skipped`, `liked`, `disliked`).
  Loaded from `SharedPreferences` once per `loadPuzzlesFile`. The
  defaults ban `played`, `skipped`, `disliked` and leave everything
  else open.
- **Shuffle** — boolean toggle stored at
  `SharedPreferences['shouldShuffleCollection']`. Reloaded at the start
  of every `loadPuzzlesFile`.
- **Onboarding state** — drives the *recommended filter preset*, not a
  separate gating pass. See §8 for the recommendation mapping.
  - `currentPhase` — strict phase (P0–P5 today). While non-null the
    player gets a phase-shaped `(wantedRules, bannedRules)` preset
    automatically the first time `loadPuzzlesFile` runs.
  - `_softFilterActive` — once strict phases are cleared, returns true
    until every known slug has been seen at least once
    (`progress.firstSeen` covers `OnboardingPhase.allKnownSlugs`). The
    soft-filter preset elects one slug to discover next and bans the
    rest of the unseen.
  - In both cases the player retains the rules-reset IconButton to
    restore the preset after a manual override.
- **Batch cap** — built-in level collections cap the in-memory playlist
  at `Database.playlistBatchSize` (5 today). Each batch boundary is the
  natural moment to surface a level-rotation suggestion. Custom and
  user playlists are *not* capped — they play the whole list straight
  through.

---

## 2. High-level `preparePlaylist` dispatch

```
preparePlaylist()
├── if collection == 'custom' OR collection.startsWith('user_')
│       base = filter().toList()
│       playlist = shouldShuffle ? (base..shuffle()) : base
│       (no batch cap)
│
└── else  // built-in level collections
        playlist = getPuzzlesByLevel(playerLevel)
        _maybeCapBatch()                 // top-5 selection
        if shouldShuffle: playlist.shuffle()
```

Three observations matter:

1. **One sampler everywhere on level collections.**
   `getPuzzlesByLevel` (Gaussian-on-cplx + variety bias) is the only
   selection mechanism. Onboarding no longer maintains a separate
   `_getPuzzlesInPhase` path — the recommended `(wantedRules,
   bannedRules)` preset is what enforces the phase envelope through
   `filter()`. The player sees in OpenPage exactly the filters that
   gate their catalog.
2. **Shuffle = display order only.**
   The toggle reorders the post-cap batch without changing which
   puzzles got selected. Both modes deliver the same level-adaptive
   top-N — useful for onboarding (the recommended slug is in every
   puzzle) and useful for advanced players (cplx-sorted vs. random).
3. **Custom / user_*** still respects `filter()` and `shouldShuffle`
   identically, with the lone differences being no batch cap and no
   onboarding preset (filters there reflect whatever the player
   chose, not the learning track).

---

## 3. Case-by-case behaviour

### 3.1 New player, never touched filters — built-in `1-easy`, onboarding P0

- `loadPuzzlesFile` loads `assets/1-easy.txt`, then augments with
  `assets/overfilled-easy.txt` because `currentPhase != null` and
  `collection == entryCollectionKey`. See
  `_augmentWithOverfilledIfOnboarding`.
- `currentFilters` loaded from prefs, defaulting to
  `bannedFlags = {played, skipped, disliked}`.
- `maybeApplyOnboardingFilterDefaults` fires on first boot (flag
  `onboardingFiltersApplied` absent in prefs): it writes
  `wantedRules = {FM}`, `bannedRules = allKnownSlugs \ {FM}` to
  `currentFilters` and sets the flag.
- `preparePlaylist` runs `getPuzzlesByLevel(playerLevel)` over the
  filtered catalog (FM-only) and caps to 5. OpenPage shows the
  preset filters and a banner explaining they reflect the learning
  track.

### 3.2 Returning player, no onboarding left, built-in `3-advanced`

- `currentPhase == null` and `_softFilterActive == false` (every slug
  seen at least once).
- `recommendedOnboardingFilters` returns null; the migration check
  is a no-op (flag was set at first boot). The player's manual
  filters are honoured as-is.
- `preparePlaylist` runs `getPuzzlesByLevel(playerLevel)`, caps to 5,
  optionally shuffles the resulting batch order.

### 3.3 Returning player, strict phase still active, jumped to `6-mad`

- `currentPhase != null`, `_isPlayableLevel('6-mad') == true`.
- The recommended preset is still phase-shaped (e.g. P3 → `wantedRules
  = {CC}`, `bannedRules = ` non-`{FM,PA,NC,CC}` slugs). 6-mad puzzles
  by construction mix late-phase slugs, so `filter()` likely returns
  zero. `emptyPlaylistReason → filtersTooStrict`; OpenPage shows the
  banner with the reset action and the disabled-Play hint. The player
  can either reset to recommendations + switch back to an
  on-track collection, or relax the filters to play 6-mad anyway. No
  invisible fallback.

### 3.4 Player imports a file as `custom`

- `loadPuzzlesFile('custom')` reads `<documents>/.../custom.txt`,
  parses each line into a `PuzzleData`, loads `currentFilters` and
  stats, then calls `preparePlaylist`.
- The first branch fires: `playlist = filter()` (optionally
  shuffled). Filters set in the open page take effect, the shuffle
  toggle takes effect, the played/skipped/disliked default bans are
  honoured.
- The onboarding phase is *not* consulted (intentional per the inline
  comment: importing is an opt-in that supersedes the curated track).

### 3.5 Player creates a `user_<name>` playlist by hand or by import

- Same code path as 3.4 (`collection.startsWith('user_')` covers it).
  Filters and shuffle apply identically.

### 3.6 Player runs the in-app generator targeting `custom`

- `generate_page.dart::_playGenerated` (line 156) assigns
  `database.playlist = generatedPuzzles.sublist(1)` **directly**,
  skipping `preparePlaylist`. The first puzzle is opened via the
  parent callback; the rest sit in the playlist in generation order.
- When the user later re-enters the page through Open, `loadPuzzlesFile`
  runs and the rest of §3.4 applies.

### 3.7 End-of-batch on a built-in collection

- `loadPuzzle` consumes from the playlist via `Database.next` until it
  becomes empty. `EndOfPlaylist` is shown.
- "Continue current" → `database.preparePlaylist()` again. Because
  `played=true` is in `bannedFlags` by default, the previously-played
  puzzles are excluded and a fresh batch of 5 is drawn.
- "Switch to recommended" → `loadPuzzlesFile(recommendedKey)` reloads
  another built-in collection.
- "Pick another" → opens `OpenPage`.

### 3.8 Editing a filter from `OpenPage`

- `applyFilter` mutates `currentFilters`, calls
  `currentFilters.save()`, then `preparePlaylist()`, then
  `updateMatchingCount`.
- `updateMatchingCount` sets `matchingCount =
  widget.database.filter().length`. Since the playlist itself is
  now derived from `filter()` on every branch, the displayed count
  matches what will actually be served (modulo the batch cap on
  built-in collections, which only trims for in-game pacing).

---

## 4. Sources of truth & call sites

| Trigger                                 | Code path                                                                 |
| --------------------------------------- | ------------------------------------------------------------------------- |
| App boot                                | `main.dart:226` → `loadPuzzlesFile()` → `preparePlaylist` (in there)      |
| Change collection from Open             | `open_page.dart:114` `chooseCollection` → `loadPuzzlesFile(collection)`   |
| Toggle a filter from Open               | `open_page.dart:108` `applyFilter` → `preparePlaylist()`                  |
| Toggle shuffle from Open                | `open_page.dart:123` `setShuffle` → `Database.setShouldShuffle` → `preparePlaylist` |
| End-of-batch → "Continue current"       | `main.dart:1115` → `preparePlaylist()`                                    |
| End-of-batch → "Switch to recommended"  | `main.dart:1131` → `loadPuzzlesFile(recommendedKey)`                      |
| Player level changes (manual or auto)   | `main.dart:972` → `preparePlaylist()`                                     |
| Skip onboarding modal                   | `main.dart:403` → `preparePlaylist()`                                     |
| Replay onboarding (Settings)            | `main.dart:923` → `preparePlaylist()`                                     |
| Clear all stats (Settings)              | `database.dart:1115` (inside `clearAllStats`) → `preparePlaylist()`       |
| Import stats file                       | `database.dart:1523` (inside `importStats`) → `preparePlaylist()`         |
| Generator "Play these now" shortcut     | `generate_page.dart:160` → **direct assignment, bypasses `preparePlaylist`** |

---

## 5. Empty-playlist reasoning

`Database.emptyPlaylistReason` (used by the Open page's disabled-Play
hint and by `EndOfPlaylist`) is a probe order, not an exclusive
classification:

```
playlist.isEmpty?
  no  → null
  yes → if (custom AND puzzles.isEmpty)            → customEmpty
        else if (collection startsWith 'user_')    → userAllPlayed   (always!)
        else if (puzzles.isEmpty)                  → noPuzzlesLoaded
        else if (filter().isEmpty)                 → filtersTooStrict
        else                                       → generic
```

Onboarding-specific reasons used to live here (`onboardingPhase`,
`softFilter`) but were retired: since the gating is now expressed
through the visible `currentFilters`, any empty playlist driven by
onboarding shows up as `filtersTooStrict` and the OpenPage banner
gives the contextual explanation.

The order matters: §6.4 below explains how this misclassifies an
empty user playlist that was just freshly created.

---

## 6. Known bugs and incoherences

### 6.1 — *(fixed)* Rule filters silently bypassed on custom / user playlists

**Status: fixed.** `preparePlaylist`'s custom/user_* branch now
routes through `filter()` exactly like the level branches:

```dart
if (collection == 'custom' || collection.startsWith('user_')) {
  final base = filter().toList();
  playlist = shouldShuffle ? (base..shuffle()) : base;
}
```

Regression coverage in
`test/playlist_batch_test.dart::Database.preparePlaylist — custom/user_ filters & shuffle`
(`bannedRules filters out matching puzzles on custom`,
`bannedRules filters apply on user_* playlists too`).

The "no shuffle = file order" contract is preserved because
`filter()` iterates `puzzles` in insertion order.

### 6.2 — *(fixed)* Shuffle toggle has no effect on custom / user playlists

**Status: fixed** as part of 6.1. The single `shouldShuffle ? ... :
...` ternary in the custom branch makes the toggle effective.
Regression covered by `shuffle reorders the playlist on custom` and
`shuffle off keeps insertion order on custom` in
`test/playlist_batch_test.dart`.

### 6.3 — *(fixed indirectly)* `matchingCount` lies on custom / user playlists

**Status: fixed by 6.1.** Since the playlist is now derived from
`filter()` on every branch, `matchingCount = filter().length`
matches the playable count (modulo the in-game batch cap on built-in
collections, which is intentional pacing).

### 6.4 — `userAllPlayed` reason returned even for a freshly created, empty user playlist

`emptyPlaylistReason` has no `customEmpty` equivalent for the
`user_<slug>` case: any time `playlist.isEmpty` on a user playlist,
`userAllPlayed` is returned regardless of cause. A user who just
created `user_foo` and hit Play before adding any puzzle gets the
"you played them all" copy — wrong and frustrating.

Fix: probe `puzzles.isEmpty` first for `user_*` too, with a dedicated
`userEmpty` reason and its own copy.

### 6.5 — *(fixed indirectly)* `skipped` / `disliked` puzzles re-surface in custom / user playlists

**Status: fixed by 6.1.** The `bannedFlags` (defaulting to `played`,
`skipped`, `disliked`) now apply on every branch via `filter()`. A
puzzle the player has explicitly disliked stops resurfacing on
custom/user_* until they toggle the dislike flag off, exactly as on
level collections.

### 6.6 — Filters are global, not per-collection

`Filters.load`/`save` are unaware of `collection`. Settings the player
chose for `3-advanced` follow them into `1-easy`, `custom`, etc. This
is the current contract (and is consistent across the codebase) but is
worth documenting: switching collection does *not* reset filters.

Now that 6.1 is fixed, this is no longer a footgun — but it does
mean that a strict filter set up while playing `3-advanced` may
silently empty a freshly-opened custom collection. The Open page's
`matchingCount` (and the disabled-Play hint via
`emptyPlaylistReason → filtersTooStrict`) does surface it.

### 6.7 — *(fixed)* Strict-phase fallback silently drops the onboarding contract

**Status: fixed.** `_getPuzzlesInPhase` and its silent fallback are
gone. The recommended filters live in `currentFilters` and `filter()`
either returns matches (so the player plays on-track) or an empty
set (so `emptyPlaylistReason → filtersTooStrict` + the OpenPage
banner explain the situation and offer reset + collection switch as
visible affordances).

### 6.8 — Generator shortcut bypasses `preparePlaylist`

`generate_page.dart:160`:

```dart
widget.database.playlist = generatedPuzzles.sublist(1);
```

This direct assignment is the only place in the codebase that
mutates `playlist` without going through `preparePlaylist`. The
freshly-generated puzzles are not flagged in any filter pass, so the
moment the user navigates away and back through Open, the in-memory
list is rebuilt from `custom.txt` and the chosen ordering is lost.
Probably acceptable for a one-off "play what I just generated" gesture
but worth a comment.

---

## 7. Recommended invariants going forward

1. **Single source of truth** — every code path that wants to mutate
   `Database.playlist` should go through `preparePlaylist`. The lone
   exception (`generate_page.dart`) should at least add an inline
   reason.
2. **Filters apply uniformly** — every branch routes through
   `filter()`; only the *batch cap* differs between built-in and
   user/custom collections.
3. **Shuffle vs. display order is a separate axis** — honoured by
   every branch. On level collections shuffle reorders the cap-trimmed
   batch (top-N stays the same); on custom/user_*, it shuffles the
   full filtered catalog.
4. **UI mirrors the engine** — `matchingCount` reflects what
   `preparePlaylist` will produce. `emptyPlaylistReason` still needs
   the §6.4 fix to fully match the engine's reasoning for user_*
   playlists.

---

## 8. Onboarding-derived filter preset

The onboarding system no longer applies a separate gating pass. It
publishes a **recommended `(wantedRules, bannedRules)` pair** through
`Database.recommendedOnboardingFilters`, which is auto-applied to
`currentFilters` the first time a player launches the post-refactor
build (gated by `SharedPreferences['onboardingFiltersApplied']`).

### 8.1 Strict-phase recommendation

For each `OnboardingPhase`:
- `wantedRules = {phase.introducing}` — puzzle must contain the
  currently-introduced slug.
- `bannedRules = OnboardingPhase.allKnownSlugs \ phase.allowed` —
  puzzle must not contain any slug outside the envelope.

This is an exact rewrite of the previous `puzzleEligibleForPhase`
predicate. `filter()` enforces it, and the player can inspect or
override the chips in OpenPage.

### 8.2 Soft-filter recommendation

Post-P5, the player still has unseen slugs. The getter elects one
slug to discover next — the first not-yet-seen entry in
`OnboardingPhase.postStrictDiscoveryOrder` (derived from
`constraintRegistry` minus the strict-phase introducers). Every
*other* not-yet-seen slug goes into `bannedRules`, and `wantedRules`
stays empty so puzzles with 0 new slugs still pass (refresh remains
allowed). This is a faithful translation of the old "≤1 new slug per
puzzle" rule that *also* gives the player a single visible slug to
expect next.

### 8.3 OpenPage banner & reset button

While `isInOnboarding == true`, OpenPage shows a banner (above the
Play button) that:
- explains the rule filters reflect the learning track,
- changes copy when the player's effective filters differ from the
  recommendation,
- exposes a reset action that restores the recommendation.

The rules-reset `IconButton` inside the advanced filters panel uses
the same code path (`_resetToRecommendation`) while in onboarding,
falling back to the historical "clear all rule filters" behaviour
after graduation.

### 8.4 Replay / skip / clearStats interactions

- `resetOnboardingProgress` and `skipOnboarding` clear the
  `onboardingFiltersApplied` flag in `SharedPreferences`. The next
  `loadPuzzlesFile` re-applies the freshly-shaped recommendation
  (P0 for replay; soft-filter or graduated-no-op for skip).
- `clearAllStats` does not touch the flag — clearing play stats keeps
  the current phase progression intact, so the existing preset
  remains correct.
