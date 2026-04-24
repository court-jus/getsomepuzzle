import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/main.dart';
import 'package:getsomepuzzle/widgets/pause_overlay.dart';
import 'package:getsomepuzzle/widgets/puzzle.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('hidden app lifecycle auto-pauses with focus-lost subtitle', (
    tester,
  ) async {
    await prepareApp({});

    await tester.pumpWidget(const MyApp());
    await pumpUntil(
      tester,
      () => find.byType(PuzzleWidget).evaluate().isNotEmpty,
    );

    // Simulate the OS/browser moving the app off-screen. This is what
    // `WidgetsBindingObserver.didChangeAppLifecycleState` sees on a tab
    // switch (web) or alt-tab (desktop).
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();

    expect(find.byType(PauseOverlay), findsOneWidget);
    expect(find.text('Paused because the app lost focus'), findsOneWidget);
  });

  testWidgets('inactive lifecycle auto-pauses with focus-lost subtitle', (
    tester,
  ) async {
    await prepareApp({});

    await tester.pumpWidget(const MyApp());
    await pumpUntil(
      tester,
      () => find.byType(PuzzleWidget).evaluate().isNotEmpty,
    );

    // Desktop window losing focus typically reports AppLifecycleState.inactive.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    expect(find.text('Paused because the app lost focus'), findsOneWidget);
  });

  testWidgets('resumed lifecycle does not auto-resume the game', (
    tester,
  ) async {
    await prepareApp({});

    await tester.pumpWidget(const MyApp());
    await pumpUntil(
      tester,
      () => find.byType(PuzzleWidget).evaluate().isNotEmpty,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(find.byType(PauseOverlay), findsOneWidget);

    // User switches back to the app. The lifecycle goes `resumed`, but the
    // overlay must stay up — resuming is an explicit user click, not an
    // automatic behaviour, so the timer does not silently tick again.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(
      find.byType(PauseOverlay),
      findsOneWidget,
      reason: 'resume must require an explicit click',
    );
  });
}
