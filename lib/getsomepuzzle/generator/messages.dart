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

class GeneratorDoneMessage extends GeneratorMessage {
  final int totalGenerated;
  GeneratorDoneMessage(this.totalGenerated);
}
