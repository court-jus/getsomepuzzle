import 'dart:async';

import 'hint_rank_worker_core.dart';

export 'hint_rank_worker_core.dart' show HintRankResult;

class HintRankWorker {
  bool _cancelled = false;

  Future<HintRankResult> rank({
    required int width,
    required int height,
    required List<int> domain,
    required List<int> cellValues,
    required List<String> existingConstraints,
    required List<String> candidateConstraints,
  }) async {
    _cancelled = false;

    final (puzzle, baselineMoves) = prepareRanking(
      width: width,
      height: height,
      domain: domain,
      cellValues: cellValues,
      existingConstraints: existingConstraints,
    );

    final useful = <(String, int)>[];
    final notUseful = <String>[];

    int processed = 0;
    for (final cs in candidateConstraints) {
      if (_cancelled) {
        notUseful.addAll(
          candidateConstraints.skip(useful.length + notUseful.length),
        );
        break;
      }

      final score = scoreCandidate(puzzle, cs, baselineMoves);
      if (score != null) {
        useful.add((cs, score));
      } else {
        notUseful.add(cs);
      }

      processed++;
      if (processed % 5 == 0) {
        await Future.delayed(Duration.zero);
      }
    }
    // Sort useful candidates by descending score so the hint button
    // surfaces the constraint that unlocks the most cells first.
    useful.sort((a, b) => b.$2.compareTo(a.$2));

    return HintRankResult([
      ...useful.map((e) => e.$1),
      ...notUseful,
    ], useful.length);
  }

  void cancel() {
    _cancelled = true;
  }

  void dispose() {
    cancel();
  }
}
