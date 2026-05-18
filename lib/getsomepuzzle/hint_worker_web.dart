import 'dart:async';

import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/hint_worker_core.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

class HintWorker {
  bool _cancelled = false;

  Future<List<String>> compute({required Puzzle puzzle}) async {
    _cancelled = false;
    final ctx = HintContext.forPuzzle(puzzle);
    final validConstraints = <String>[];

    int processed = 0;
    for (final entry in constraintRegistry) {
      final allParameters = entry.generateAllParameters(
        ctx.puzzle.width,
        ctx.puzzle.height,
        ctx.puzzle.domain,
        ctx.readonlyIndices,
      );
      for (final param in allParameters) {
        if (_cancelled) return validConstraints;

        final serialized = classifyHintCandidate(ctx, entry.slug, param);
        if (serialized != null) validConstraints.add(serialized);

        // Yield to event loop periodically so the UI stays responsive.
        processed++;
        if (processed % 100 == 0) {
          await Future.delayed(Duration.zero);
        }
      }
    }

    return validConstraints;
  }

  void cancel() {
    _cancelled = true;
  }

  void dispose() {
    cancel();
  }
}
