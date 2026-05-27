import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

class HintWorker {
  Future<String?> compute({
    required Puzzle puzzle,
    required Set<String> learnedSlugs,
  }) async => null;

  void cancel() {}

  void dispose() {}
}
