import 'package:getsomepuzzle/getsomepuzzle/generator/generator.dart';
import 'package:getsomepuzzle/getsomepuzzle/level.dart';

/// Message types sent from the worker to the UI or CLI.
sealed class GeneratorMessage {}

class GeneratorProgressMessage extends GeneratorMessage {
  final GeneratorProgress progress;
  GeneratorProgressMessage(this.progress);
}

class GeneratorPuzzleMessage extends GeneratorMessage {
  final String puzzleLine;

  /// Difficulty palier as classified by the generator's own
  /// `solveExplained` trace — the same trace it used to validate
  /// deductive uniqueness, so this comes for free.
  final PuzzleLevel level;
  GeneratorPuzzleMessage(this.puzzleLine, this.level);
}

/// Emitted whenever a worker picks a new equilibrium target for the next
/// generation attempt. [label] is null when no target is being chased
/// (equilibrium disabled or no positive-gap candidate left).
class GeneratorTargetMessage extends GeneratorMessage {
  final String? label;
  GeneratorTargetMessage(this.label);
}

class GeneratorDoneMessage extends GeneratorMessage {
  final int totalGenerated;
  GeneratorDoneMessage(this.totalGenerated);
}

/// Emitted whenever a worker's `generateOne` returns null with a
/// classifiable reason. Used by the CLI dashboard to surface why
/// attempts are failing (e.g. mostly `ratioTooHigh` → iterative loop
/// isn't picking strong-enough constraints).
class GeneratorRejectMessage extends GeneratorMessage {
  final GenerationRejectReason reason;
  GeneratorRejectMessage(this.reason);
}

/// Emitted once per `generateOne` attempt (success *or* rejection)
/// with the per-stage wall-time breakdown ([micros], microseconds)
/// AND the per-stage invocation count ([calls]). Together they let
/// the CLI dashboard compute averages like "avg µs per
/// `loop_candidate` call" — the dominant signal for "is this stage
/// worth optimising next?". Keys are stable stage names defined in
/// `PuzzleGenerator.generateOne`.
class GeneratorTimingsMessage extends GeneratorMessage {
  final Map<String, int> micros;
  final Map<String, int> calls;
  GeneratorTimingsMessage(this.micros, this.calls);
}
