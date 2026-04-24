// Integration test for the in-app puzzle generation page.
// Verifies that:
// - The generate page opens from the drawer
// - Generation starts, shows progress, and can be stopped
// - The UI reflects state transitions correctly

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:getsomepuzzle/main.dart' as app;

import 'helpers/harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Generate page', () {
    testWidgets('open, start, stop generation', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await openDrawer(tester);

      // Tap the "Generate" menu item (identified by its icon)
      final generateTile = find.byIcon(Icons.auto_fix_high);
      expect(generateTile, findsOneWidget);
      await tester.tap(generateTile);
      await tester.pumpAndSettle();

      // We should be on the generate page — the "Generate" button is visible
      final generateButton = find.widgetWithIcon(
        ElevatedButton,
        Icons.auto_fix_high,
      );
      expect(generateButton, findsOneWidget);

      // Tap "Generate" to start generation
      await tester.tap(generateButton);
      await tester.pump(); // kick off the async generation

      // Wait a bit for progress to appear
      await tester.pump(const Duration(seconds: 2));

      // The stop button should now be visible
      final stopButton = find.widgetWithIcon(ElevatedButton, Icons.stop);
      expect(stopButton, findsOneWidget);

      // A LinearProgressIndicator should be displayed
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // Tap "Stop" to interrupt generation
      await tester.tap(stopButton);
      await tester.pumpAndSettle();

      // After stopping, the generate button should be back
      expect(
        find.widgetWithIcon(ElevatedButton, Icons.auto_fix_high),
        findsOneWidget,
      );
      // The stop button should be gone
      expect(find.widgetWithIcon(ElevatedButton, Icons.stop), findsNothing);
    });

    testWidgets('generation completes with count=1', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Navigate to generate page
      await openDrawer(tester);
      await tester.tap(find.byIcon(Icons.auto_fix_high));
      await tester.pumpAndSettle();

      // Set count to 1 via the count slider (find the last Slider, which is count)
      // Default count is 5, we need to drag it to 1
      final sliders = find.byType(Slider);
      // Order: width, height, maxTime, count
      final countSlider = sliders.at(3);
      // Drag left to set count to 1
      await tester.drag(countSlider, const Offset(-300, 0));
      await tester.pumpAndSettle();

      // Start generation
      final generateButton = find.widgetWithIcon(
        ElevatedButton,
        Icons.auto_fix_high,
      );
      await tester.tap(generateButton);

      // Wait for generation to complete (up to 60s)
      // Poll until the "Generation complete!" text or play button appears
      bool completed = false;
      for (int i = 0; i < 60; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.byIcon(Icons.play_arrow).evaluate().isNotEmpty) {
          completed = true;
          break;
        }
      }

      expect(
        completed,
        isTrue,
        reason: 'Generation should complete within 60s',
      );

      // The "Play" button should be visible
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });
  });
}
