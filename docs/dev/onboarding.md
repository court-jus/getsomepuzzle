# Onboarding — replacing the tutorial

Locked-in plan to replace the `tutorial` collection (and its
"Reset tutorial" button) with a constraint-by-constraint introduction
mechanism driven by the player's stats. Open discussion is limited to
the [Still open](#7-decisions-and-still-open) section.

> **2026-05 architecture update.** The phase semantics, slug
> rotation and the "≤ 1 new slug at a time" contract are unchanged,
> but they are now expressed as a *visible* filter preset
> (`recommendedOnboardingFilters` → `currentFilters`) rather than a
> hidden gating step inside the playlist sampler. The player sees
> the preset chips in OpenPage and can override them. Sections 5–6
> below describe the current implementation; see `playlist.md` §8
> for the OpenPage banner and reset flow. Sections 3–4 keep the
> original (early-2026) corpus snapshots — informative but no
> longer regenerated.

## 1. Previous state

- Dedicated `tutorial` collection (`assets/tutorial.txt`, 23 puzzles).
- Each puzzle carried a `TX:` (`HelpText`) constraint that injected a
  pedagogical block of text at the head of the line (e.g.
  `TX:text1_1:121121111_45`).
- The collection was offered as the default at first launch
  (`collectionToLoad` → `tutorial`) and the app detected
  "tutorial finished" once every line had been played
  (`open_page.dart:43`).
- A "Restart tutorial" button in Settings called
  `Database.restartTutorial()`, which wiped the stats of the tutorial
  lines and replayed the whole sequence.
- The playlist filter had a special path for `tutorial`: no shuffle,
  no user filters, fixed pedagogical order
  (`database.dart:622`).

### Observed limitations

- **Too dense**: the 23 puzzles introduced FM, PA, GS, LT, QA, SY,
  CC, NC, GC, DF, SH in tight succession (often 2-3 constraints per
  puzzle starting from the 8th).
- **Incomplete coverage**: `EY` was never introduced. `SH` only
  appeared in a single puzzle. The pedagogy was implicit (free-form
  text) rather than tied to a specific constraint.
- **One-shot**: once finished, no further reminder; coming back six
  months later to a rare constraint was unguided.
- **Fragile**: the "reset tutorial" button relied on the exact list
  of file lines; any change to the file broke the stats reset for the
  matching entries.

## 2. Adopted model

**Drop the `tutorial` collection, the "Reset tutorial" button and the
`TX:` constraint.** In their place:

1. **Per-constraint tracker** `firstSeen: Map<slug, DateTime>`
   persisted in `SharedPreferences`. When the player opens a puzzle
   that contains a slug whose `firstSeen` is `null`:
   - a **modal** displays the constraint's explanation
     (localised text, added to the `.arb` files),
   - on dismiss, `firstSeen[slug] = now`.
2. **Onboarding phases**: as long as not every constraint is
   unlocked, the playlist runs through a dedicated filter restricting
   the allowed constraints (see § 5 for the chosen sequence).
   Phase advancement is driven by a per-slug completion counter — the
   player crosses into the next phase once they have finished
   `phaseLength` (= 5) puzzles whose declared rules contain the current
   *introducing* slug. See § 5 for the exact accounting rules.
3. **Dynamic sampling**: the onboarding playlist is **not a frozen
   list**. At each phase we sample at random from the `1-easy`
   collection (and later others) by applying the phase filter.
   Consequences:
   - Any new puzzle added to the corpus that satisfies the filter is
     immediately eligible.
   - A player who restarts the onboarding will **not** replay the
     same puzzles (already-played ones are excluded as in normal mode).
   - Only the **algorithm** (filter + introducing-slug requirement) is
     frozen.

### Asset migration

- `assets/tutorial.txt` is removed.
- Its 23 puzzles are **merged into the appropriate level
  collections** (`1-easy` / `2-player` / …) according to their `cplx`.
- The `TX:` prefix is stripped from each migrated line. The
  `HelpText` class (`lib/getsomepuzzle/constraints/helptext.dart`) and
  its registration in `registry.dart` are removed.
- The `tutorial` mode disappears from the dropdown, along with the
  specific code in `Database.preparePlaylist()` and
  `Database.restartTutorial()`.

### Migration and rebuilding `firstSeen` from stats

`firstSeen` is derivable at any time from the play history: a player
saw a constraint the first time they completed a puzzle that
contained it. We exploit that:

- On every stats load (`Database.loadStats`), for each entry where
  `finished != null && skipped == null`, we parse the slugs from the
  `puzzleLine`; for each slug `s`, we set
  `firstSeen[s] = min(firstSeen[s], entry.finished)` (i.e. take the
  `null` slot or the older date). This **genuine first-encounter**
  semantics is robust to the order in which stat lines are read
  (which is not guaranteed chronological) and leaves the door open
  for prompts like "you learned this constraint X months ago, want a
  refresher?".
- Consequences:
  - A player who finished the tutorial has `firstSeen` populated for
    the 11 tutorial constraints (`FM, PA, GS, LT, QA, SY, CC, NC, GC,
    DF, SH`) — but not for `EY`, which the tutorial didn't cover.
  - A player who climbed without the tutorial has `firstSeen`
    populated for each constraint encountered in `1-easy` /
    `2-player` / etc., proportionally to their plays — typically `EY`
    will be set if they've played enough in `1-easy` (`EY` is at 9 %
    there) or higher.
  - A fresh player keeps `firstSeen = {}` and starts in phase 0.
- The mechanism is also a **runtime safety net**: if a puzzle with
  `firstSeen[s] == null` shows up *during a session* (rare — an
  imported playlist, an overlooked constraint, a race window between
  loadStats and puzzle open), the modal still fires on opening. The
  load-time rebuild covers the bulk of the migration without a
  dedicated button.
- No "migration date" or `tutorialCompleted` flag is stored: stats
  remain the source of truth.

## 3. Data: constraint distribution in `1-easy`

Computed by `bin/onboarding_stats.dart` on `assets/1-easy.txt`
(1750 puzzles). For each slug: catalog presence, number of puzzles
where it is the **only** declared rule (`solo`), and how many of those
solo puzzles are entirely solvable with complexity-0 propagations
(`solo_cplx0`).

```
slug   #puz      %      solo   solo_cplx0  solo_cplx≤1
FM     1605   91.7%     99        50          93
PA     1368   78.2%      0         0           0
GS     1072   61.3%      9         0           2
SY      397   22.7%      0         0           0
DF      248   14.2%      0         0           0
QA      241   13.8%      0         0           0
CC      228   13.0%      0         0           0
EY      163    9.3%      7         0           0
NC      127    7.3%     26        26          26
LT       93    5.3%      0         0           0
GC       14    0.8%      0         0           0
SH        2    0.1%      0         0           0
```

Distribution by complexity tier (over every propagation step observed
when replaying `solveExplained` on each puzzle):

```
slug   #puz_used  total   t0     t1     t2     t3     t4     t5    %t0
FM       1602    15744   8771   3780   3193      0      0      0   55.7
GS       1072     6220   3790   2159    271      0      0      0   60.9
PA       1363     3373   2155   1097    121      0      0      0   63.9
SY        397     1263      0    128   1135      0      0      0    0.0
EY        163     1246    666      0    580      0      0      0   53.5
NC        127      993    993      0      0      0      0      0  100.0
CC        226      663    663      0      0      0      0      0  100.0
QA        239      606    606      0      0      0      0      0  100.0
DF        239      472    472      0      0      0      0      0  100.0
LT         92      158    123     20     15      0      0      0   77.8
SH          2        5      5      0      0      0      0      0  100.0
```

## 4. Data: FM+X and NC+X duos

> **Note.** This section captures the duo-based analysis that
> informed an early version of the onboarding sequence. The final
> sequence § 5 uses **cumulative envelopes** (each phase's `allowed`
> set extends the previous one), not strict `{FM,X}` / `{NC,X}`
> duos. The data below is still informative for picking which slug
> to introduce next, but the prose framing of "FM-anchored vs
> NC-anchored introductions" no longer matches the shipped flow.

Once FM and NC are mastered, we look to introduce each new constraint
X via a puzzle whose only declared rules are `{FM, X}` or `{NC, X}`.
The table gives, per anchor, the number of available "duo" puzzles,
how many are entirely solvable in complexity 0 (resp. ≤ 1), and the
tier distribution of propagations attributed to the **partner** only.

```
Duos with anchor=FM  ({FM, partner}):
  partner   #duo   cplx0  cplx≤1   partner_steps  t0   t1   t2   t3   t4   t5    %t0
  PA       326     55    258         761        433  294   34    0    0    0    56.9
  GS       126     20     54         825        505  284   36    0    0    0    61.2
  LT         7      1      6          15          6    4    5    0    0    0    40.0
  SY         4      0      0          13          0    2   11    0    0    0     0.0
  NC         1      0      0          16         16    0    0    0    0    0   100.0
  QA         1      0      0           1          1    0    0    0    0    0   100.0

Duos with anchor=NC  ({NC, partner}):
  partner   #duo   cplx0  cplx≤1   partner_steps  t0   t1   t2   t3   t4   t5    %t0
  PA         7      4      7          33         26    7    0    0    0    0    78.8
  CC         6      6      6          16         16    0    0    0    0    0   100.0
  DF         3      3      3           3          3    0    0    0    0    0   100.0
  GS         2      0      1          14          7    6    1    0    0    0    50.0
  FM         1      0      0           2          0    0    2    0    0    0     0.0
  QA         1      1      1           1          1    0    0    0    0    0   100.0
```

## 5. Adopted onboarding sequence

Onboarding works in **two phases**:

1. **Strict phases** (P0-P5, 6 phases × 5 puzzles = 30 introductory
   plays) — slug-envelope filter **plus** a hard requirement that the
   puzzle contains the phase's introducing slug. Source =
   `1-easy` ∪ `overfilled-easy`. The second file collects puzzles
   whose prefill exceeds `defaultMaxPrefill` (30 %) **but** whose
   solving trace would be *beginner* — i.e. pedagogically simple
   puzzles that just happen to have many pre-filled cells. The
   distinction is decided by `classifyTrace` at generation time:
   depending on whether the puzzle's `traceLevel` is *beginner* or
   not, it is routed to `overfilled-easy.txt` or `overfilled.txt`.
   Every line in `overfilled-easy.txt` is therefore pedagogically
   appropriate by construction.
2. **Soft filter mode** (post-P5) — the playlist falls back to
   `getPuzzlesByLevel(playerLevel)` on any collection
   (1-easy → 6-mad), with **one extra filter**: a puzzle may
   introduce **at most one constraint not yet seen**. The remaining
   constraints (LT, QA, SY, DF, SH, GC, EY) are then discovered
   organically, one at a time, at a pace that depends on the player.

### Constraint-completion accounting

The strict-phase counter lives in
`Database.onboardingCompletions : Map<String, int>`, persisted as
JSON in `SharedPreferences` under the
`onboardingCompletions` key.

- **On `notePuzzleCompleted(puz)`** while `currentPhase != null`,
  *every* slug present in `puz.rules` increments its counter. A
  `{FM, PA, NC}` puzzle bumps all three. The map is persisted
  fire-and-forget — failure only resets the counter on next launch.
- **`phaseForCompletions(map)`** walks `OnboardingPhase.phases` in
  order and returns the first phase whose `introducing` slug has a
  count below `phaseLength` (= 5). Returns `null` once every phase's
  introducing slug has been satisfied — that's the trigger for
  soft-filter mode.
- **`skipOnboarding()`** writes `phaseLength` to every phase's
  introducing slug and **persists immediately**. The immediate
  persistence is load-bearing: `loadPuzzlesFile` rebuilds
  `onboardingCompletions` from prefs at app start, so a deferred
  write would silently drop the player back to phase 0 the next time
  the app launches.
- **`resetOnboardingProgress()`** clears the map and persists
  immediately (same reason). Note: this clears
  `onboardingCompletions`, **not** `firstSeen` — the explanation
  modals will not re-fire for already-seen slugs after a reset. If
  the eventual product decision is to also reshow modals on replay,
  `firstSeen` must be wiped separately.

### Strict phases (P0-P5)

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
contract holds exactly while the preset is in effect. The sampler
does no extra phase weighting: once `filter()` passes, puzzles compete
on Gaussian-cplx + variety score. No refresh share, no
anti-forgetting sprinkle. `puzzleEligibleForPhase` is still exported
for `bin/` tools (e.g. `bin/check_phase_coverage.dart`) but is no
longer consulted at runtime.

| Phase | Length | Introducing | Allowed slugs               |
|------:|-------:|:------------|:----------------------------|
| 0     | 5      | `FM`        | `{FM}`                      |
| 1     | 5      | `NC`        | `{FM, NC}`                  |
| 2     | 5      | `PA`        | `{FM, PA, NC}`              |
| 3     | 5      | `CC`        | `{FM, PA, NC, CC}`          |
| 4     | 5      | `RC`        | `{FM, PA, NC, CC, RC}`      |
| 5     | 5      | `GS`        | `{FM, PA, NC, CC, RC, GS}`  |

Filters are kept in sync automatically: `notePuzzleCompleted` syncs
`currentFilters` with `recommendedOnboardingFilters` after every
completed puzzle, so the playlist never uses stale phase presets when
the phase transitions. A cross-session guard in `loadPuzzlesFile`
handles the edge case where the app is closed at a phase boundary.

Past P5 the player enters the soft-filter mode described below.

### Empty-playlist surfacing

When the strict-phase filter would produce an empty playlist on the
currently-selected collection (e.g. a beginner-level player tries
6-mad before finishing phase 5), the OpenPage banner introduced in
2026-05 (see `playlist.md` §8) surfaces the recommended preset and
offers a one-tap reset to apply it, instead of the
previous empty-state message under a disabled Play button. The
`EmptyPlaylistReason` enum still exists for the residual empty states
(`customEmpty`, `userAllPlayed`, `noPuzzlesLoaded`, `filtersTooStrict`,
`generic`) — it no longer contains a dedicated onboarding case.

### "Soft filter" mode (post-P5)

Why no strict phase past P5? The corpus doesn't easily sustain strict
phases for the remaining slugs (the eight in
`OnboardingPhase.postStrictDiscoveryOrder` — currently
`LT, QA, SY, DF, SH, GC, MJ, EY`, derived from `constraintRegistry`):
too few puzzles whose declared rules sit cleanly inside a narrow
envelope. Generating more in such a narrow envelope is
counter-productive (the generator classifies elsewhere or yields very
little).

Adopted model — also expressed as a filter preset, via
`_softFilterRecommendation()`:

- The player can explore **every level collection** (the user-level
  filter still drives the sampler).
- The recommendation **elects** the first slug in
  `postStrictDiscoveryOrder` that the player has not yet met. While
  ≥ 2 slugs are still unseen, the preset is
  `wantedRules = {}`, `bannedRules = (unseen \ {elected})` — puzzles
  with 0 new slugs pass (refresh) AND the elected slug can surface
  (single new rule), while every other unseen slug is banned. The
  resulting playlist matches the original "≤ 1 new rule" contract.
- **Terminal case** (one unseen slug left): the preset flips to
  `wantedRules = {elected}`, `bannedRules = {}` so the OpenPage banner
  references a real chip and the missing slug surfaces faster.
- The soft filter becomes a no-op once
  `progress.firstSeen.length == OnboardingPhase.allKnownSlugs.length`
  (every known slug encountered). At that point
  `_softFilterActive` is false, `recommendedOnboardingFilters`
  returns `null`, and `isInOnboarding` flips to false → onboarding is
  implicitly over.
- An `OnboardingCompleteDialog` fires the next time a new-rule modal
  is dismissed after `isInOnboarding` becomes false (i.e. the last
  unseen slug was just marked seen). The dialog congratulates the
  player and mentions that future game updates may add new rules.
- **New-rule detection in future updates** — The existing
  infrastructure naturally handles new constraints added to the
  registry: when a slug unknown to the player appears in a game
  update, `_softFilterActive` automatically flips back to true
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

### Learning page (menu)

A **Learning** menu entry (labelled "Apprentissage" in French) sits
next to Help. It serves as a rule reference and refresh tool.

For each entry in `OnboardingPhase.allKnownSlugs` (currently 14 slugs,
read from the registry), the page shows:

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
without disturbing their main progress. A previous spec proposed a
"mini refresher playlist" launched from this page; that feature was
not retained — the modal-only refresh ships today.

### Exiting onboarding

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
- The EOP shows the standard message ("continue / switch
  collection"), without the "you haven't met every rule yet" note.
- The `OnboardingCompleteDialog` fires the first time a new-rule
  modal is dismissed after `isInOnboarding` becomes false. If future
  updates add new constraints, the player re-enters discovery and
  the dialog fires again after the new slugs are seen.

## 6. Implementation: code impact

The implementation reached a stable shape in v1.6.x. Key landing zones:

- **`lib/getsomepuzzle/model/onboarding.dart`**: 6 strict
  `OnboardingPhase` entries (FM, NC, PA, CC, RC, GS),
  `phaseLength = 5`, `phaseForCompletions(Map<String,int>)`
  selector, `puzzleEligibleForPhase` helper. The soft-filter
  predicate that used to live here is now expressed as a filter
  preset (`_softFilterActive` / `_softFilterRecommendation` in
  `database.dart`, surfaced through `recommendedOnboardingFilters`).
  Flutter-free so it can be reused in `bin/`.
- **`lib/getsomepuzzle/model/database.dart`**:
  - `onboardingCompletions : Map<String,int>` (was `int` pre-v1.6),
    JSON-serialised in `SharedPreferences` under the
    `onboardingCompletions` key.
  - `currentPhase` getter delegates to
    `phaseForCompletions(onboardingCompletions)`.
  - `notePuzzleCompleted` increments every slug in `puz.rules`
    when `currentPhase != null` and persists fire-and-forget.
    It also syncs `currentFilters` with
    `recommendedOnboardingFilters` whenever they diverge after the
    increment, keeping the playlist in step with the current phase
    (covers both strict-phase advances and soft-filter changes from
    `progress.noteSeen` in the previous dialog dismissal).
  - `skipOnboarding` and `resetOnboardingProgress` both persist
    immediately to avoid the
    "loadPuzzlesFile-rebuilds-from-prefs-and-drops-the-update"
    regression.
  - `recommendedOnboardingFilters` returns the
    `(wantedRules, bannedRules)` preset for the current state
    (`_strictPhaseRecommendation` for P0-P5,
    `_softFilterRecommendation` for the post-strict discovery), or
    `null` once onboarding is over. `maybeApplyOnboardingFilterDefaults`
    runs this once per launch, behind the `onboardingFiltersApplied`
    prefs flag, and writes the result into `currentFilters`.
  - `preparePlaylist` no longer carries an onboarding-specific path
    — once the preset is applied to `currentFilters`, the standard
    `getPuzzlesByLevel(playerLevel)` pipeline (which consults
    `filter()`) does the gating for free.
  - `loadPuzzlesFile` runs an unconditional sync of `currentFilters`
    with `recommendedOnboardingFilters` after
    `maybeApplyOnboardingFilterDefaults`. This covers the
    cross-session edge case where the previous session exited at a
    phase boundary and the fire-and-forget filter-save from
    `notePuzzleCompleted` may not have completed.
  - `EmptyPlaylistReason` enum + `emptyPlaylistReason` getter
    surface a localised reason under the Play button when the
    playlist is empty. As of 2026-05 the enum carries the residual
    cases only (`customEmpty`, `userAllPlayed`, `noPuzzlesLoaded`,
    `filtersTooStrict`, `generic`); the previous onboarding-specific
    and soft-filter-specific cases are absorbed by the upstream
    `recommendedOnboardingFilters` preset (see `playlist.md` §8).
- **Removed earlier**: `tutorial` dropdown entry, `restartTutorial`,
  the tutorial settings section, `assets/tutorial.txt`, the
  `HelpText` (`TX:`) class + registration, the `tutorial` mode in
  `preparePlaylist`, and the `settingRestartTutorial*` /
  `endOfPlaylistTutorialFinished` ARB strings.
- **`firstSeen`** map in `SharedPreferences` (`constraintFirstSeen`),
  with `slug → ISO date` serialisation, drives the explanation modal.
- **`widgets/new_constraint_dialog.dart`** modal fires from
  `_MyHomePageState` when a puzzle introduces a slug with
  `firstSeen[slug] == null`.
- **`widgets/onboarding_complete_dialog.dart`** modal fires once
  from the same post-dialog-dismissal path in `_MyHomePageState`
  when `isInOnboarding` becomes false after the last unseen slug
  is marked seen. Congratulates the player and signals that future
  updates may bring new rules.
- **`widgets/learning_page.dart`** page reachable from the main menu
  next to Help: list of `OnboardingPhase.allKnownSlugs` (14 today)
  with `firstSeen` status, play count, and a refresh button that
  re-opens the explanation modal — no refresher playlist.
- **ARB entries**: `constraintExplain<Slug>` (title + body) per
  constraint, the `learningPage*` labels, the `bannerOnboardingFilters*`
  banner strings for OpenPage, the `onboardingCompleteTitle` /
  `onboardingCompleteBody` dialog strings, and the residual
  `emptyPlaylist*` reasons (`customEmpty`, `userAllPlayed`,
  `noPuzzlesLoaded`, `filtersTooStrict`, `generic`).

## 7. Decisions and still open

### Locked-in decisions

1. **No refresh sprinkle.** During strict phases, only puzzles that
   *contain* the introducing slug are eligible — the introducing-slug
   requirement is baked into `puzzleEligibleForPhase` itself, not
   layered on top via a sampler weight. The earlier 80/20 mix (where
   refresh puzzles using only previously-met slugs got weight 1 and
   introducing puzzles got weight 4) was removed — the `phaseWeight`
   helper is gone. Rationale: with `phaseLength = 5` per phase and 6
   phases, the player only sees 30 onboarding-strict puzzles total; a
   refresh share would dilute the teaching focus. Refresh of
   already-met rules happens organically in soft-filter mode (post-P5)
   since the soft filter accepts any puzzle with ≤ 1 unseen slug.
2. **`playerLevel` during onboarding**: **kept as-is**. The phase
   sampler uses the Gaussian centred on
   `playerLevel + selectionOffset` exactly as elsewhere. This is
   safe only because the onboarding source (`1-easy +
   overfilled-easy`) is already bounded to the *beginner* level by
   trace classification — a fast learner can therefore not land on a
   puzzle out of pedagogical reach, regardless of `playerLevel`.
   It's the "if we're at beginner, we should be at beginner" intuition:
   the trade-off is solved at the catalog level, not at the sampler
   level.
3. **End of playlist during onboarding**: as long as the § 5 phases
   aren't all done, the `EndOfPlaylist` widget shows **an explicit
   note** to the player: they haven't met every rule yet, and we
   **suggest staying on the "Beginner" (`1-easy`) collection**.
   Concretely the phase filter keeps the next batch in `1-easy`; the
   note just prevents the player from diving into a harder collection
   whose puzzles would be filtered to nothing afterwards.
4. **"Replay onboarding" button** replaces the old "Reset tutorial".
   Action: `Database.resetOnboardingProgress()` clears the
   `onboardingCompletions` map (not `firstSeen` — the explanation
   modals do not re-fire for already-seen slugs) and persists
   immediately. The phase filter automatically rolls back to phase 0,
   and thanks to the dynamic sampling (§ 2.3) the player lands on
   unplayed puzzles. There is also a **"Skip onboarding"** button
   that calls `skipOnboarding()`: writes `phaseLength` to every
   phase's introducing slug and persists, instantly putting the
   player in soft-filter mode without playing the phase puzzles.

### Locked-in decisions (cont.)

5. **`custom` / `user_*` collections**: we **ignore the phase
   filter** on those (they are explicit user choices). The
   `firstSeen` modals **stay active**: if a puzzle from the
   `custom` playlist introduces a never-seen constraint, the modal
   fires and `firstSeen[slug]` gets set. The player auto-unlocks
   progressively.

### Still open

1. **Phases 6+**: introduction order for LT/QA/SY/EY/GC/SH to be
   spec'd after the in-progress generation of small puzzles
   (≤ 5×5) — the enriched corpus should make the missing duos
   (FM+QA, FM+EY, …) currently absent from `1-easy` available.
   A new pass of `bin/onboarding_stats.dart` after the generation
   will tell us whether we can hold phases 6+ as pure duos or have
   to keep going via trios.

## 8. Diagnostic tools

- `bin/onboarding_stats.dart`: regenerates the tables of § 3 and § 4.
  Useful to verify that a generator change or a re-sort of `1-easy`
  doesn't invalidate the § 5 sequencing.
- `bin/check_phase_coverage.dart`: per-phase coverage on the current
  corpus. Flags:
  - no flag: strict coverage (P0-P5) on `1-easy ∪ overfilled-easy`.
  - `--per-level`: where phase-eligible puzzles land in each
    collection (useful after a generation run).
  - `--soft`: soft-filter coverage (≤1 unseen slug) at various
    stages of player progression.
