// Guards for the one-shot domain-3 introduction modal: the gating in
// Database (fires once, only for a purple grid the player has never
// actually played) and the modal's content (option dots + paintbrush).
//
// Pure unit + widget tests — no device needed, run by `flutter test`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:getsomepuzzle/getsomepuzzle/model/app_theme.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/cell.dart';
import 'package:getsomepuzzle/widgets/domain3_intro_dialog.dart';

Widget _wrap(Widget home, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: brightness == Brightness.dark ? darkTheme : lightTheme,
    home: home,
  );
}

void main() {
  group('Database.shouldShowDomain3Intro', () {
    // Each test isolates one clause of the AND chain so a regression
    // points straight at the culprit.

    test('returns true for a first-ever 3-colour open', () {
      final db = Database(playerLevel: 0);
      expect(db.shouldShowDomain3Intro(true), isTrue);
    });

    test('returns false for a 2-colour puzzle', () {
      // The modal explains the purple UI specifically; a black-and-white
      // grid must never surface it.
      final db = Database(playerLevel: 0);
      expect(db.shouldShowDomain3Intro(false), isFalse);
    });

    test('returns false once already shown', () {
      final db = Database(playerLevel: 0);
      db.domain3IntroShown = true;
      expect(db.shouldShowDomain3Intro(true), isFalse);
    });

    test('returns false when the history proves 3-colour plays', () {
      // An imported/reinstalled stats history that already contains a
      // purple play means the player has met the dots and the paintbrush;
      // re-explaining them would be noise.
      final db = Database(playerLevel: 0);
      db.hasPlayedThirdColor = true;
      expect(db.shouldShowDomain3Intro(true), isFalse);
    });

    test('noteDomain3IntroShown latches the shown flag', () async {
      final db = Database(playerLevel: 0);
      expect(db.domain3IntroShown, isFalse);
      await db.noteDomain3IntroShown();
      expect(db.domain3IntroShown, isTrue);
      expect(db.shouldShowDomain3Intro(true), isFalse);
    });
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    group('Domain3IntroDialog ($brightness)', () {
      testWidgets('explains the dots and the paintbrush, then closes', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Domain3IntroDialog.show(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
            brightness: brightness,
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(find.byType(Domain3IntroDialog), findsOneWidget);
        expect(find.text('Three colors!'), findsOneWidget);
        // Both explained surfaces are present: a live option-dots sample
        // and the paintbrush icon the toolbar button uses.
        expect(find.byType(OptionDots), findsOneWidget);
        expect(find.byIcon(Icons.format_paint), findsOneWidget);
        expect(find.text('The dots at the bottom of a cell'), findsOneWidget);
        expect(find.text('The paintbrush button'), findsOneWidget);

        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(find.byType(Domain3IntroDialog), findsNothing);
      });
    });
  }
}
