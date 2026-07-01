import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/main.dart';
import 'package:getsomepuzzle/widgets/cell.dart';
import 'package:getsomepuzzle/widgets/pause_overlay.dart';
import 'package:getsomepuzzle/widgets/puzzle.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/harness.dart';

/// Verifies that the desktop keyboard shortcuts wired into `_handleKeyEvent`
/// actually drive the matching game actions. We assert through observable UI
/// state (button enablement, overlay presence, drawer open) rather than
/// private game state, so a test only fails when player-visible behaviour
/// regresses — not when an internal field is renamed.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Brings up the app on a 2-colour 3x3 fixture and waits for the grid.
  // Rating is disabled so completing a puzzle never blocks behind a modal.
  // (prepareApp graduates onboarding for custom-puzzle tests, so the fixture
  // is actually surfaced.)
  Future<void> launch(WidgetTester tester) async {
    await prepareApp(
      {'settingsShowRating': 'no'},
      customPuzzles: const [fixture3x3],
    );
    setTestViewport(tester);
    await tester.pumpWidget(const MyApp());
    await pumpUntil(
      tester,
      () => find.byType(PuzzleWidget).evaluate().isNotEmpty,
    );
  }

  bool undoEnabled(WidgetTester tester) =>
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.undo_outlined),
          )
          .onPressed !=
      null;

  testWidgets('U undoes the last move', (tester) async {
    await launch(tester);

    // Undo starts disabled: an untouched grid has no history to revert.
    expect(undoEnabled(tester), isFalse);

    // One tap on a free cell records a move, enabling undo.
    await tester.tap(find.byType(CellWidget).at(1));
    await tester.pump();
    expect(undoEnabled(tester), isTrue);

    // Pressing U must revert that move, emptying the history again.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
    await tester.pump();
    expect(
      undoEnabled(tester),
      isFalse,
      reason: 'the U shortcut must call the same undo as the topbar button',
    );
  });

  testWidgets('P toggles pause on and off', (tester) async {
    await launch(tester);

    // No overlay while playing.
    expect(find.byType(PauseOverlay), findsNothing);

    // P pauses → the pause overlay covers the grid.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pumpAndSettle();
    expect(find.byType(PauseOverlay), findsOneWidget);

    // P again resumes → overlay gone.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pumpAndSettle();
    expect(
      find.byType(PauseOverlay),
      findsNothing,
      reason: 'P must toggle pause, not only enter it',
    );
  });

  testWidgets('Escape opens the navigation menu drawer', (tester) async {
    await launch(tester);

    final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);
    expect(scaffold.isDrawerOpen, isFalse);

    // Escape is the Menu shortcut: it must open the drawer.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      scaffold.isDrawerOpen,
      isTrue,
      reason: 'Escape must open the navigation drawer (Menu)',
    );
  });
}
