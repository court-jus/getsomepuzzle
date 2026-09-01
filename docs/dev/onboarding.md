# Onboarding

Constraint-by-constraint introduction mechanism driven by the player's
stats. Replaces the older "tutorial collection + `TX:` constraint +
reset button" model end to end.

## Model

1. **Per-constraint tracker** `firstSeen: Map<slug, DateTime>`
   persisted in `SharedPreferences`. When the player opens a puzzle
   that contains a slug whose `firstSeen` is `null`:
   - a **modal** displays the constraint's explanation (localised
     text in the `.arb` files);
   - on dismiss, `firstSeen[slug] = now`.
2. **Onboarding phases**: as long as not every constraint is
   unlocked, the playlist runs through a dedicated filter restricting
   the allowed constraints. Phase advancement is driven by a per-slug
   completion counter — the player crosses into the next phase once
   they have finished `phaseLength = 5` puzzles whose declared rules
   contain the current *introducing* slug.
3. **Dynamic sampling**: the onboarding playlist is **not a frozen
   list**. At each phase we sample at random from the eligible
   collections by applying the phase filter. Consequences:
   - Any new puzzle added to the corpus that satisfies the filter is
     immediately eligible.
   - A player who restarts the onboarding will **not** replay the
     same puzzles (already-played ones are excluded as in normal
     mode).
   - Only the **algorithm** (filter + introducing-slug requirement) is
     frozen.

### Rebuilding `firstSeen` from stats

`firstSeen` is derivable at any time from the play history — a player
saw a constraint the first time they completed a puzzle containing it.
On every `Database.loadStats`, for each entry where
`finished != null && skipped == null`, the loader parses the slugs
from the `puzzleLine` and sets
`firstSeen[s] = min(firstSeen[s], entry.finished)` (take the `null`
slot or the older date). This **genuine first-encounter** semantics is
robust to the order in which stat lines are read (which is not
guaranteed chronological) and leaves the door open for prompts like
"you learned this constraint X months ago, want a refresher?".

The mechanism also acts as a **runtime safety net**: if a puzzle with
`firstSeen[s] == null` shows up *during a session* (rare — an imported
playlist, an overlooked constraint, a race between `loadStats` and
puzzle open), the modal still fires on opening. No `tutorialCompleted`
flag is stored: stats remain the source of truth.

## Onboarding sequence

Two modes run back to back:

### Strict phases (P0–P9)

10 phases × 5 puzzles = 50 introductory plays. Slug-envelope filter
**plus** a hard requirement that the puzzle contains the phase's
introducing slug. Source = `1-easy` ∪ `1-easy-overfilled`.

`1-easy-overfilled.txt` collects puzzles whose prefill exceeds
`defaultMaxPrefill` (30 %) **but** whose solving trace would be
*beginner* — i.e. pedagogically simple puzzles that just happen to
have many pre-filled cells. The distinction is decided by
`classifyTrace` at generation time: depending on whether the puzzle's
`traceLevel` is *beginner* or not, it is routed to
`1-easy-overfilled.txt` or `overfilled.txt`. Every line in
`1-easy-overfilled.txt` is therefore pedagogically appropriate by
construction.

| Phase | Length | Introducing | Allowed slugs               |
|------:|-------:|:------------|:----------------------------|
| 0     | 5      | `FM`        | `{FM}`                      |
| 1     | 5      | `NC`        | `{FM, NC}`                  |
| 2     | 5      | `PA`        | `{FM, PA, NC}`              |
| 3     | 5      | `CC`        | `{FM, PA, NC, CC}`          |
| 4     | 5      | `RC`        | `{FM, PA, NC, CC, RC}`      |
| 5     | 5      | `GS`        | `{FM, PA, NC, CC, RC, GS}`  |
| 6     | 5      | `EY`        | `{…, EY}`                   |
| 7     | 5      | `DF`        | `{…, EY, DF}`               |
| 8     | 5      | `LT`        | `{…, EY, DF, LT}`           |
| 9     | 5      | `QA`        | `{…, EY, DF, LT, QA}`       |

(Each `allowed` set is cumulative: every prior introducing slug plus
the phase's own.)

The two conditions of the original `puzzleEligibleForPhase` predicate
(allow-envelope + introducing-slug-present) are expressed as a visible
filter preset on `currentFilters`:

- `wantedRules = {phase.introducing}` — the puzzle must declare the
  introducing slug.
- `bannedRules = allKnownSlugs \ phase.allowed` — every slug outside
  the phase envelope is forbidden.

`Database.recommendedOnboardingFilters` returns this pair from
`_strictPhaseRecommendation(phase)`, and
`maybeApplyOnboardingFilterDefaults` (run once per launch, gated by
the `onboardingFiltersApplied` prefs key) writes it into
`currentFilters` if the player hasn't customised them. From there the
existing `Database.filter()` does the actual filtering — there is no
dedicated onboarding sampler. The player can inspect the preset in
OpenPage and override it via the standard chip UI; the original
contract holds exactly while the preset is in effect.

Once `filter()` passes, puzzles compete on Gaussian-cplx + variety
score. The one phase-specific weighting is in phase 5: while `GS` is
the introducing slug, a puzzle holding a size-1 `GS` (an isolated
cell — a trivial, poorly instructive instance) has its selection
weight multiplied by `Database.selectionTrivialGsPenalty` (0.05).
`PuzzleData.hasTrivialGroupSize`, parsed once at load from the `GS`
`idx.size` parameter, flags it; `getPuzzlesByLevel` applies the
penalty only when `currentPhase?.introducing == 'GS'`. The factor is
non-zero so such puzzles stay drawable as a last resort and the
playlist never empties. Otherwise no refresh share, no anti-forgetting
sprinkle. `puzzleEligibleForPhase` is still exported for `bin/` tools
(e.g. `bin/check_phase_coverage.dart`) but is no longer consulted at
runtime.

Filters are kept in sync automatically: `notePuzzleCompleted` syncs
`currentFilters` with `recommendedOnboardingFilters` after every
completed puzzle, so the playlist never uses stale phase presets when
the phase transitions. A cross-session guard in `loadPuzzlesFile`
handles the edge case where the app is closed at a phase boundary.

### Soft-filter mode (post-P9)

The corpus doesn't easily sustain strict phases for the remaining slugs in
`OnboardingPhase.postStrictDiscoveryOrder` (currently `RT, MI, SY, SH, JC, CH,
CT, GC, MJ, IM, IS, JR, BB, RE, SZ`, derived from `constraintRegistry`): too
few puzzles whose declared rules sit cleanly inside a narrow envelope.

The post-P9 model is also expressed as a filter preset, via
`_softFilterRecommendation()`:

- The recommendation **elects** the first slug in
  `postStrictDiscoveryOrder` that the player has not yet met
  (exposed as `Database.electedSoftSlug`). While
  ≥ 2 slugs are still unseen, the preset is `wantedRules = {}`,
  `bannedRules = (unseen \ {elected})` — puzzles with 0 new slugs
  pass (refresh) AND the elected slug can surface (single new rule),
  while every other unseen slug is banned. The resulting playlist
  matches the "≤ 1 new rule" contract.
- **Terminal case** (one unseen slug left): the preset flips to
  `wantedRules = {elected}`, `bannedRules = {}` so the OpenPage
  banner references a real chip and the missing slug surfaces faster.

#### Surfacing the elected rule (cadenced injection + widening)

The filter preset alone is not enough: the soft-discovery slugs are
so rare in the entry catalog that the weighted sampler almost never
draws one — the abundant 0-new-rule "refresh" puzzles win every slot,
and a player who stays on the entry collection would loop forever
without ever meeting them. Two mechanisms in `Database` fix this:

- **Cadenced injection** (`_injectElectedSoftRule`, called by
  `getPuzzlesByLevel`). `notePuzzleCompleted` counts soft-phase plays
  in `_softPlaysSinceElectedChange`, reset whenever discovery advances.
  Once it reaches `softElectedInjectPeriod` (10) — or the filtered
  batch is empty, as in the terminal single-slug case — one
  elected-rule puzzle is spliced into a random slot of the upcoming
  batch. With the 5-puzzle batch granularity this surfaces a new rule
  roughly every 10–15 plays: not every batch (too rushed), not never
  (the stall).
- **Bounded widening** (`_refreshSoftDiscoveryPool`, Axe B). The entry
  collection alone is too thin for the scarcest slugs (`RT`, `CT`), so
  the pool is pre-loaded — when soft mode becomes active — with
  soft-slug puzzles from the **next level collection(s) up**, capped at
  `softDiscoveryMaxLevelsAbove` (1) so a beginner meets a rule on a
  `2-player` puzzle, never a `6-mad` one. Entry (`1-easy` +
  `1-easy-overfilled`, already in `puzzles`) plus the next level holds
  ≥ a dozen eligible puzzles for every soft slug. The injection draws
  from the current collection first and falls back to this pool only
  when the collection offers fewer than `softElectedMinInCollection`
  (8) eligible puzzles. Pool puzzles still pass `_matchesFilters` (the
  predicate extracted from `filter()`), so the envelope/flag/size
  gates hold.
- The soft filter becomes a no-op once
  `progress.firstSeen.length == OnboardingPhase.allKnownSlugs.length`
  (every known slug encountered). At that point `_softFilterActive`
  is false, `recommendedOnboardingFilters` returns `null`, and
  `isInOnboarding` flips to false → onboarding is implicitly over.
- An `OnboardingCompleteDialog` fires the next time a new-rule modal
  is dismissed after `isInOnboarding` becomes false. The dialog
  congratulates the player and mentions that future game updates
  may add new rules.
- **New-rule detection in future updates** — the infrastructure
  naturally handles new constraints added to the registry: when a
  slug unknown to the player appears in a game update,
  `_softFilterActive` automatically flips back to true
  (`firstSeen.length < allKnownSlugs.length`), the player re-enters
  discovery mode, the `NewConstraintDialog` fires for the new slug,
  and the `OnboardingCompleteDialog` fires again once all slugs are
  re-seen. If the update adds a new `OnboardingPhase` entry,
  `phaseForCompletions` returns that phase (completions for the new
  slug are 0 < `phaseLength`), placing the returning player in a
  strict phase for the new constraint.

For up-to-date corpus coverage figures per phase, run
`bin/check_phase_coverage.dart` (and `--soft` for the post-strict
fan-out). The numbers shift with every generator pass; freezing them
in this doc was painful to maintain and the script makes the
diagnostic cheap.

## Completion accounting

The strict-phase counter lives in
`Database.onboardingCompletions : Map<String, int>`, persisted as JSON
in `SharedPreferences` under the `onboardingCompletions` key.

- **On `notePuzzleCompleted(puz)`** while `currentPhase != null`,
  *every* slug present in `puz.rules` increments its counter. A
  `{FM, PA, NC}` puzzle bumps all three. The map is persisted
  fire-and-forget — failure only resets the counter on next launch.
- **`phaseForCompletions(map)`** walks `OnboardingPhase.phases` in
  order and returns the first phase whose `introducing` slug has a
  count below `phaseLength`. Returns `null` once every phase's
  introducing slug has been satisfied — that's the trigger for
  soft-filter mode.
- **`skipOnboarding()`** writes `phaseLength` to every phase's
  introducing slug and **persists immediately**. The immediate
  persistence is load-bearing: `loadPuzzlesFile` rebuilds
  `onboardingCompletions` from prefs at app start, so a deferred
  write would silently drop the player back to phase 0 the next time
  the app launches.
- **`resetOnboardingProgress()`** clears the map and persists
  immediately (same reason). It clears `onboardingCompletions`,
  **not** `firstSeen` — the explanation modals will not re-fire for
  already-seen slugs after a reset.

## Empty-playlist surfacing

When the strict-phase filter would produce an empty playlist on the
currently-selected collection (e.g. a beginner-level player tries
`6-mad` before finishing phase 5), the OpenPage banner (see
`playlist.md` §8) surfaces the recommended preset and offers a
one-tap reset to apply it, instead of an empty-state message under a
disabled Play button. The `EmptyPlaylistReason` enum carries the
residual cases only (`customEmpty`, `userAllPlayed`,
`noPuzzlesLoaded`, `filtersTooStrict`, `generic`).

## Learning page (menu)

A **Learning** menu entry (labelled "Apprentissage" in French) sits
next to Help. It serves as a rule reference and refresh tool.

For each entry in `OnboardingPhase.allKnownSlugs` (read from the
registry), the page shows:

- The localised **icon** + **name**.
- A status: `seen on 12 March 2026` if `progress.firstSeen[slug]` is
  set, otherwise "not yet encountered".
- The **number of puzzles already played** (finished, non-skipped)
  that contained this constraint. Computed by
  `Database.playCountForSlug(slug)` over the entire stats history
  (across every collection, not just the current one).
- A **"Refresh"** button that re-opens the constraint's explanation
  modal (`NewConstraintDialog.show(context, {slug})`) so the player
  can review the rule any time without affecting their progress —
  `firstSeen` stays untouched.

Slugs are sorted seen-first, by first-seen date ascending, then
alphabetical. The page is rebuilt every time it is opened — counts
and dates are pulled live from `Database` and `ConstraintProgress`.

This page also serves as a gateway for a player who **never went
through onboarding** (custom-only path, a player playing 6-mad out of
curiosity): they can browse the list and read each rule on demand,
without disturbing their main progress.

## Exiting onboarding

Onboarding is implicitly complete once
`progress.firstSeen.length == OnboardingPhase.allKnownSlugs.length`
(every constraint encountered at least once). From that point:

- `_softFilterActive` returns false and
  `recommendedOnboardingFilters` returns `null`; `isInOnboarding`
  flips to false.
- `currentFilters` keeps whatever values the player last had — the
  preset is no longer overridden at boot. The standard
  `Database.filter()` + `getPuzzlesByLevel(playerLevel)` pipeline
  runs without onboarding-specific gating.
- The `EndOfPlaylist` widget shows the standard "continue / switch
  collection" message, without the "you haven't met every rule yet"
  note.
- The `OnboardingCompleteDialog` fires the first time a new-rule
  modal is dismissed after `isInOnboarding` becomes false. If future
  updates add new constraints, the player re-enters discovery and
  the dialog fires again after the new slugs are seen.

## Custom and user playlists

The phase filter is **ignored** on `custom` / `user_*` collections —
they're explicit user choices. The `firstSeen` modals **stay
active**: if a puzzle from the `custom` playlist introduces a
never-seen constraint, the modal fires and `firstSeen[slug]` gets
set. The player auto-unlocks progressively.

## Replay and skip controls

In the player settings:

- **Replay onboarding** — `Database.resetOnboardingProgress()` clears
  `onboardingCompletions` (not `firstSeen`) and persists immediately.
  The phase filter rolls back to phase 0; dynamic sampling lands the
  player on unplayed puzzles.
- **Skip onboarding** — `Database.skipOnboarding()` writes
  `phaseLength` to every phase's introducing slug and persists,
  instantly putting the player in soft-filter mode without playing
  the phase puzzles.

## Code landing zones

- **`lib/getsomepuzzle/model/onboarding.dart`** — 10 strict
  `OnboardingPhase` entries (FM, NC, PA, CC, RC, GS, EY, DF, LT, QA),
  `phaseLength = 5`, `phaseForCompletions(Map<String, int>)`
  selector, `puzzleEligibleForPhase` helper. The soft-filter
  predicate is expressed as a filter preset
  (`_softFilterActive` / `_softFilterRecommendation` in
  `database.dart`, surfaced through `recommendedOnboardingFilters`).
  Flutter-free so it can be reused in `bin/`.
- **`lib/getsomepuzzle/model/database.dart`**:
  - `onboardingCompletions : Map<String, int>` JSON-serialised in
    `SharedPreferences` under the `onboardingCompletions` key.
  - `currentPhase` getter delegates to
    `phaseForCompletions(onboardingCompletions)`.
  - `notePuzzleCompleted` increments every slug in `puz.rules`
    when `currentPhase != null` and persists fire-and-forget. It
    also syncs `currentFilters` with `recommendedOnboardingFilters`
    whenever they diverge after the increment, keeping the playlist
    in step with the current phase. In soft mode it advances
    `_softPlaysSinceElectedChange` (the injection cadence) and, on the
    play that graduates the strict phases, triggers
    `_refreshSoftDiscoveryPool`.
  - `skipOnboarding` and `resetOnboardingProgress` both persist
    immediately to avoid the
    "loadPuzzlesFile-rebuilds-from-prefs-and-drops-the-update"
    regression.
  - `recommendedOnboardingFilters` returns the
    `(wantedRules, bannedRules)` preset for the current state
    (`_strictPhaseRecommendation` for P0–P9,
    `_softFilterRecommendation` for the post-strict discovery), or
    `null` once onboarding is over. `maybeApplyOnboardingFilterDefaults`
    runs this once per launch, behind the `onboardingFiltersApplied`
    prefs flag, and writes the result into `currentFilters`.
  - `getPuzzlesByLevel(playerLevel)` does the strict-phase gating for
    free once the preset is applied to `currentFilters` (it consults
    `filter()`). For soft mode it additionally runs
    `_injectElectedSoftRule` to splice the elected rule into the batch
    on its cadence, drawing from `_softDiscoveryPool` (Axe B) when the
    current collection is too thin.
  - `loadPuzzlesFile` runs an unconditional sync of `currentFilters`
    with `recommendedOnboardingFilters` after
    `maybeApplyOnboardingFilterDefaults`, then `_refreshSoftDiscoveryPool`
    before `preparePlaylist`. The filter sync covers the cross-session
    edge case where the previous session exited at a phase boundary and
    the fire-and-forget filter-save from `notePuzzleCompleted` may not
    have completed.
- **`firstSeen`** map in `SharedPreferences` under
  `constraintFirstSeen` (`slug → ISO date` serialisation) drives the
  explanation modal.
- **`widgets/new_constraint_dialog.dart`** fires from
  `_MyHomePageState` when a puzzle introduces a slug with
  `firstSeen[slug] == null`.
- **`widgets/onboarding_complete_dialog.dart`** fires once from the
  same post-dialog-dismissal path when `isInOnboarding` becomes
  false after the last unseen slug is marked seen.
- **`widgets/learning_page.dart`** lists
  `OnboardingPhase.allKnownSlugs` with `firstSeen` status, play
  count, and a refresh button that re-opens the explanation modal.
- **ARB entries** — `constraintExplain<Slug>` (title + body) per
  constraint, the `learningPage*` labels, the
  `bannerOnboardingFilters*` banner strings for OpenPage, the
  `onboardingCompleteTitle` / `onboardingCompleteBody` dialog
  strings, and the residual `emptyPlaylist*` reasons.

## Diagnostic tools

- `bin/onboarding_stats.dart` — regenerates the constraint coverage
  tables across `1-easy`. Useful to verify that a generator change
  or a re-sort of `1-easy` doesn't invalidate the phase sequencing.
- `bin/check_phase_coverage.dart` — per-phase coverage on the
  current corpus. Flags:
  - no flag: strict coverage (P0–P9) on `1-easy ∪ 1-easy-overfilled`.
  - `--per-level`: where phase-eligible puzzles land in each
    collection (useful after a generation run).
  - `--soft`: soft-filter coverage (≤ 1 unseen slug) at various
    stages of player progression.
