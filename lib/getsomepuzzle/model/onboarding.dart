import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';

/// Phase definitions for the new-player onboarding.
///
/// Each phase narrows the catalog to a subset of constraint slugs and
/// nominates one slug as "currently being introduced". The playlist
/// sampler biases ~80 % of picks toward puzzles containing the
/// `introducing` slug and ~20 % toward refresh puzzles using only the
/// previously-unlocked slugs.
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

/// Soft-filter check: a puzzle passes when at most one of its declared
/// slugs is unseen by the player. The unseen count is computed via
/// [isFirstTimeForSlug], which the caller wires to
/// `ConstraintProgress.isFirstTimeFor` in the live app and to a fixed
/// set in tests.
///
/// Used after the strict phases to keep introducing new constraints
/// gradually while letting the player roam freely across collections.
/// A puzzle with zero unseen slugs trivially passes (refresh) — the
/// filter only kicks in to block multi-new puzzles.
bool puzzlePassesSoftFilter(
  Iterable<String> declaredRules,
  bool Function(String slug) isFirstTimeForSlug,
) {
  int unseen = 0;
  for (final s in declaredRules) {
    if (s.isEmpty || s == 'TX') continue;
    if (isFirstTimeForSlug(s)) {
      unseen++;
      if (unseen > 1) return false;
    }
  }
  return true;
}

/// Whether the puzzle's declared slug set is allowed under [phase].
/// Puzzles with at least one slug outside [OnboardingPhase.allowed]
/// are filtered out by the onboarding sampler.
bool puzzleEligibleForPhase(
  Iterable<String> declaredRules,
  OnboardingPhase phase,
) {
  for (final s in declaredRules) {
    if (s.isEmpty || s == 'TX') continue;
    if (!phase.allowed.contains(s)) return false;
  }
  return true;
}
