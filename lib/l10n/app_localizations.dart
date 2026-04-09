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

  /// Label of the menu choice that allows to manually open a puzzle to play or a file
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
  /// **'Complexity'**
  String get labelWidgetCplx;

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

  /// Label on the button that allows to share the stats.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get btnShareStats;

  /// Tooltip displayed while the mouse is over the pause menu
  ///
  /// In en, this message translates to:
  /// **'Pause...'**
  String get tooltipPause;

  /// Tooltip displayed while the mouse is over the extra menu
  ///
  /// In en, this message translates to:
  /// **'More...'**
  String get tooltipMore;

  /// Tooltip displayed while the mouse is over the 'give me a clue' button
  ///
  /// In en, this message translates to:
  /// **'Clue'**
  String get tooltipClue;

  /// Tooltip displayed while the mouse is over the undo button
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get tooltipUndo;

  /// Tooltip displayed while the mouse is over the language choosing menu
  ///
  /// In en, this message translates to:
  /// **'Language...'**
  String get tooltipLanguage;

  /// Menu item that allows to close the menu
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeMenu;

  /// Menu item that allows to change application settings
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// Verb describing the action of validating the solution of a puzzzle
  ///
  /// In en, this message translates to:
  /// **'Validate'**
  String get manuallyValidatePuzzle;

  /// How does the player want the puzzles to be validated?
  ///
  /// In en, this message translates to:
  /// **'Validation'**
  String get settingValidateType;

  /// The player wants to manually validate each puzzle
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get settingValidateTypeManual;

  /// The default validation mode
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get settingValidateTypeDefault;

  /// The player wants to move on to the next puzzle automatically
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get settingValidateTypeAutomatic;

  /// Does the player want to rate each of the played puzzles?
  ///
  /// In en, this message translates to:
  /// **'Show rating'**
  String get settingShowRating;

  /// The player wants to rate each puzzle
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get settingShowRatingYes;

  /// The player does not want to rate each puzzle
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get settingShowRatingNo;

  /// Does the player want to share they played/liked data?
  ///
  /// In en, this message translates to:
  /// **'Share data'**
  String get settingShareData;

  /// The player wants to share
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get settingShareDataYes;

  /// The player does not want to share
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get settingShareDataNo;

  /// Does the player want a live check for errors?
  ///
  /// In en, this message translates to:
  /// **'Errors check'**
  String get settingsLiveCheckType;

  /// The player wants all errors to be displayed live
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get settingsLiveCheckTypeAll;

  /// The player only wants to see the number of errors live
  ///
  /// In en, this message translates to:
  /// **'Count'**
  String get settingsLiveCheckTypeCount;

  /// The player wants to wait until puzzle completion to see errors
  ///
  /// In en, this message translates to:
  /// **'Wait'**
  String get settingsLiveCheckTypeComplete;

  /// Hint message shown when the player clicks the lightbulb to get a clue
  ///
  /// In en, this message translates to:
  /// **'This cell can be deduced from the {constraintName} constraint'**
  String hintDeducedFrom(String constraintName);

  /// Hint message shown when a force step is required
  ///
  /// In en, this message translates to:
  /// **'This cell can be deduced by combining multiple constraints'**
  String get hintForce;

  /// Hint message shown when the puzzle is in an impossible state
  ///
  /// In en, this message translates to:
  /// **'A constraint is violated — a mistake was made'**
  String get hintImpossible;

  /// Name of the forbidden pattern constraint
  ///
  /// In en, this message translates to:
  /// **'forbidden pattern'**
  String get constraintForbiddenPattern;

  /// Name of the group size constraint
  ///
  /// In en, this message translates to:
  /// **'group size'**
  String get constraintGroupSize;

  /// Name of the letter group constraint
  ///
  /// In en, this message translates to:
  /// **'letter group'**
  String get constraintLetterGroup;

  /// Name of the parity constraint
  ///
  /// In en, this message translates to:
  /// **'parity'**
  String get constraintParity;

  /// Name of the quantity constraint
  ///
  /// In en, this message translates to:
  /// **'quantity'**
  String get constraintQuantity;

  /// Name of the symmetry constraint
  ///
  /// In en, this message translates to:
  /// **'symmetry'**
  String get constraintSymmetry;

  /// Menu label for the puzzle generator
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get generate;

  /// Title of the puzzle generation page
  ///
  /// In en, this message translates to:
  /// **'Generate puzzles'**
  String get generateTitle;

  /// Label for the width selector in the generator
  ///
  /// In en, this message translates to:
  /// **'Width'**
  String get generateWidth;

  /// Label for the height selector in the generator
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get generateHeight;

  /// Label for the required rules selector
  ///
  /// In en, this message translates to:
  /// **'Required rules'**
  String get generateRequiredRules;

  /// Label for the excluded rules selector
  ///
  /// In en, this message translates to:
  /// **'Excluded rules'**
  String get generateExcludedRules;

  /// Label for the max generation time selector
  ///
  /// In en, this message translates to:
  /// **'Max time'**
  String get generateMaxTime;

  /// Label for the number of puzzles to generate
  ///
  /// In en, this message translates to:
  /// **'Puzzles'**
  String get generateCount;

  /// Label of the button that starts generation
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get generateStart;

  /// Label of the button that stops generation
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get generateStop;

  /// Progress message during puzzle generation
  ///
  /// In en, this message translates to:
  /// **'Generated {current} / {total} puzzles'**
  String generateProgress(int current, int total);

  /// Message shown when generation is finished
  ///
  /// In en, this message translates to:
  /// **'Generation complete!'**
  String get generateComplete;

  /// Label for the constraints progress display
  ///
  /// In en, this message translates to:
  /// **'Constraints'**
  String get generateConstraints;

  /// Message shown when generation produced zero puzzles
  ///
  /// In en, this message translates to:
  /// **'No puzzles could be generated with these parameters. Try different settings.'**
  String get generateFailed;

  /// Button to play the generated puzzles
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get generatePlay;

  /// Button to generate more puzzles
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get generateMore;

  /// Message shown when the custom collection is empty
  ///
  /// In en, this message translates to:
  /// **'No custom puzzles yet. Use the Generate page to create some!'**
  String get noCustomPuzzles;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @createTitle.
  ///
  /// In en, this message translates to:
  /// **'Create a puzzle'**
  String get createTitle;

  /// No description provided for @createStart.
  ///
  /// In en, this message translates to:
  /// **'Start editing'**
  String get createStart;

  /// No description provided for @createTest.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get createTest;

  /// No description provided for @createValidate.
  ///
  /// In en, this message translates to:
  /// **'Validate'**
  String get createValidate;

  /// No description provided for @createSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get createSave;

  /// No description provided for @createSaved.
  ///
  /// In en, this message translates to:
  /// **'Puzzle saved!'**
  String get createSaved;

  /// No description provided for @createSolvable.
  ///
  /// In en, this message translates to:
  /// **'Solvable'**
  String get createSolvable;

  /// No description provided for @createNotSolvable.
  ///
  /// In en, this message translates to:
  /// **'Not solvable'**
  String get createNotSolvable;

  /// No description provided for @createUniqueSolution.
  ///
  /// In en, this message translates to:
  /// **'Unique solution'**
  String get createUniqueSolution;

  /// No description provided for @createMultipleSolutions.
  ///
  /// In en, this message translates to:
  /// **'Multiple solutions'**
  String get createMultipleSolutions;

  /// No description provided for @createNoSolution.
  ///
  /// In en, this message translates to:
  /// **'No solution'**
  String get createNoSolution;

  /// No description provided for @createComplexity.
  ///
  /// In en, this message translates to:
  /// **'Complexity'**
  String get createComplexity;

  /// No description provided for @createNoConstraints.
  ///
  /// In en, this message translates to:
  /// **'Tap a cell to add a constraint'**
  String get createNoConstraints;

  /// No description provided for @createAddConstraint.
  ///
  /// In en, this message translates to:
  /// **'Add a constraint'**
  String get createAddConstraint;

  /// No description provided for @createChooseType.
  ///
  /// In en, this message translates to:
  /// **'Constraint type'**
  String get createChooseType;

  /// No description provided for @createChooseSide.
  ///
  /// In en, this message translates to:
  /// **'Side'**
  String get createChooseSide;

  /// No description provided for @createChooseAxis.
  ///
  /// In en, this message translates to:
  /// **'Symmetry axis'**
  String get createChooseAxis;

  /// No description provided for @createChooseSize.
  ///
  /// In en, this message translates to:
  /// **'Group size'**
  String get createChooseSize;

  /// No description provided for @createChooseLetter.
  ///
  /// In en, this message translates to:
  /// **'Letter'**
  String get createChooseLetter;

  /// No description provided for @createChooseValue.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get createChooseValue;

  /// No description provided for @createChooseCount.
  ///
  /// In en, this message translates to:
  /// **'Count'**
  String get createChooseCount;

  /// No description provided for @createMotifWidth.
  ///
  /// In en, this message translates to:
  /// **'Pattern width'**
  String get createMotifWidth;

  /// No description provided for @createMotifHeight.
  ///
  /// In en, this message translates to:
  /// **'Pattern height'**
  String get createMotifHeight;

  /// No description provided for @createLetterGroupMode.
  ///
  /// In en, this message translates to:
  /// **'Tap cells to add to group {letter}, then press Done'**
  String createLetterGroupMode(String letter);

  /// No description provided for @createLetterGroupDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get createLetterGroupDone;

  /// No description provided for @createAddNew.
  ///
  /// In en, this message translates to:
  /// **'Add new constraint'**
  String get createAddNew;

  /// No description provided for @createDeleteConstraint.
  ///
  /// In en, this message translates to:
  /// **'Delete a constraint'**
  String get createDeleteConstraint;

  /// No description provided for @createConfirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete this constraint?'**
  String get createConfirmDelete;

  /// No description provided for @createValidating.
  ///
  /// In en, this message translates to:
  /// **'Validating...'**
  String get createValidating;

  /// No description provided for @createSolutions.
  ///
  /// In en, this message translates to:
  /// **'Solutions'**
  String get createSolutions;

  /// Name of the different-from constraint
  ///
  /// In en, this message translates to:
  /// **'different from'**
  String get constraintDifferentFrom;

  /// No description provided for @createPlaylist.
  ///
  /// In en, this message translates to:
  /// **'New playlist'**
  String get createPlaylist;

  /// No description provided for @deletePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Delete playlist'**
  String get deletePlaylist;

  /// No description provided for @importPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Import from file'**
  String get importPlaylist;

  /// No description provided for @playlistName.
  ///
  /// In en, this message translates to:
  /// **'Playlist name'**
  String get playlistName;

  /// No description provided for @playlistCreated.
  ///
  /// In en, this message translates to:
  /// **'Playlist created'**
  String get playlistCreated;

  /// No description provided for @confirmDeletePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Delete this playlist and all its puzzles?'**
  String get confirmDeletePlaylist;

  /// No description provided for @targetPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Save to'**
  String get targetPlaylist;

  /// No description provided for @newPlaylist.
  ///
  /// In en, this message translates to:
  /// **'New playlist...'**
  String get newPlaylist;

  /// No description provided for @createFixedCellMode.
  ///
  /// In en, this message translates to:
  /// **'Fix cell color'**
  String get createFixedCellMode;

  /// No description provided for @createFixBlack.
  ///
  /// In en, this message translates to:
  /// **'Fix to black'**
  String get createFixBlack;

  /// No description provided for @createFixWhite.
  ///
  /// In en, this message translates to:
  /// **'Fix to white'**
  String get createFixWhite;

  /// No description provided for @createRemoveFixed.
  ///
  /// In en, this message translates to:
  /// **'Remove fixed color'**
  String get createRemoveFixed;

  /// No description provided for @createPasteHint.
  ///
  /// In en, this message translates to:
  /// **'Paste a puzzle representation to edit it'**
  String get createPasteHint;
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
