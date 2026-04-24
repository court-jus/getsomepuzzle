import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/main.dart';
import 'package:getsomepuzzle/widgets/cell.dart';
import 'package:getsomepuzzle/widgets/puzzle.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/harness.dart';

/// Tap a cell [n] times. Each tap cycles the value 0 → 1 → 2 → 0, so this is
/// the only way to land on a specific non-zero value from the UI.
Future<void> _tapCell(WidgetTester tester, int idx, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.byType(CellWidget).at(idx));
    await tester.pump();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('automatic mode defers the puzzle switch until the 1s debounce', (
    tester,
  ) async {
    await prepareApp({
      // Automatic is the default; set explicitly anyway so the test is
      // self-documenting.
      'settingsValidateType': 'automatic',
      // No rating screen → completion routes straight to loadPuzzle.
      'settingsShowRating': 'no',
      // "all" keeps live error highlights; completion still flows through
      // the unified 1s debounce.
      'settingsLiveCheckType': 'all',
    });
    setTestViewport(tester);

    await tester.pumpWidget(const MyApp());
    await pumpUntil(
      tester,
      () => find.byType(PuzzleWidget).evaluate().isNotEmpty,
    );
    expect(find.byType(CellWidget), findsNWidgets(9));

    // Fill the tutorial puzzle 1 with its known solution "121121111".
    // Cell 0 is a prefilled "1" (readonly).
    await _tapCell(tester, 1, 2); // → 2
    await _tapCell(tester, 2, 1); // → 1
    await _tapCell(tester, 3, 1); // → 1
    await _tapCell(tester, 4, 2); // → 2
    await _tapCell(tester, 5, 1); // → 1
    await _tapCell(tester, 6, 1); // → 1
    await _tapCell(tester, 7, 1); // → 1
    await _tapCell(tester, 8, 1); // → 1

    // Within the 1s debounce window: still on the 3x3 puzzle.
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byType(CellWidget),
      findsNWidgets(9),
      reason: 'switch must not happen before the 1s debounce elapses',
    );

    // After the full 1s window: tutorial puzzle 2 is loaded (5x3 = 15 cells).
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      find.byType(CellWidget),
      findsNWidgets(15),
      reason: 'after the debounce, the next tutorial puzzle must load',
    );
  });

  testWidgets('tapping inside the debounce window cancels the switch', (
    tester,
  ) async {
    await prepareApp({
      'settingsValidateType': 'automatic',
      'settingsShowRating': 'no',
      'settingsLiveCheckType': 'all',
    });
    setTestViewport(tester);

    await tester.pumpWidget(const MyApp());
    await pumpUntil(
      tester,
      () => find.byType(PuzzleWidget).evaluate().isNotEmpty,
    );

    // Complete the puzzle correctly.
    await _tapCell(tester, 1, 2);
    await _tapCell(tester, 2, 1);
    await _tapCell(tester, 3, 1);
    await _tapCell(tester, 4, 2);
    await _tapCell(tester, 5, 1);
    await _tapCell(tester, 6, 1);
    await _tapCell(tester, 7, 1);
    await _tapCell(tester, 8, 1);

    // 500ms in, the player changes their mind and taps a cell, breaking
    // completeness. The pending 1s switch must be cancelled.
    await tester.pump(const Duration(milliseconds: 500));
    // Cell 8 goes 1 → 2 (still complete) → back to 0 here on the 2nd tap.
    await _tapCell(tester, 8, 2);

    await tester.pump(const Duration(seconds: 2));
    expect(
      find.byType(CellWidget),
      findsNWidgets(9),
      reason:
          'breaking completeness inside the debounce window must cancel '
          'the pending switch',
    );
  });
}
