import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';

class HintWorker {
  Future<List<String>> compute({
    required int width,
    required int height,
    required List<CellValue> domain,
    required List<CellValue> solution,
    required Set<String> existingConstraints,
    required Set<int> readonlyIndices,
  }) async => [];

  void cancel() {}

  void dispose() {}
}
