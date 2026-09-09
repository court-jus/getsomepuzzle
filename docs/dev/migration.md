# Migration 1.6.22 → 2.0.0 — player data & onboarding

Analysis of what happens to a **player** upgrading from the published
`1.6.22` (`v1.6.22` tag, commit `bb2def1`) to the upcoming `2.0.0`
(pubspec `2.0.0+13`; this analysis is against `develop` HEAD `f2c9378`).
Scope: stats, settings, onboarding. No code changes proposed here —
this page records the facts and the open risks.

Headline verdict:

- **Stats are not lost on read**: storage path, file format and parser
  are unchanged; every `1.6.22` row parses and is kept, and — after
  the metadata-preservation fix (§1.4) — rows round-trip through the
  2.0.0 flush **verbatim**, ratings/hints/skip markers included. The
  only data the upgrade cannot recover is replay history, which
  1.6.22 itself collapsed to one row per puzzle before this upgrade.
  Plays are flushed at completion (`_onPuzzleCompleted` →
  `writeStats`), covering the end-of-batch and rating screens;
  puzzles never completed or skipped are not recorded (same as
  1.6.22).
- **Settings are preserved**: every `SharedPreferences` key is kept;
  2.0.0 only adds keys, each with a safe default. Player level may be
  re-derived once at first boot from a wider sample (formula unchanged).
- **Onboarding never restarts**: mid-onboarding progress is remapped
  onto the new 9-phase sequence (CC/RC merged); completed players
  re-enter soft discovery for the 8 new rules and get one
  explanation modal per new rule; the third colour (purple) is a
  separate opt-in suggestion gated on 50 post-graduation plays.

Baseline refs: `v1.6.22` = `bb2def1`; engine registry grew from
17 to 25 slugs (`lib/getsomepuzzle/constraints/registry.dart`).

---

## 1. Stats

### 1.1 Where they live (identical in both versions)

| Platform | Location | Read rule |
|---|---|---|
| native | `ApplicationDocumentsDirectory/getsomepuzzle/stats.txt` (+ any `stats*` file in that dir) | every file whose path contains `…/getsomepuzzle/stats` (`Database._readRawStatsFromStorage`) |
| web | `SharedPreferences` | every key starting with `stats` (`stats`, `stats_imported_<ts>`) |

2.0.0 adds an optional **custom sync directory**
(`Settings.statsDirectory` → `Database.statsDirectory`, pref
`settingsStatsDirectory`). Writes go to the custom dir when set
(single source of truth, to avoid split-brain with a sync tool);
**reads always scan both** the legacy dir and the custom dir, so
existing local stats are never lost when the setting is first used.
Clearing the custom dir flushes the merged history back to the legacy
location first (`clearStatsDirectory` → `writeStatsToDefaultLocation`).

### 1.2 Line format — unchanged

`StatEntry.parse` / `toString` are **byte-identical** in 1.6.22 and
2.0.0 (`lib/getsomepuzzle/model/stats.dart`):

```
<finished ISO-8601 | unfinished> <dur>s <fail>f <puzzleLine> - <SLD> - <skip> - <like> - <dislike> - <pleasure> <h>h <e>e <fc>fc <lg>lg
```

Extra fields are suffix-tagged and looked up by suffix, so old lines
parse with defaults for newer fields and future fields slot in
without breaking parsers. Nothing rewrites the file **at read time**:
the first write happens when the player completes their first
puzzle, which triggers the flush described in §1.3.

### 1.3 What changes in 2.0.0

- **Full play history.** 1.6.22 `writeStats` deduped by
  `canonicalPuzzleKey` → one row per puzzle (latest play wins);
  2.0.0 dedupes by `(finished|unfinished) + canonicalPuzzleKey`
  (`_mergedStatHistory`), so distinct completion timestamps become
  distinct rows. Consequence for the upgrade: `1.6.22` rows were
  already collapsed — each becomes the *first* history row of its
  puzzle. Replays **before** the upgrade are not recoverable; replays
  **after** the upgrade accumulate.
- **Flush cadence = every completed puzzle, not a hand-out.**
  `writeStats()` runs from `main.dart _onPuzzleCompleted` — the single
  callback every finish path converges on (automatic check,
  manual-next FAB, rating advance, mid-solve settings change) — and it
  fires **before** the EndOfPlaylist or rating screen is shown, so a
  play completed on the last puzzle of a batch is on disk even if the
  player quits at that screen without pressing Continue. During 2.0.0
  development the flush had been moved into `Database.next()` (which
  skipped the end-of-batch hand-out) after commit `2271962`
  ("Don't re-write the stats every minute (#34)", 2026-07-01) removed
  1.6.22's 60 s `Timer.periodic` (`main.dart` `_saveTimer`) — this
  doc accompanies the fix that moved the call to the completion
  callback. Residual non-persisted plays: puzzles abandoned
  mid-puzzle or skipped — neither 1.6.22 nor 2.0.0 ever emitted rows
  for them (`getStats` only surfaces puzzles whose `stop()` ran), so
  nothing regressed there.
- **Counters collapse at load.** `loadStats` folds the full history
  back to one entry per puzzle (most recent finished play,
  `_isMoreRecentPlay`) before deriving `played`/`finished`/`skipped`
  flags, per-slug play counts, usable-plays counters and the
  `firstSeen` rebuild. So the multi-row file does not inflate any
  counter; per-puzzle behaviour matches 1.6.22 exactly.
- **Matching is by structural identity, not serialization.**
  `loadStats` indexes with `identityKey` (domain, dims, prefill,
  sorted constraint tokens — version prefix, solution, cplx and
  `_p:` dropped); `canonicalPuzzleKey` additionally walks the 4
  rotations and re-serializes through `Puzzle` so in-memory
  constraint merges (LT per-letter, PA same-axis) are applied before
  keying. Old stats lines keep matching the 2.0.0 catalog even when
  solutions, cplx or constraint order changed. Measured on the entry
  catalog: 4,508 of the 7,229 unique 1.6.22 `1-easy` identity keys
  (62 %) are still present in HEAD `assets/1-easy.txt`; removed
  puzzles' rows stay harmlessly in the file.
- **Player level.** The stored level pref (`settingsPlayerLevel`) is
  untouched. Auto-level (`settingsAutoLevel`, default true) now
  recomputes **at every boot** (`main.dart` `initialize()`), where
  1.6.22 only recomputed when the playlist was empty. The skill
  formula is unchanged, but the sample widened from *the current
  collection's* played puzzles (1.6.22) to *the global last-50
  finished plays across all collections* with per-play winsorization
  (`Database.computePlayerLevel`). Expect a possible one-time level
  adjustment for players whose history spans several collections.

### 1.4 Verdict on "are the stats lost?"

Preserved by the upgrade itself: all rows (timestamps, durations,
failures, puzzle identity), played/finished/skipped states, per-slug
and per-puzzle aggregates, level inputs, first-seen derivation. After
the two fixes below, the upgrade is **fully lossless**: 1.6.22 files
already hold one full row per puzzle (ratings, hints, click
analytics, skip markers included), and 2.0.0 round-trips those rows
byte-for-byte.

1. **Persistence is per-completion, covering every finish path.** All
   completions funnel into `main._onPuzzleCompleted` (automatic
   check, manual-next FAB, rating advance, switching away from manual
   mode mid-solve), which calls `writeStats()` before the
   EndOfPlaylist / rating screen appears — so the final play of a
   batch survives a quit at either screen. (An earlier 2.0.0
   incarnation flushed from `Database.next()` instead, which skipped
   that case; see §1.3.) The only plays not persisted are puzzles
   abandoned mid-puzzle or skipped, which `writeStats` never emitted
   under 1.6.22 either (`getStats` only surfaces puzzles whose
   `stop()` ran).
2. **Play metadata survives the flush verbatim.** The 2.0.0 merge
   (`_mergedStatHistory`) used to re-serialize every already-stored
   row through `StatEntry.toString()` — the minimal 4-field form
   (`finished dur fail puzzleLine`) — which dropped
   skip/like/dislike markers, pleasure, hints and click analytics of
   every row not re-emitted by the in-memory `PuzzleData` of the
   currently loaded collection on the first flush; and the loader
   never re-hydrated `cellEdits`/`firstClickMs`/`longestGapMs`, so
   even covered rows lost those three fields. Fixed:
   - `StatEntry` retains the **raw line** it was parsed from
     (`raw`, set by `StatEntry.parse`) and exposes `fullLine()`;
     `_mergedStatHistory` persists `fullLine()` instead of
     `toString()`, so stored rows round-trip byte-for-byte (this
     also stops imported rows from being minimalized on the next
     flush);
   - `loadStats` hydrates `cellEdits`/`firstClickMs`/
     `longestGapMs` onto the in-memory puzzle, so the flush overlay
     (`getStats()` → `PuzzleData.getStat()`) reproduces the same
     values instead of zeroing them.
   Regression tests in `test/stats_persistence_test.dart` cover both
   halves (non-active-collection rows keep metadata across a flush;
   the loaded collection's latest play keeps click analytics).
   Cost of the fix: persisted rows grow ~25–40 % (the `- SLD -`
   block + extras); native storage impact is negligible, web rows
   live in a `SharedPreferences` `StringList` (localStorage ~5 MB
   quota) and full-history growth there is worth watching.

---

## 2. Settings

### 2.1 Key inventory — all additions, no removals

Diffing every `SharedPreferences` access between `v1.6.22` and HEAD,
2.0.0 only **adds** keys (each read with a default and written back):

| Key | Default | Meaning |
|---|---|---|
| `settingsNextPuzzleDelay` | `s1` | delay before auto-advance after a solve (`s1|s3|s10|manual`) |
| `settingsGrayoutEnabled` | `true` | disable grayout of completed constraints |
| `settingsStatsDirectory` | unset (`null`) | custom stats sync directory (removed from prefs when cleared) |
| `settingsThemeMode` | `system` | `system|light|dark|beige` |
| `wantedDomainsFilter` | `{}` | domain flags selector (`d2`/`d3`), see §2.3 |
| `bannedDomainsFilter` | `{"d3"}` | see §2.3 |
| `wantedScenarioFilter` | unset (`null`) | reasoning-style (scenario) filter |

Loaders guard against unknown enum spellings with
`firstWhere(…, orElse: default)`, and `Filters.load` already cleaned
the obsolete `minCplxFilter`/`maxCplxFilter` keys in 1.6.22 (the
cleanup call is kept). No stored key changed name or meaning, so all
1.6.22 settings carry over: validation/live-check/rating/hint/idle
modes, `playerLevel`, `autoLevel`, `shouldShuffleCollection`,
`collectionToLoad`, `locale`, all size/flag/rule filters, and the
`constraintFirstSeen` / `onboardingCompletions` maps.

Two visible consequences:

- **Appearance.** `settingsThemeMode` defaults to `system` for
  everyone. The `light` palette is the legacy v1.6.22 look
  (`app_theme.dart`, theming doc), so light-OS players see the same
  colours; on dark-mode OSes the app now renders dark (new feature),
  and `beige` (the solarized palette) is manual-only. Nothing is
  reset; players who dislike the default can switch in Settings.
- **Purple is hidden until opted in.** `bannedDomainsFilter` defaults
  to `{"d3"}` on missing key, so a 1.6.22 player (who never had the
  key) and a fresh player both start with every 3-colour puzzle
  (`v2_123_…` lines — 8,083 of the 20,241 `1-easy` lines at HEAD)
  filtered out, exactly like the pre-upgrade two-colour catalogue.
  §3.5 describes how players are invited to enable it.

### 2.2 Stats directory auto-clear

At boot, a configured `statsDirectory` is validated; if the path is
inaccessible (e.g. a pre-SAF path saved on Android 11+), the merged
history is flushed back to the default location, the pref is cleared
and a snackbar informs the player (`main.dart`
`_validateAndAutoClearStatsDir`). This targets 2.0.0 exp users — the
setting did not exist in 1.6.22.

### 2.3 Verdict on "are the settings lost?"

No. Additive keys with safe defaults; nothing renames or repurposes
an existing key; enum loaders fall back to defaults on unknown
values. The only *perceived* changes are new defaults the player can
flip (theme, grayout, next-puzzle delay) and the temporarily pinned
rule filters while soft discovery is active (§3.4).

---

## 3. Onboarding

### 3.1 Model recap (unchanged architecture)

- `ConstraintProgress.firstSeen` — `SharedPreferences`
  `constraintFirstSeen` (JSON `slug → ISO date`), **rebuilt from
  stats** on every load: each finished, non-skipped play marks every
  slug it declares as seen at `min(existing, finished)`.
- `Database.onboardingCompletions` — `SharedPreferences`
  `onboardingCompletions` (JSON `slug → count`); drives
  `phaseForCompletions`.
- The playlist enforces onboarding through a visible filter preset
  (`recommendedOnboardingFilters`) written into `currentFilters`
  (rule chips), re-pinned at every boot while in onboarding
  (cross-session guard in `loadPuzzlesFile`) and after every
  completed puzzle (`notePuzzleCompleted`).
- New-rule explanation modals fire on **puzzle open** when the puzzle
  declares a slug with `firstSeen == null`
  (`main.dart _surfaceNewConstraintsIfAny`); dismissing marks the slug
  seen. Axis-variant pairs `CC↔RC`, `RT↔CT`, `JC↔JR` share one
  concept: the modal collapses to the display slug and marks every
  sibling seen (`mergedRuleGroups`, `hiddenSlugs = {RC, JR, CT}` —
  user-facing names are always the column variant).
- `OnboardingPhase.allKnownSlugs` = all registered slugs (25 at
  HEAD). Onboarding (strict or soft) ends when every slug has a
  first-seen date.

### 3.2 The 2.0.0 new-player sequence (for reference)

Nine strict phases × 5 finished plays (was ten in 1.6.22 — **CC and
RC now share one phase**, `OnboardingPhase.phases`): FM, NC, PA,
CC(+RC, combined count), GS, EY, DF, LT, QA. Eligible source is the
entry catalog (`1-easy` ∪ `1-easy-overfilled`, the latter augmented
while `currentPhase != null`). After QA, soft discovery introduces
the remaining slugs in registry order (RC, RT, MI, SY, SH, JC, CH,
CT, GC, MJ, IM, IS, JR, BB, RE, SZ) with the "≤ 1 new rule" contract,
cadenced injection for scarce rules (~every 10–15 plays;
`softElectedInjectPeriod`) and a widened pool one difficulty level up
(e.g. BB only exists from `2-player`). The merge also relaxed phase 3
eligibility: during the CC phase, puzzles declaring **either** CC or
RC satisfy the "introducing slug present" condition
(`puzzleEligibleForPhase`).

### 3.3 Players mid-onboarding on 1.6.22

`onboardingCompletions` survives verbatim; 2.0.0 re-derives the phase
with `phaseForCompletions` against the new table. RC completions
count toward the merged CC phase
(`(completions['CC'] ?? 0) + (completions['RC'] ?? 0) >= 5`).

| 1.6.22 position (10 phases) | 2.0.0 position (9 phases) |
|---|---|
| P0 FM … P2 PA | unchanged (same slugs, same counts, same index) |
| P3 CC (CC count < 5) | P3 merged CC/RC — same envelope `{FM, PA, NC, CC, RC}`, RC puzzles newly eligible; needs CC+RC ≥ 5 |
| P4 RC (CC = 5, RC < 5) | advances straight past the merged phase if CC+RC ≥ 5 → lands in P4 GS |
| P5 GS … P9 QA | same slugs and requirements, index shifted by −1 (GS → P4 … QA → P8) |
| soft mode (post-P9) | still soft mode; discovery list extended with the 8 new slugs |

Net effect: nobody is pushed back a phase; the only change is that a
player who had completed the old CC phase but was still inside the old
RC phase has the remainder of their RC practice folded into the merged
phase (their RC first-seen dates come from the stats rebuild, so no
explanation modal re-fires for RC). Their rule chips are re-pinned to
the 2.0.0 preset at the next boot, as they were under 1.6.22.

### 3.4 Players who completed onboarding on 1.6.22

On the first 2.0.0 launch, for a fully graduated 1.6.22 player:

1. `currentPhase` is null (all strict counts ≥ 5 — the merged CC/RC
   count stays ≥ 5) and `onboardingCompletedAt` (a 2.0.0 key) is
   absent → `loadPuzzlesFile` **backfills it to "now"** so the
   third-colour gate (§3.5) has a baseline.
2. `firstSeen` is rebuilt from stats and covers the 17 old slugs.
   `allKnownSlugs` is now 25 → `firstSeen.length < allKnownSlugs` →
   `_softFilterActive` flips back on: the player **re-enters soft
   discovery** (their `isInOnboarding` is true again).
3. `recommendedOnboardingFilters` is non-null again → the rule chips
   (`wantedRules`/`bannedRules`) are **overwritten with the soft
   preset at every boot and after every completion** until discovery
   ends. Size/flag/domain filters are untouched; only rule chips are
   pinned (they are visible and editable in the Open page, but the
   preset is re-applied — custom pre-upgrade rule filters are
   superseded, not lost to disk, but the preset must not be fought).

The 8 new rules (BB, IM, IS, JC, JR, MI, RE, SZ) are introduced **one
modal at a time, in registry discovery order**, exactly like the
post-strict rules they already met in 1.6.22:

| step | slug(s) surfaced | entry-catalog availability (2-colour lines) |
|---|---|---|
| 1 | MI | 178 in `1-easy` (+ 78 `2-player`) |
| 2 | JC — one modal marks JR seen too | 1,394 / 1,250 |
| 3 | IM | 3,138 |
| 4 | IS | 87 (+ 224 `2-player`) |
| 5 | BB | none in `1-easy` → widened pool (`2-player`, 71) |
| 6 | RE | 47 (+ 38) |
| 7 | SZ | 44 (+ 50) |

Elected rules are *allowed* in every draw (the preset bans only the
other unseen slugs), so common rules (IM, JC) surface naturally
within a batch or two; scarce ones (MI, BB, RE, SZ) are guaranteed by
the cadenced injection. Dismissing each modal marks the slug seen;
the merged-sibling loop marks JC and JR together. There is **no
re-run of strict phases** for these players. Once the last unseen
slug is marked (SZ), `isInOnboarding` flips false,
`OnboardingCompleteDialog` fires again, and `resetRuleFilters`
clears the rule chips back to the empty default. (Because JC/JR, and
MI's absence from the strict sequence, land mid-list, a full 1.6.22
graduate re-learns 8 rules over roughly 50–90 plays; mid-soft 1.6.22
players who had not met every 1.6.22 slug simply have a longer
unseen list — the same mechanism handles it.)

**Purple is not part of this discovery** — it is a colour domain, not
a rule, and it is gated separately (§3.5). Returning players never
see a purple grid by accident: the `d3` domain ban applies through
the whole onboarding preset (presets only touch rule chips).

### 3.5 Introducing the third colour (purple) to returning players

Not a modal-on-first-contact like rules. The trigger is
`Database.shouldSuggestThirdColor`, evaluated after each puzzle open
when no new-rule modal fired; all four conditions must hold:

1. `thirdColorSuggestionShown` is false (pref `thirdColorSuggestionShown`);
2. `hasPlayedThirdColor` is false (pref, also re-derived from stats
   history both ways — a reinstall or a stats reset cannot
   desynchronise it);
3. `currentPhase == null` **and** `onboardingCompletedAt != null`;
4. `postOnboardingCompletions >= 50` (pref `postOnboardingCompletions`,
   incremented per finished play once `currentPhase == null`,
   backfilled from stats rows whose finish is after
   `onboardingCompletedAt`).

Because the graduation timestamp is backfilled to the first 2.0.0
launch, a 1.6.22 graduate's **pre-upgrade plays do not count toward
the 50** — the counter deliberately starts at zero on 2.0.0 ("so the
50-plays gate starts counting from their first launch on this
version", `loadPuzzlesFile`). Soft-mode plays count too, so the
suggestion typically lands **mid-discovery** (≈ 50 plays in, while
the new rules take ≈ 10–15 plays each to surface) — it is independent
of discovery state: only the graduation timestamp and the play
threshold matter.

The `ThirdColorSuggestionDialog`:

- **"Try it"** → `bannedDomains` swaps `d3`→`d2` ban
  (`bannedDomains = {d2}`), i.e. the next batch is 3-colour only —
  not a mix — and the in-progress 2-colour puzzle is dropped for a
  fresh one. Reversible anytime from the Open-page domain chips.
- **"Later"** → the modal is marked shown and **never fires again**
  (`noteThirdColorSuggestionShown` regardless of the button); the
  player can still opt in via the domain filter.
- Replaying onboarding re-arms the suggestion
  (`resetOnboardingProgress` clears `thirdColorSuggestionShown`) but
  never clears `hasPlayedThirdColor` (it is history-derived).
- A player who *has* played 3-colour puzzles (e.g. opted in during a
  2.0.0 exp build) is never suggested to.

### 3.6 What never happens on upgrade

No strict-phase replay for graduates, no `tutorial`/`TX` regression
(`TX` is stripped from identity keys so legacy lines still match),
no stats wipe, no firstSeen wipe (`constraintFirstSeen` is kept and
stats keep it convergent), no re-show of the first-run welcome
(`WelcomeDialog` fires only when `firstSeen` is empty — §3.7).

### 3.7 Numbered intro dialogs (#0 welcome, #1 release notes)

Intro/release dialogs are tracked by a single persisted counter,
`introDialogSeen` (SharedPreferences int, absent on pre-2.0.0
installs), storing the highest dialog number the player has seen;
at most one dialog is shown per session, in order.

- **#0 — first-run welcome** (`WelcomeDialog`): unchanged trigger —
  fires when a puzzle with an unseen rule opens while `firstSeen` is
  empty (fresh install, and onboarding replay, which clears
  `firstSeen`). After it is dismissed, the player is bumped straight
  to the latest dialog number, so release dialogs never fire for
  players who installed the current version.
- **#1 — 2.0.0 release notes** (`ReleaseNotesDialog`, new): shown
  once to **returning players only** — the check requires play
  history (`firstSeen` non-empty) — on their first puzzle open after
  the upgrade. An absent counter on such a player means "has seen up
  to #0" (the 1.6.22 welcome), so #1 is offered, then the counter is
  set to 1. Future releases append #2, #3, … by raising the
  `_latestIntroDialogNumber` constant in `main.dart` and routing the
  new number in `_showIntroDialog`; a player who skips several
  releases catches up one dialog per launch.

Upgrade experience: a 1.6.22 player's first 2.0.0 puzzle shows the
release-notes dialog once (possibly after the first new-rule
explanation modal, since both chain off puzzle open), never the
welcome again.

---

## 4. Pre-release checklist

1. **DONE — flush moved to the completion callback.** `writeStats()`
   now runs from `main._onPuzzleCompleted` (every finish path),
   closing the end-of-batch / rating-screen quit gap that the
   `Database.next()`-based flush had. Remaining non-persisted plays
   are only puzzles never completed or skipped — same as 1.6.22.
2. **DONE — metadata survives the flush.** `StatEntry` retains its
   raw line, `_mergedStatHistory` persists `fullLine()`, and
   `loadStats` hydrates the click-analytics fields; covered by
   regressions in `test/stats_persistence_test.dart` (§1.4 item 2).
   Watch web `SharedPreferences` growth over time.
3. **Verify the merged CC/RC phase mapping for 1.6.22 RC-phase
   players is intended** (§3.3): CC+RC ≥ 5 lets a player who had
   completed CC but only started RC skip the rest of their RC
   practice. Consistent with "CC/RC are one concept now", but worth
   an explicit sign-off.
4. **Doc drift**: `docs/dev/onboarding.md` still documents the
   un-merged 10-phase table (P3 CC / P4 RC, "P0–P9", post-strict list
   with 15 entries) and `docs/dev/index.md` gains this page. Re-sync
   onboarding.md before release (phase table, merged pairs,
   `OnboardingCompleteDialog`/purple-gate sections already partially
   covered). The stale flush references (the `_mergedStatHistory`
   "periodic 60 s flush" comment in `database.dart`, and
   `docs/dev/crossplay.md`'s "periodic `writeStats` timer" sentence)
   were corrected as part of the flush move; crossplay.md now
   describes the completion-callback caller.
5. **Confirm filter takeover duration for returners** (§3.4): rule
   chips are pinned to the soft preset from first 2.0.0 boot until the
   last new slug is seen (~50–90 plays for a full graduate); a player
   who fights the preset mid-discovery is overridden at the next
   completion/boot by design.

---

## Appendix — SharedPreferences keys: 1.6.22 → 2.0.0

Kept unchanged (all of 1.6.22's set): `collectionToLoad`,
`shouldShuffleCollection`, `locale`, `settingsValidateType`,
`settingsLiveCheckType`, `settingsShowRating`, `settingsHintType`,
`settingsIdleTimeout`, `settingsPlayerLevel`, `settingsAutoLevel`,
`min/maxWidthFilter`, `min/maxHeightFilter`, `min/maxPrefilledFilter`,
`wantedRulesFilter`, `bannedRulesFilter`, `wantedFlagsFilter`,
`bannedFlagsFilter`, `constraintFirstSeen`, `onboardingCompletions`,
`onboardingFiltersApplied`, `stats` (web) / `stats*.txt` files.

Added by 2.0.0: `settingsNextPuzzleDelay`, `settingsGrayoutEnabled`,
`settingsStatsDirectory`, `settingsThemeMode`, `wantedDomainsFilter`,
`bannedDomainsFilter`, `wantedScenarioFilter`,
`onboardingCompletedAt`, `postOnboardingCompletions`,
`hasPlayedThirdColor`, `thirdColorSuggestionShown`,
`introDialogSeen` (highest numbered intro dialog shown — §3.7).

Obsolete keys cleaned at load (both versions): `minCplxFilter`,
`maxCplxFilter`.
