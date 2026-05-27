import 'dart:async';

import 'package:getsomepuzzle/getsomepuzzle/hint_worker_core.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

class HintWorker {
  bool _cancelled = false;

  /// Returns the constraint (serialized `SLUG:params`) to offer as a hint, or
  /// null when none is available. Web has no isolate, so the search runs on
  /// the main thread, yielding periodically to keep the UI responsive.
  Future<String?> compute({required Puzzle puzzle}) async {
    _cancelled = false;
    final ctx = HintContext.forPuzzle(puzzle);
    return pickHintConstraint(
      ctx,
      shouldStop: () => _cancelled,
      yieldEvery: () => Future.delayed(Duration.zero),
    );
  }

  void cancel() {
    _cancelled = true;
  }

  void dispose() {
    cancel();
  }
}
