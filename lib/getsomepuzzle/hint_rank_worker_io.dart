import 'dart:async';
import 'dart:isolate';

import 'hint_rank_worker_core.dart';

export 'hint_rank_worker_core.dart' show HintRankResult;

class HintRankWorker {
  Isolate? _isolate;

  Future<HintRankResult> rank({
    required int width,
    required int height,
    required List<int> domain,
    required List<int> cellValues,
    required List<String> existingConstraints,
    required List<String> candidateConstraints,
  }) async {
    final receivePort = ReceivePort();

    _isolate = await Isolate.spawn(
      _isolateEntryPoint,
      _RankParams(
        sendPort: receivePort.sendPort,
        width: width,
        height: height,
        domain: domain,
        cellValues: cellValues,
        existingConstraints: existingConstraints,
        candidateConstraints: candidateConstraints,
      ),
    );

    final result = await receivePort.first as Map<String, dynamic>;
    receivePort.close();
    _isolate = null;
    return HintRankResult(
      (result['ranked'] as List).cast<String>(),
      result['usefulCount'] as int,
    );
  }

  void cancel() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }

  void dispose() {
    cancel();
  }
}

class _RankParams {
  final SendPort sendPort;
  final int width;
  final int height;
  final List<int> domain;
  final List<int> cellValues;
  final List<String> existingConstraints;
  final List<String> candidateConstraints;

  _RankParams({
    required this.sendPort,
    required this.width,
    required this.height,
    required this.domain,
    required this.cellValues,
    required this.existingConstraints,
    required this.candidateConstraints,
  });
}

void _isolateEntryPoint(_RankParams params) {
  final (puzzle, baselineMoves) = prepareRanking(
    width: params.width,
    height: params.height,
    domain: params.domain,
    cellValues: params.cellValues,
    existingConstraints: params.existingConstraints,
  );

  final useful = <String>[];
  final notUseful = <String>[];
  for (final cs in params.candidateConstraints) {
    if (classifyCandidate(puzzle, cs, baselineMoves)) {
      useful.add(cs);
    } else {
      notUseful.add(cs);
    }
  }

  params.sendPort.send({
    'ranked': [...useful, ...notUseful],
    'usefulCount': useful.length,
  });
}
