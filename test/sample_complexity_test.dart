import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';

void main() {
  test('Compute complexity for try_me sample and generate report', () {
    final file = File('assets/try_me.txt');
    final lines = file
        .readAsLinesSync()
        .where((l) => l.trim().isNotEmpty)
        .toList();

    final report = StringBuffer();
    report.writeln('# Complexity Comparison Report');
    report.writeln('');
    report.writeln(
      'Sample of ${lines.length} puzzles from default.txt with computed complexity.',
    );
    report.writeln('');
    report.writeln('## Formula');
    report.writeln('');
    report.writeln('```');
    report.writeln('new_cplx = round(cells_by_force / total_free_cells * 100)');
    report.writeln('```');
    report.writeln('');
    report.writeln('Where:');
    report.writeln('- `total_free_cells` = grid size minus pre-filled cells');
    report.writeln(
      '- `cells_by_force` = cells that could NOT be determined by constraint propagation alone',
    );
    report.writeln(
      '- If the puzzle requires backtracking (force insufficient): new_cplx = 100',
    );
    report.writeln('');
    report.writeln('## Detailed Results');
    report.writeln('');
    report.writeln(
      '| # | Dims | Old | New | Free | Prop | Force | BT | Detail |',
    );
    report.writeln(
      '|---|------|-----|-----|------|------|-------|----|--------|',
    );

    int idx = 0;
    for (final line in lines) {
      idx++;
      final parts = line.split('_');
      final dims = parts[2];
      final oldCplx = int.parse(parts.last);

      final p = Puzzle(line);
      final size = p.width * p.height;
      final prefilled = p.cellValues.where((v) => v != 0).length;
      final totalFree = size - prefilled;

      // Step 1: propagation
      final pProp = p.clone();
      int cellsByProp = 0;
      try {
        pProp.applyConstraintsPropagation();
        cellsByProp = totalFree - pProp.freeCells().length;
      } on SolverContradiction {
        // contradiction
      }

      // Step 2: force
      int cellsByForce = 0;
      bool needsBT = false;
      final pSolve = pProp.clone();
      for (int step = 0; step < 100; step++) {
        final before = pSolve.freeCells().length;
        if (before == 0) break;
        try {
          final fc = pSolve.applyWithForce();
          if (!fc) break;
          pSolve.applyConstraintsPropagation();
        } on SolverContradiction {
          break;
        }
        final after = pSolve.freeCells().length;
        cellsByForce += before - after;
        if (after == 0) break;
      }
      if (pSolve.freeCells().isNotEmpty) needsBT = true;

      final newCplx = p.computeComplexity();
      final bt = needsBT ? 'Y' : '';
      final detail = 'size=$size pf=$prefilled';

      report.writeln(
        '| $idx | $dims | $oldCplx | $newCplx | $totalFree | $cellsByProp | $cellsByForce | $bt | $detail |',
      );
    }

    // Summary statistics
    report.writeln('');
    report.writeln('## Summary');
    report.writeln('');

    // Correlation check
    final pairs = <(int, int)>[];
    for (final line in lines) {
      final parts = line.split('_');
      final oldCplx = int.parse(parts.last);
      final p = Puzzle(line);
      final newCplx = p.computeComplexity();
      pairs.add((oldCplx, newCplx));
    }

    // Group by old complexity bracket
    final brackets = <String, List<int>>{};
    for (final (old, newC) in pairs) {
      String bracket;
      if (old == 0) {
        bracket = '0';
      } else if (old <= 2)
        bracket = '1-2';
      else if (old <= 5)
        bracket = '3-5';
      else if (old <= 12)
        bracket = '6-12';
      else if (old <= 25)
        bracket = '13-25';
      else if (old <= 50)
        bracket = '26-50';
      else
        bracket = '51-100';
      brackets.putIfAbsent(bracket, () => []).add(newC);
    }

    report.writeln('| Old bracket | Avg new | Min new | Max new | Count |');
    report.writeln('|-------------|---------|---------|---------|-------|');
    for (final bracket in [
      '0',
      '1-2',
      '3-5',
      '6-12',
      '13-25',
      '26-50',
      '51-100',
    ]) {
      final vals = brackets[bracket];
      if (vals == null) continue;
      final avg = (vals.reduce((a, b) => a + b) / vals.length).round();
      final mn = vals.reduce((a, b) => a < b ? a : b);
      final mx = vals.reduce((a, b) => a > b ? a : b);
      report.writeln('| $bracket | $avg | $mn | $mx | ${vals.length} |');
    }

    File('docs/complexity_report.md').writeAsStringSync(report.toString());
    print('Report written to docs/complexity_report.md');
    print('Sample size: ${lines.length}');
  });
}
