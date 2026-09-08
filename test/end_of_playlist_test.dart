// Regression guard for the end-of-batch dialog copy: the suggestion
// caption must follow the direction of the recommendation (congratulate
// when moving up one tier, soft invite when moving down or when the
// current collection has no ladder tier), and the numeric player-level
// caption is gone.
//
// Pure widget tests — no device needed, run by the default `flutter test`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/end_of_playlist.dart';

const _upCaption = 'Good job, do you want to try the next collection?';
const _downCaption =
    'Are you having fun? Do you want to try this other collection?';

Widget _wrap(Widget home) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: home)),
  );
}

EndOfPlaylist _modal({
  bool withSuggestion = false,
  CollectionSuggestionDirection? direction,
}) {
  return EndOfPlaylist(
    filtersBlocking: false,
    playedCount: 20,
    currentCollectionLabel: 'Easy',
    recommendedCollectionLabel: withSuggestion ? 'Player' : null,
    suggestionDirection: direction,
    onSwitchToRecommended: withSuggestion ? () {} : null,
  );
}

void main() {
  testWidgets('congratulates when the suggestion is one tier up', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _modal(
          withSuggestion: true,
          direction: CollectionSuggestionDirection.up,
        ),
      ),
    );
    expect(find.text(_upCaption), findsOneWidget);
    expect(find.text(_downCaption), findsNothing);
  });

  testWidgets('soft invite when the suggestion is one tier down', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _modal(
          withSuggestion: true,
          direction: CollectionSuggestionDirection.down,
        ),
      ),
    );
    expect(find.text(_downCaption), findsOneWidget);
    expect(find.text(_upCaption), findsNothing);
  });

  testWidgets('soft invite when the current collection has no tier', (
    tester,
  ) async {
    // A suggestion exists (label + action) but `suggestionDirection` is
    // null — custom/user collections sit outside the ladder. The soft
    // caption still reads correctly as a generic invite.
    await tester.pumpWidget(_wrap(_modal(withSuggestion: true)));
    expect(find.text(_downCaption), findsOneWidget);
    expect(find.text(_upCaption), findsNothing);
  });

  testWidgets('keeps the tally headline and drops the level caption', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _modal(
          withSuggestion: true,
          direction: CollectionSuggestionDirection.up,
        ),
      ),
    );
    expect(
      find.text("You've played 20 puzzles in this collection."),
      findsOneWidget,
    );
    // The obsolete numeric-level caption must not resurface.
    expect(find.textContaining('Current level'), findsNothing);
  });

  testWidgets('no suggestion means no suggestion caption', (tester) async {
    // `EndOfPlaylist` with no recommendation at all (null label, null
    // direction, null action) must not render either caption.
    await tester.pumpWidget(
      _wrap(const EndOfPlaylist(filtersBlocking: false, playedCount: 0)),
    );
    expect(find.text(_upCaption), findsNothing);
    expect(find.text(_downCaption), findsNothing);
  });
}
