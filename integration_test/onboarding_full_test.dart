import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/onboarding.dart';
import 'package:getsomepuzzle/main.dart';
import 'package:getsomepuzzle/widgets/cell.dart';
import 'package:getsomepuzzle/widgets/end_of_playlist.dart';
import 'package:getsomepuzzle/widgets/initial_locale_chooser.dart';
import 'package:getsomepuzzle/widgets/new_constraint_dialog.dart';
import 'package:getsomepuzzle/widgets/onboarding_complete_dialog.dart';
import 'package:getsomepuzzle/widgets/puzzle.dart';
import 'package:getsomepuzzle/widgets/welcome_dialog.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/harness.dart';

/// Full onboarding playthrough, end to end, in the *real* app.
///
/// Boots `MyApp` from a clean install (no locale, no `constraintFirstSeen`)
/// and plays exactly what a brand-new beginner sees: the language chooser,
/// the welcome modal, then puzzle after puzzle on the genuine onboarding
/// corpus (the app loads its own `1-easy` collection + the `overfilled-easy`
/// augmentation — we do **not** inject a corpus, and we never switch to
/// another collection). Each puzzle is solved in-game by tapping its cells
/// to the unique solution the hint engine deduces (`Puzzle.solve`), and every
/// new-constraint modal is dismissed the way a player would.
///
/// The test asserts the journey actually *terminates*: the
/// `OnboardingCompleteDialog` fires, and the 17 registered constraints were
/// introduced — via their modals — in the exact order the onboarding
/// contract dictates. This is the real-app counterpart of the stall a real
/// player hit mid-2026 (she cleared every strict phase but the soft-discovery
/// slugs never surfaced); if the shipped beginner corpus can no longer carry
/// a player to graduation, this test stalls and fails with the unmet slugs.

/// The order the onboarding contract introduces every slug: the 10 strict
/// phases (P0–P9) then the post-strict soft-discovery order.
final List<String> _expectedIntroOrder = [
  ...OnboardingPhase.phases.map((p) => p.introducing),
  ...OnboardingPhase.postStrictDiscoveryOrder,
];

/// Pump in small fixed steps (never `pumpAndSettle` — the app runs periodic
/// timers that would never let it settle) until [condition] holds or the
/// budget runs out.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxSteps = 60,
  Duration step = const Duration(milliseconds: 50),
}) async {
  for (var i = 0; i < maxSteps; i++) {
    if (condition()) return;
    await tester.pump(step);
  }
}

bool _present(Type widget) => find.byType(widget).evaluate().isNotEmpty;

/// Tap the "OK" action of whatever onboarding dialog is currently up
/// (never the "Skip learning" button — we want the full playthrough).
Future<void> _tapOk(WidgetTester tester) async {
  // Let the dialog finish its entrance animation: a freshly-inserted dialog
  // is in the tree but its button is NEEDS-PAINT and not yet hit-testable.
  await _pumpUntil(tester, () => false, maxSteps: 8); // ~0.4 s
  final ok = find.widgetWithText(TextButton, 'OK');
  expect(ok, findsOneWidget);
  await tester.tap(ok);
  await _pumpUntil(tester, () => false, maxSteps: 8); // let it close
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a brand-new player completes the whole onboarding on the shipped '
      'beginner corpus, meeting all 17 rules in contract order', (tester) async {
    // Clean install: a fresh temp documents dir and EMPTY prefs — no
    // `locale` (so the language chooser shows) and no `constraintFirstSeen`
    // (so the welcome + per-rule modals fire). We do seed a few gameplay
    // settings so completion auto-advances to the next puzzle without a
    // manual validate/rating tap, exactly like the existing completion
    // tests do — these are ordinary player settings, not corpus shortcuts.
    PathProviderPlatform.instance = FakePathProviderPlatform();
    SharedPreferences.setMockInitialValues({
      'settingsValidateType': 'automatic',
      'settingsShowRating': 'no',
      'settingsLiveCheckType': 'all',
    });
    setTestViewport(tester);

    await tester.pumpWidget(const MyApp());

    // 1. Language chooser — pick English, like a new player.
    await _pumpUntil(tester, () => _present(InitialLocaleChooser));
    expect(find.text('English'), findsOneWidget);
    await tester.tap(find.text('English'));
    await _pumpUntil(tester, () => _present(WelcomeDialog));

    final introduced = <String>[]; // slugs in modal-encounter order
    var completed = false;
    // Generous cap: ~50 strict completions (10 phases × 5) + the soft tail.
    // A real stall trips the assertions below long before this fires.
    const maxPuzzles = 120;
    var puzzlesSolved = 0;

    // 2. Drain whatever onboarding dialogs are showing, recording the rules
    //    they introduce. Returns true once onboarding is declared complete.
    Future<bool> drainDialogs() async {
      for (var guard = 0; guard < 24; guard++) {
        await _pumpUntil(
          tester,
          () =>
              _present(OnboardingCompleteDialog) ||
              _present(WelcomeDialog) ||
              _present(NewConstraintDialog) ||
              _present(EndOfPlaylist) ||
              _present(PuzzleWidget),
        );
        if (_present(OnboardingCompleteDialog)) {
          await _tapOk(tester);
          return true;
        }
        if (_present(WelcomeDialog)) {
          await _tapOk(tester);
          continue;
        }
        if (_present(NewConstraintDialog)) {
          final dialog = tester.widget<NewConstraintDialog>(
            find.byType(NewConstraintDialog),
          );
          for (final slug in dialog.slugs) {
            if (!introduced.contains(slug)) introduced.add(slug);
          }
          await _tapOk(tester);
          continue;
        }
        if (_present(EndOfPlaylist)) {
          // End of a 5-puzzle batch. Stay in the same collection (a beginner
          // never switches) and load the next batch — the exact action the
          // "Continue in <collection>" button performs. We invoke its
          // callback directly to avoid mistaking it for the "try suggested"
          // button (which would switch collections and break the premise).
          final eop = tester.widget<EndOfPlaylist>(find.byType(EndOfPlaylist));
          eop.onContinueCurrent?.call();
          await _pumpUntil(tester, () => false, maxSteps: 8);
          continue;
        }
        return false; // a puzzle is on screen, no dialog pending
      }
      fail('Dialog drain did not converge — stuck on a modal / end screen.');
    }

    // 3. Solve the on-screen puzzle by playing it: tap each free cell up to
    //    its value in the puzzle's stored unique solution. On a 2-colour
    //    puzzle a tap cycles a cell free → 1 → 2 → free, so the tap count
    //    equals the target value. Filling the last cell completes the grid;
    //    automatic validation then advances to the next puzzle after its
    //    debounce. (We read the cached solution rather than re-solving so a
    //    rule injected from a higher level collection — Axe B — that needs
    //    backtracking is still handled.)
    Future<void> solveCurrentPuzzle() async {
      final live = tester
          .widget<PuzzleWidget>(find.byType(PuzzleWidget))
          .currentPuzzle;
      final solution = live.cachedSolution;
      expect(
        solution,
        isNotNull,
        reason: 'shipped puzzles must carry a cached solution to play',
      );
      for (var i = 0; i < live.cells.length; i++) {
        if (live.cells[i].readonly) continue; // given cell, already set
        final taps = solution![i].index; // free=0, black=1, white=2
        for (var t = 0; t < taps; t++) {
          await tester.tap(find.byType(CellWidget).at(i));
          await tester.pump();
        }
      }
    }

    while (puzzlesSolved < maxPuzzles) {
      if (await drainDialogs()) {
        completed = true;
        break;
      }
      expect(
        _present(PuzzleWidget),
        isTrue,
        reason: 'expected a puzzle to play after draining dialogs',
      );
      await solveCurrentPuzzle();
      puzzlesSolved++;
      // Automatic validation switches to the next puzzle after a ~1 s
      // debounce; let it elapse so the next puzzle (and its new-rule modal)
      // surfaces before the loop drains dialogs again.
      await _pumpUntil(tester, () => false, maxSteps: 26); // ~1.3 s
    }

    // The journey must end with the congratulations dialog…
    expect(
      completed,
      isTrue,
      reason:
          'onboarding never completed after $puzzlesSolved puzzles. '
          'Rules met so far: $introduced. '
          'Still unseen: '
          '${OnboardingPhase.allKnownSlugs.where((s) => !introduced.contains(s)).toList()}',
    );
    // …having introduced every registered rule…
    expect(introduced.toSet(), equals(OnboardingPhase.allKnownSlugs));
    // …in the exact order the onboarding contract dictates.
    expect(introduced, equals(_expectedIntroOrder));
  });
}
