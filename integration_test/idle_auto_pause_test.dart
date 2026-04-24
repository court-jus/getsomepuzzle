import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/main.dart';
import 'package:getsomepuzzle/widgets/cell.dart';
import 'package:getsomepuzzle/widgets/pause_overlay.dart';
import 'package:getsomepuzzle/widgets/puzzle.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'idle auto-pause surfaces the overlay with an inactivity subtitle',
    (tester) async {
      await prepareApp({'settingsIdleTimeout': 's5'});

      await tester.pumpWidget(const MyApp());
      // Async startup: database load, locale load, settings load, first
      // puzzle open. Pump until the puzzle grid is on screen.
      await pumpUntil(
        tester,
        () => find.byType(PuzzleWidget).evaluate().isNotEmpty,
      );
      expect(find.byType(PuzzleWidget), findsOneWidget);

      // Advance past the 5 s idle window. No taps, no drags — the idle
      // watchdog should fire and the app auto-pauses.
      await tester.pump(const Duration(seconds: 6));

      expect(find.byType(PauseOverlay), findsOneWidget);
      expect(find.text('Paused due to inactivity'), findsOneWidget);
    },
  );

  testWidgets('interaction before the deadline keeps the game running', (
    tester,
  ) async {
    await prepareApp({'settingsIdleTimeout': 's5'});

    await tester.pumpWidget(const MyApp());
    await pumpUntil(
      tester,
      () => find.byType(PuzzleWidget).evaluate().isNotEmpty,
    );

    // Wait 4 s, then tap a cell, then wait another 4 s. Total elapsed > 5 s
    // but no 5 s stretch of inactivity: the idle watchdog must stay silent.
    await tester.pump(const Duration(seconds: 4));
    // Cell 0 is readonly in the tutorial's first puzzle (prefilled "1"), so
    // tapping it is a no-op. Cell 1 is blank and toggles the timer.
    await tester.tap(find.byType(CellWidget).at(1));
    await tester.pump(const Duration(seconds: 4));

    expect(find.byType(PauseOverlay), findsNothing);
  });
}
