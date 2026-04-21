// Integration tests for the puzzle editor (Create page).
// Verifies the dialog-driven flows after the §2.6 refactor (all AlertDialog):
// - Opening the editor from the drawer
// - Picking a cell action via the constraint type picker (grid)
// - Adding a Quantity constraint via the shared color+count dialog
// - Fixing a cell black via the picker
// - Deleting a top-bar constraint via the confirm dialog
//
// Locale-agnostic: finders rely on icons/types and on MaterialLocalizations
// for the standard Cancel / OK / Delete labels, so tests don't depend on the
// user's saved locale (en/fr/es).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:getsomepuzzle/main.dart' as app;
import 'package:getsomepuzzle/widgets/quantity.dart';
import 'package:getsomepuzzle/widgets/cell.dart';

String _cancelLabel(WidgetTester tester) {
  final ctx = tester.element(find.byType(AlertDialog).first);
  return MaterialLocalizations.of(ctx).cancelButtonLabel;
}

String _okLabel(WidgetTester tester) {
  final ctx = tester.element(find.byType(AlertDialog).first);
  return MaterialLocalizations.of(ctx).okButtonLabel;
}

String _deleteLabel(WidgetTester tester) {
  final ctx = tester.element(find.byType(AlertDialog).first);
  return MaterialLocalizations.of(ctx).deleteButtonTooltip;
}

/// Pump until the app has rendered something actionable: either the initial
/// locale chooser (first run) or the home screen's drawer button (subsequent
/// runs). Taps through the locale chooser when present. Fails fast if neither
/// appears in time, instead of silently waiting out a fixed delay.
Future<void> _waitForAppReady(WidgetTester tester) async {
  final english = find.text('English');
  final menu = find.byTooltip('Open navigation menu');

  for (int i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    if (english.evaluate().isNotEmpty) {
      await tester.tap(english);
      await tester.pumpAndSettle();
      return;
    }
    if (menu.evaluate().isNotEmpty) return;
  }
  fail(
    'App did not become ready within 10s: neither locale chooser nor drawer '
    'button appeared.',
  );
}

Future<void> _waitForCreateTileInDrawer(WidgetTester tester) async {
  // The drawer's "Create" entry is gated by `database != null` — database
  // loading is async (file reads) and may not be done by the first settle.
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 500));
    final tile = find.descendant(
      of: find.byType(Drawer),
      matching: find.widgetWithIcon(ListTile, Icons.edit),
    );
    if (tile.evaluate().isNotEmpty) return;
  }
}

Future<void> _openCreatePage(WidgetTester tester) async {
  final scaffoldState = tester.state<ScaffoldState>(
    find.byType(Scaffold).first,
  );
  scaffoldState.openDrawer();
  await tester.pumpAndSettle();
  await _waitForCreateTileInDrawer(tester);

  // The drawer's "Create" entry is the only ListTile with Icons.edit inside it.
  final createTile = find.descendant(
    of: find.byType(Drawer),
    matching: find.widgetWithIcon(ListTile, Icons.edit),
  );
  expect(createTile, findsOneWidget);
  await tester.tap(createTile);
  await tester.pumpAndSettle();

  // On the dimensions page the only ElevatedButton is "Start editing".
  final startButton = find.byType(ElevatedButton);
  expect(startButton, findsOneWidget);
  await tester.tap(startButton);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Create page', () {
    testWidgets('open editor from drawer', (tester) async {
      app.main();
      await _waitForAppReady(tester);

      await _openCreatePage(tester);

      // A 4x4 grid means 16 CellWidgets (default dimensions).
      expect(find.byType(CellWidget), findsNWidgets(16));
    });

    testWidgets('add a Quantity constraint via color+count dialog', (
      tester,
    ) async {
      app.main();
      await _waitForAppReady(tester);
      await _openCreatePage(tester);

      // Tap any cell — empty cell opens the constraint type picker directly.
      await tester.tap(find.byType(CellWidget).first);
      await tester.pumpAndSettle();

      // Type picker is an AlertDialog showing a grid of options.
      expect(find.byType(AlertDialog), findsOneWidget);

      // Quantity tile (Icons.tag).
      final quantityTile = find.byIcon(Icons.tag);
      expect(quantityTile, findsOneWidget);
      await tester.tap(quantityTile);
      await tester.pumpAndSettle();

      // Quantity dialog: color dropdown + count slider + OK/Cancel.
      expect(find.byType(Slider), findsOneWidget);
      expect(find.byType(DropdownButton<int>), findsOneWidget);

      // Confirm with OK.
      await tester.tap(find.widgetWithText(TextButton, _okLabel(tester)));
      await tester.pumpAndSettle();

      // The dialog is gone, a QuantityWidget now appears in the top bar.
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(QuantityWidget), findsOneWidget);
    });

    testWidgets('cancel picker adds nothing', (tester) async {
      app.main();
      await _waitForAppReady(tester);
      await _openCreatePage(tester);

      await tester.tap(find.byType(CellWidget).first);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      // Cancel the type picker.
      await tester.tap(find.widgetWithText(TextButton, _cancelLabel(tester)));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      // Still no QuantityWidget / top-bar constraint.
      expect(find.byType(QuantityWidget), findsNothing);
    });

    testWidgets('fix a cell black from the picker', (tester) async {
      app.main();
      await _waitForAppReady(tester);
      await _openCreatePage(tester);

      // Tap cell 0 → picker.
      await tester.tap(find.byType(CellWidget).first);
      await tester.pumpAndSettle();

      // In the picker, the two "Fix …" buttons at the bottom both use
      // Icons.circle; the first one (Colors.black) is "Fix black".
      final fixButtons = find.byIcon(Icons.circle);
      expect(fixButtons, findsNWidgets(2));
      await tester.tap(fixButtons.first);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);

      // Tap cell 0 again: since it's now fixed, we land on cell-actions
      // (not the empty-cell picker).
      await tester.tap(find.byType(CellWidget).first);
      await tester.pumpAndSettle();

      // Cell actions dialog: Add-new (Icons.add) and Unlock (Icons.lock_open)
      // are both present for a fixed cell.
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.lock_open), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, _cancelLabel(tester)));
      await tester.pumpAndSettle();
    });

    testWidgets('delete a top-bar constraint via confirm dialog', (
      tester,
    ) async {
      app.main();
      await _waitForAppReady(tester);
      await _openCreatePage(tester);

      // Add a Quantity constraint first.
      await tester.tap(find.byType(CellWidget).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.tag));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, _okLabel(tester)));
      await tester.pumpAndSettle();
      expect(find.byType(QuantityWidget), findsOneWidget);

      // Tap the top-bar constraint → confirm-delete dialog.
      await tester.tap(find.byType(QuantityWidget));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      // Confirm deletion.
      await tester.tap(find.widgetWithText(TextButton, _deleteLabel(tester)));
      await tester.pumpAndSettle();

      // The top-bar constraint is gone.
      expect(find.byType(QuantityWidget), findsNothing);
    });
  });
}
