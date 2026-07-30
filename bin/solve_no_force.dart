import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/puzzle_display.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    print('Usage: dart run bin/solve_no_force.dart <puzzleLine>');
    return;
  }
  final p = Puzzle(args.first);
  print('Initial state (${p.width}x${p.height}):');
  printGrid(p);

  final moves = p.propagateToFixpoint();

  if (moves == null) {
    print('Contradiction during propagation.');
    print('Final state:');
    printGrid(p);
    return;
  }

  if (p.complete) {
    print('SOLVED after $moves propagation steps.');
    print('Solution:');
    printGrid(p);
  } else {
    print('');
    print('Stuck after $moves propagation steps.');
    print('State where force would kick in:');
    printGrid(p);
    final freeCount = p.freeCells().length;
    print('Empty cells remaining: $freeCount');
  }
}

void printGrid(Puzzle p) {
  print(formatGrid(p.cellValues, p.width, p.height));
}
