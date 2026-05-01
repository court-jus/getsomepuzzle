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
