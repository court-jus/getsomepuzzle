import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/complicity.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    print('Usage: dart run bin/solve_no_force.dart <puzzleLine>');
    return;
  }
  final p = Puzzle(args.first);
  print('Initial state (${p.width}x${p.height}):');
  _printGrid(p);

  int step = 0;
  for (; step < 1000; step++) {
    final m = p.findAMove(checkErrors: false, tryForce: false);
    if (m == null) break;
    if (m.isImpossible != null) {
      print('IMPOSSIBLE at step $step');
      break;
    }
    final src = m.givenBy is Complicity
        ? m.givenBy.serialize()
        : m.givenBy.runtimeType.toString();
    p.setValue(m.idx, m.value);
    final r = m.idx ~/ p.width;
    final c = m.idx % p.width;
    print('Step ${step + 1}: ($r,$c) = ${m.value} [$src]');
    if (p.complete) {
      print('SOLVED.');
      return;
    }
  }
  print('');
  print('Stuck after $step propagation+complicity moves.');
  print('State where force would kick in:');
  _printGrid(p);
  final freeCount = p.freeCells().length;
  print('Empty cells remaining: $freeCount');
}

void _printGrid(Puzzle p) {
  for (int r = 0; r < p.height; r++) {
    final row = <String>[];
    for (int c = 0; c < p.width; c++) {
      final v = p.cellValues[r * p.width + c];
      row.add(v == 0 ? '.' : v.toString());
    }
    print('  ${row.join(' ')}');
  }
}
