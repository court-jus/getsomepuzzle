// Regression guard for the constraint-icon UI work: the three surfaces
// that render constraint icons (onboarding dialog, Learning page, help
// page catalogue) must build without exceptions, with and without dark
// theme.
//
// Pure widget tests — no device needed, run by the default `flutter test`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:getsomepuzzle/getsomepuzzle/model/app_theme.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constraint_progress.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/help_page.dart';
import 'package:getsomepuzzle/widgets/constraints/registry.dart';
import 'package:getsomepuzzle/widgets/learning_page.dart';
import 'package:getsomepuzzle/widgets/new_constraint_dialog.dart';

Widget _wrap(Widget home, {required Brightness brightness}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: brightness == Brightness.dark ? darkTheme : lightTheme,
    home: home,
  );
}

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    group('constraint icons ($brightness)', () {
      testWidgets('onboarding dialog renders icon + name + explanation', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () =>
                        NewConstraintDialog.show(context, {'FM', 'CH'}),
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
        expect(find.byType(NewConstraintDialog), findsOneWidget);
        // One icon per slug plus the material icons in the dialog.
        expect(find.byType(ConstraintIcon), findsNWidgets(2));
      });

      testWidgets('learning page renders every constraint row', (tester) async {
        await tester.pumpWidget(
          _wrap(
            LearningPage(
              database: Database(playerLevel: 0),
              progress: ConstraintProgress(),
            ),
            brightness: brightness,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // All constraints are listed (unseen at this point → locked).
        expect(find.byType(ConstraintIcon), findsWidgets);
        expect(find.byIcon(Icons.lock_outline), findsWidgets);
      });

      testWidgets('help page renders markdown + constraints catalogue', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(const HelpPage(locale: 'en'), brightness: brightness),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // 18 display slugs: onboarding introducers first (FM, NC, PA,
        // CC, GS, EY, DF, LT, QA), then the rest in registry order;
        // row/column pairs (RC/CC, JC/JR, RT/CT) are collapsed.
        expect(
          find.byType(ConstraintIcon),
          findsNWidgets(constraintCatalogueSlugs.length),
        );
        expect(constraintCatalogueSlugs.length, 18);
        expect(constraintCatalogueSlugs.first, 'FM');
        // Teaching order: onboarding introducers (FM, NC, PA, CC, GS,
        // EY, DF, LT, QA) then remaining display slugs in registry order.
        expect(constraintCatalogueSlugs, [
          'FM',
          'NC',
          'PA',
          'CC',
          'GS',
          'EY',
          'DF',
          'LT',
          'QA',
          'RT',
          'SY',
          'SH',
          'JC',
          'CH',
          'GC',
          'MJ',
          'IM',
          'BB',
        ]);
        // First catalogue row is FM (Forbidden pattern), teaching order.
        final firstIcon = tester.widget<ConstraintIcon>(
          find.byType(ConstraintIcon).first,
        );
        expect(firstIcon.slug, 'FM');
        // The merged column/row-majority row carries the neutral name
        // ("line majority"), just like "cells per line" / "transition".
        expect(find.text('Line majority'), findsOneWidget);
      });
    });
  }
}
