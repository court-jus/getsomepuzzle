import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/main.dart';
import 'package:getsomepuzzle/widgets/cell.dart';
import 'package:getsomepuzzle/widgets/puzzle.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('manual mode does not auto-switch when all cells are filled', (
    tester,
  ) async {
    await prepareApp({
      'settingsValidateType': 'manual',
      'settingsShowRating': 'no',
    });
    setTestViewport(tester);

    await tester.pumpWidget(const MyApp());
    await pumpUntil(
      tester,
      () => find.byType(PuzzleWidget).evaluate().isNotEmpty,
    );
    final initialCellCount = find.byType(CellWidget).evaluate().length;
    expect(initialCellCount, 9, reason: 'tutorial puzzle 1 is 3x3');

    // Before filling: validate button is disabled (puzzle incomplete).
    final buttonBefore = tester.widget<TextButton>(
      find.widgetWithIcon(TextButton, Icons.check),
    );
    expect(buttonBefore.onPressed, isNull);

    // Fill cells 1..8 with a tap each. Correctness does not matter — only
    // completeness does. In manual mode the completion never fires a
    // switch without the explicit validate button click.
    for (int i = 1; i < 9; i++) {
      await tester.tap(find.byType(CellWidget).at(i));
      await tester.pump();
    }

    // Give the completion-debounce window a chance to expire. In an
    // auto-validation mode this would already have switched puzzles.
    await tester.pump(const Duration(seconds: 2));

    expect(
      find.byType(CellWidget),
      findsNWidgets(9),
      reason:
          'manual mode must not auto-advance to the next puzzle even '
          'after the usual completion debounce elapses',
    );
    // The manual validate button is now enabled (puzzle is complete).
    final buttonAfter = tester.widget<TextButton>(
      find.widgetWithIcon(TextButton, Icons.check),
    );
    expect(
      buttonAfter.onPressed,
      isNotNull,
      reason: 'completing the grid must enable the manual validate button',
    );
  });
}
