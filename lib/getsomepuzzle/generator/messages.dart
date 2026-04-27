import 'package:getsomepuzzle/getsomepuzzle/generator/generator.dart';

/// Message types sent from the worker to the UI or CLI.
sealed class GeneratorMessage {}

class GeneratorProgressMessage extends GeneratorMessage {
  final GeneratorProgress progress;
  GeneratorProgressMessage(this.progress);
}

class GeneratorPuzzleMessage extends GeneratorMessage {
  final String puzzleLine;
  GeneratorPuzzleMessage(this.puzzleLine);
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
