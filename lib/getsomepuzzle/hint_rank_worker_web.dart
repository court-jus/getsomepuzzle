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

    final useful = <String>[];
    final notUseful = <String>[];

    int processed = 0;
    for (final cs in candidateConstraints) {
      if (_cancelled) {
        notUseful.addAll(
          candidateConstraints.skip(useful.length + notUseful.length),
        );
        break;
      }

      if (classifyCandidate(puzzle, cs, baselineMoves)) {
        useful.add(cs);
      } else {
        notUseful.add(cs);
      }

      processed++;
      if (processed % 5 == 0) {
        await Future.delayed(Duration.zero);
      }
    }

    return HintRankResult([...useful, ...notUseful], useful.length);
  }

  void cancel() {
    _cancelled = true;
  }

  void dispose() {
    cancel();
  }
}
