import 'dart:async';
import 'dart:isolate';

import 'hint_rank_worker_core.dart';

export 'hint_rank_worker_core.dart' show HintRankResult;

class HintRankWorker {
  Isolate? _isolate;
  ReceivePort? _receivePort;

  Future<HintRankResult> rank({
    required int width,
    required int height,
    required List<int> domain,
    required List<int> cellValues,
    required List<String> existingConstraints,
    required List<String> candidateConstraints,
  }) async {
    final port = ReceivePort();
    _receivePort = port;

    _isolate = await Isolate.spawn(
      _isolateEntryPoint,
      _RankParams(
        sendPort: port.sendPort,
        width: width,
        height: height,
        domain: domain,
        cellValues: cellValues,
        existingConstraints: existingConstraints,
        candidateConstraints: candidateConstraints,
      ),
    );

    try {
      final result = await port.first as Map<String, dynamic>;
      return HintRankResult(
        (result['ranked'] as List).cast<String>(),
        result['usefulCount'] as int,
      );
    } finally {
      port.close();
      if (identical(_receivePort, port)) _receivePort = null;
      _isolate = null;
    }
  }

  void cancel() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _receivePort?.close();
    _receivePort = null;
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
