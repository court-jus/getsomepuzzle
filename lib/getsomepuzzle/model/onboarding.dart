import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';

/// Phase definitions for the new-player onboarding.
///
/// Each phase narrows the catalog to a subset of constraint slugs
/// (`allowed`) and nominates one slug as "currently being introduced".
/// During strict phases the playlist sampler only surfaces puzzles
/// that **both** stay within the allowed envelope **and** contain the
/// introducing slug — see [puzzleEligibleForPhase]. There is no
/// refresh share: refresh of already-met rules happens organically in
/// the post-strict soft-filter mode.
class OnboardingPhase {
  /// Phase index. 0 is the first phase (FM only); the last entry in
  /// [phases] is the latest defined phase.
  final int index;

  /// Slug being introduced in this phase (will appear more in
  /// proposed puzzles).
  final String introducing;

  /// Set of slugs allowed in puzzles surfaced during this phase.
  /// Puzzles whose declared slug set is **not a subset** of this are
  /// filtered out.
  final Set<String> allowed;

  const OnboardingPhase({
    required this.index,
    required this.introducing,
    required this.allowed,
  });

  static const phases = <OnboardingPhase>[
    OnboardingPhase(index: 0, introducing: 'FM', allowed: {'FM'}),
    OnboardingPhase(index: 1, introducing: 'NC', allowed: {'FM', 'NC'}),
    OnboardingPhase(index: 2, introducing: 'PA', allowed: {'FM', 'PA', 'NC'}),
    OnboardingPhase(
      index: 3,
      introducing: 'CC',
      allowed: {'FM', 'PA', 'NC', 'CC'},
    ),
    OnboardingPhase(
      index: 4,
      introducing: 'RC',
      allowed: {'FM', 'PA', 'NC', 'CC', 'RC'},
    ),
    OnboardingPhase(
      index: 5,
      introducing: 'GS',
      allowed: {'FM', 'PA', 'NC', 'CC', 'RC', 'GS'},
    ),
    // Phases for the remaining slugs (LT, QA, SY, DF, SH, CC, GC, EY)
    // are not figés as strict envelopes any more. After phase 3
    // the player enters [softFilter] mode: any level collection opens
    // up but the playlist filters out puzzles introducing more than
    // one new constraint at a time. The modal still fires per first
    // contact, so each remaining slug gets explained naturally.
  ];

  /// Number of finished, non-skipped plays a player must accumulate
  /// before crossing into the next phase. Matches
  /// [Database.playlistBatchSize] so a phase wraps up at every natural
  /// end-of-batch boundary.
  static const int phaseLength = 5;

  /// All constraint slugs the onboarding system recognises. Mirrors
  /// the registry in `lib/getsomepuzzle/constraints/registry.dart`
  /// (minus the legacy `TX` HelpText slug). Hardcoded here rather than
  /// derived to keep this file Flutter-free; adding a new constraint
  /// is a one-liner update.
  static final Set<String> allKnownSlugs = constraintRegistry
      .map((c) => c.slug)
      .toSet();

  /// Slugs not covered by [phases] (the strict-phase introducers), in
  /// the order they appear in `constraintRegistry`. Used by the soft
  /// filter to elect the next slug for the player to discover. Adding
  /// a new constraint to the registry automatically extends this list,
  /// so post-P5 discovery stays in sync with no manual bookkeeping.
  static List<String> get postStrictDiscoveryOrder {
    final strictSlugs = phases.map((p) => p.introducing).toSet();
    return constraintRegistry
        .map((c) => c.slug)
        .where((s) => !strictSlugs.contains(s))
        .toList();
  }
}

/// Returns the strict onboarding phase the player is currently in
/// based on [completions]. Returns null when the
/// player has graduated past the last defined strict phase — at that
/// point the playlist sampler enters soft-filter mode (any level
/// collection, ≤1 unseen slug per puzzle).
OnboardingPhase? phaseForCompletions(Map<String, int> completions) {
  for (var phase in OnboardingPhase.phases) {
    final slug = phase.introducing;
    final completed = completions[slug];
    if (completed == null || completed < OnboardingPhase.phaseLength) {
      // The player has not played enough puzzle with this slug
      return phase;
    }
  }
  // The player has played enough puzzle for each phase, they can move
  // on with soft filtering
  return null;
}

/// Whether the puzzle can be surfaced during the strict [phase].
///
/// Two conditions, both required:
/// 1. **Slug envelope** — every declared slug must be in
///    [OnboardingPhase.allowed]. Empty entries and the legacy `TX`
///    slug are tolerated (skipped).
/// 2. **Introducing slug present** — the puzzle must declare
///    [OnboardingPhase.introducing]. This is the "no refresh share"
///    contract: during a strict phase, every surfaced puzzle teaches
///    or re-exercises the slug currently being introduced. Refresh of
///    previously-met rules is handled in soft-filter mode (post-P5),
///    not here.
bool puzzleEligibleForPhase(
  Iterable<String> declaredRules,
  OnboardingPhase phase,
) {
  bool containsIntroducing = false;
  for (final s in declaredRules) {
    if (s.isEmpty || s == 'TX') continue;
    if (!phase.allowed.contains(s)) return false;
    if (s == phase.introducing) containsIntroducing = true;
  }
  return containsIntroducing;
}
