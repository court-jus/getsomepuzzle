import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
    Locale('fr'),
  ];

  /// Label of the menu choice that opens the help text
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get help;

  /// Label of the menu choice that displays game statistics
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get stats;

  /// Label of the menu choice that allows to choose the next puzzle to play
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get newgame;

  /// Label of the menu choice that allows to manually open a puzzle to play
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// Label of the menu choice that allows to restart the current puzzle
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get restart;

  /// Label of the menu choice that allows to report a buggy puzzle
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get report;

  /// Tooltip that appears on the pause menu
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// Message displayed to congratulate the user after they solved a puzzle.
  ///
  /// In en, this message translates to:
  /// **'Puzzle solved!'**
  String get msgPuzzleSolved;

  /// Question asked after a user has finished playing a puzzle.
  ///
  /// In en, this message translates to:
  /// **'Was if fun to play?'**
  String get questionFunToPlay;

  /// Message displayed in the middle of the screen when no puzzle is loaded.
  ///
  /// In en, this message translates to:
  /// **'No puzzle loaded.'**
  String get infoNoPuzzle;

  /// Title of the page that allows to open a puzzle
  ///
  /// In en, this message translates to:
  /// **'Open puzzle'**
  String get titleOpenPuzzlePage;

  /// Explanation displayed in the open puzzle page
  ///
  /// In en, this message translates to:
  /// **'You can filter to find the kind of puzzle you like.'**
  String get infoFilterCollection;

  /// Label of the widget
  ///
  /// In en, this message translates to:
  /// **'Collection'**
  String get labelSelectCollection;

  /// Label of the widget
  ///
  /// In en, this message translates to:
  /// **'Shuffle'**
  String get labelToggleShuffle;

  /// Label of the widget
  ///
  /// In en, this message translates to:
  /// **'Only'**
  String get labelChooseOnly;

  /// Label of the widget
  ///
  /// In en, this message translates to:
  /// **'Played'**
  String get labelStatePlayed;

  /// Label of the widget
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get labelStateSkipped;

  /// Label of the widget
  ///
  /// In en, this message translates to:
  /// **'Liked'**
  String get labelStateLiked;

  /// Label of the widget
  ///
  /// In en, this message translates to:
  /// **'Disliked'**
  String get labelStateDisliked;

  /// Label of the widget
  ///
  /// In en, this message translates to:
  /// **'Not'**
  String get labelChooseNot;

  /// Placeholder of a text field in which the user can paste a text representation of a puzzle
  ///
  /// In en, this message translates to:
  /// **'Paste a puzzle representation here to open it'**
  String get placeholderWidgetPastePuzzle;

  /// Label of the widget
  ///
  /// In en, this message translates to:
  /// **'Dimensions'**
  String get labelWidgetDimensions;

  /// Label of the widget
  ///
  /// In en, this message translates to:
  /// **'Width'**
  String get labelWidgetWidth;

  /// Label of the widget
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get labelWidgetHeight;

  /// Label of the widget
  ///
  /// In en, this message translates to:
  /// **'Fill ratio'**
  String get labelWidgetFillRatio;

  /// Label of the widget
  ///
  /// In en, this message translates to:
  /// **'Wanted rules'**
  String get labelWidgetWantedrules;

  /// Label of the widget
  ///
  /// In en, this message translates to:
  /// **'Banned rules'**
  String get labelWidgetBannedrules;

  /// Message displayed before the number of puzzles
  ///
  /// In en, this message translates to:
  /// **'Puzzles matching filters'**
  String get msgCountMatchingPuzzles;

  /// Label on the button that allows to copy the text to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy to clipboard'**
  String get btnCopyClipboard;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
