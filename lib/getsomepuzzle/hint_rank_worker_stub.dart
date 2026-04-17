class HintRankResult {
  final List<String> ranked;
  final int usefulCount;
  HintRankResult(this.ranked, this.usefulCount);
}

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
