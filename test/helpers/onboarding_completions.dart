import 'package:getsomepuzzle/getsomepuzzle/model/onboarding.dart';

/// Returns a completions map with [OnboardingPhase.phaseLength] for
/// every strict-phase slug whose index is < [phaseCount]. For example,
/// passing 3 gives completions for phases 0, 1, and 2, placing the
/// player at the start of phase 3.
Map<String, int> strictCompletionsUpTo(int phaseCount) => {
  for (final p in OnboardingPhase.phases.take(phaseCount))
    p.introducing: OnboardingPhase.phaseLength,
};
