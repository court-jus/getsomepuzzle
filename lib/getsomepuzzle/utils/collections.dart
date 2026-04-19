import 'package:collection/collection.dart';

List<Set<int>> findAndPop(List<Set<int>> setlist, int value) {
  /*
    Pops the sets in setlist that contains value.
    */
  final Set<int> indices = {};
  for (var setEntry in setlist.indexed) {
    final idx = setEntry.$1;
    final candidate = setEntry.$2;
    if (candidate.contains(value)) {
      indices.add(idx);
    }
  }
  final List<Set<int>> result = [];
  for (var idx in indices.sorted((a, b) => a - b).reversed) {
    result.add(setlist.removeAt(idx));
  }
  return result;
}
