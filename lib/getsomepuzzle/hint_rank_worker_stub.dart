import 'hint_rank_worker_core.dart';

export 'hint_rank_worker_core.dart' show HintRankResult;

class HintRankWorker {
  Future<HintRankResult> rank({
    required int width,
    required int height,
    required List<int> domain,
    required List<int> cellValues,
    required List<String> existingConstraints,
    required List<String> candidateConstraints,
  }) async => HintRankResult(candidateConstraints, candidateConstraints.length);

  void cancel() {}

  void dispose() {}
}
