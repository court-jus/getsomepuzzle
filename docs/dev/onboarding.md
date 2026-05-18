# Onboarding — replacing the tutorial

Locked-in plan to replace the `tutorial` collection (and its
"Reset tutorial" button) with a constraint-by-constraint introduction
mechanism driven by the player's stats. Open discussion is limited to
the [Still open](#7-decisions-and-still-open) section.

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

Filters are expressed as **sets of declared slugs** in the puzzle
(`TX` is excluded by default since it is gone). The eligibility
predicate `puzzleEligibleForPhase` enforces two conditions
simultaneously: the puzzle's slugs must sit inside the phase's
`allowed` envelope **and** the puzzle must declare the phase's
`introducing` slug. The sampler does no extra phase weighting — once
a puzzle is eligible, it competes purely on Gaussian-cplx + variety
score. No refresh share, no anti-forgetting sprinkle.

| Phase | Length | Introducing | Allowed slugs               |
|------:|-------:|:------------|:----------------------------|
| 0     | 5      | `FM`        | `{FM}`                      |
| 1     | 5      | `NC`        | `{FM, NC}`                  |
| 2     | 5      | `PA`        | `{FM, PA, NC}`              |
| 3     | 5      | `CC`        | `{FM, PA, NC, CC}`          |
| 4     | 5      | `RC`        | `{FM, PA, NC, CC, RC}`      |
| 5     | 5      | `GS`        | `{FM, PA, NC, CC, RC, GS}`  |

Past P5 the player enters the soft-filter mode described below.

### Empty-playlist surfacing

When the strict-phase filter produces an empty playlist on the
currently-selected collection (e.g. a beginner-level player tries
6-mad before finishing phase 5),
`Database.emptyPlaylistReason` returns
`EmptyPlaylistReason.onboardingPhase` and `open_page.dart` renders the
localised `emptyPlaylistOnboardingPhase` message under the disabled
Play button. The reason cascade in `emptyPlaylistReason` covers the
six other empty-state cases too: see `database.dart` near the
`EmptyPlaylistReason` enum for the full ordering.

### "Soft filter" mode (post-P5)

Why no strict phase past P5? The corpus doesn't easily sustain strict
phases for the remaining slugs (LT, QA, SY, DF, SH, GC, EY): too few
puzzles whose declared rules sit cleanly inside a narrow envelope.
Generating more in such a narrow envelope is counter-productive (the
generator classifies elsewhere or yields very little).

Adopted model:

- The player can explore **every level collection** (the user-level
  filter still drives the sampler).
- A **soft filter** rejects any puzzle whose declared rules contain
  ≥ 2 slugs with `firstSeen[s] == null`. Consequence: each surfaced
  puzzle introduces at most **one** new rule (for which the modal
  fires), while still serving realistic puzzles that combine
  already-mastered rules.
- The soft filter becomes a no-op once the player has met every known
  constraint (`firstSeen.length == OnboardingPhase.allKnownSlugs`)
  → onboarding is implicitly over.

For up-to-date corpus coverage figures per phase, run
`bin/check_phase_coverage.dart` (and `--soft` for the post-strict
fan-out). The numbers shift with every generator pass; freezing them
in this doc was painful to maintain and the script makes the
diagnostic cheap.

### Learning page (menu)

A new **Learning** menu entry is added next to Help. It serves as a
rule reference + memory-refresher tool.

For each constraint (the 12 slugs), the page shows:

- The localised **icon** + **name**.
- A status: `seen on 12 March 2026` if `firstSeen[slug] != null`,
  otherwise `not yet encountered`.
- The **number of puzzles already played** (finished, skipped
  excluded) that contained this constraint. Computed from
  `puzzles.where(p => p.played && p.skipped == null &&
  p.rules.contains(slug))` over the entire stats history (across
  every collection, not just the current one).
- A **"Refresh my memory"** button which:
  1. Re-displays the explanation modal (same content as the first-
     encounter modal — the slug isn't unlearned, `firstSeen` stays
     set).
  2. Prepares a **temporary playlist of about 10 onboarding
     puzzles** centred on the constraint. Implementation: we reuse
     the phase machinery from § 5 by simulating a state where `slug`
     was just unlocked, and sample ten unplayed puzzles that satisfy
     its introduction filter (e.g. `{FM, slug}` for slugs introduced
     via FM, `{NC, slug}` for those introduced via NC), with optional
     sprinkling.
  3. At the end of the refresh playlist, the player returns to the
     collection they had before.

This page also serves as a gateway for a player who **never went
through onboarding** (custom-only path, a player playing 6-mad out of
curiosity): they can browse the list, read each rule, and launch a
mini-walkthrough for any rule they're curious about, without
disturbing their main progress.

### Exiting onboarding

Onboarding is implicitly complete once
`progress.firstSeen.length == OnboardingPhase.allKnownSlugs` (the 12
constraints have all been encountered at least once). From that point:

- The soft filter becomes a no-op (nothing to filter, no slug left
  unknown).
- The playlist falls back to `getPuzzlesByLevel(playerLevel)` with
  no extra constraint.
- The EOP shows the standard message ("continue / switch
  collection"), without the "you haven't met every rule yet" note.

## 6. Implementation: code impact

The implementation reached a stable shape in v1.6.x. Key landing zones:

- **`lib/getsomepuzzle/model/onboarding.dart`**: 6 strict
  `OnboardingPhase` entries (FM, NC, PA, CC, RC, GS),
  `phaseLength = 5`, `phaseForCompletions(Map<String,int>)`
  selector, `puzzleEligibleForPhase` + `puzzlePassesSoftFilter`
  helpers. Flutter-free so it can be reused in `bin/`.
- **`lib/getsomepuzzle/model/database.dart`**:
  - `onboardingCompletions : Map<String,int>` (was `int` pre-v1.6),
    JSON-serialised in `SharedPreferences` under the
    `onboardingCompletions` key.
  - `notePuzzleCompleted` increments every slug in `puz.rules`
    when `currentPhase != null` and persists fire-and-forget.
  - `skipOnboarding` and `resetOnboardingProgress` both persist
    immediately to avoid the
    "loadPuzzlesFile-rebuilds-from-prefs-and-drops-the-update"
    regression.
  - `preparePlaylist` filters candidates through
    `puzzleEligibleForPhase` during strict phases (slug envelope +
    introducing slug present), then ranks the survivors with the
    plain Gaussian-cplx + variety score; falls back to
    `getPuzzlesByLevel + softFilter` after.
  - `EmptyPlaylistReason` enum + `emptyPlaylistReason` getter
    surface a localised reason under the Play button when the
    playlist is empty (onboarding mismatch, filters too strict,
    soft-filter exclusion, no puzzles loaded, …).
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
- **`widgets/learning_page.dart`** page reachable from the main menu
  next to Help: list of the 13 constraints with `firstSeen` status
  and a "refresh my memory" button that launches a short refresher
  playlist.
- **ARB entries**: `constraintExplain<Slug>` (title + body) per
  constraint, the `learning` menu label, and the
  `emptyPlaylist*` reasons for the Play-button gating message.

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
