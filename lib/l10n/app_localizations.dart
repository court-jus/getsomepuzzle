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

  /// Label of the link in the help page that opens the privacy-policy page on the web
  ///
  /// In en, this message translates to:
  /// **'View privacy policy'**
  String get viewPrivacyPolicy;

  /// Label of the menu choice that displays game statistics
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get stats;

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
  /// **'Advanced filters'**
  String get labelAdvancedFilters;

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

  /// Snackbar message shown when sharing the stats fell back to copying them into the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Stats copied to clipboard'**
  String get statsCopiedToClipboard;

  /// Toggle option on the stats page to display only the stats of the currently loaded collection.
  ///
  /// In en, this message translates to:
  /// **'Current collection'**
  String get statsScopeCurrent;

  /// Toggle option on the stats page to display the complete stats across every collection ever played.
  ///
  /// In en, this message translates to:
  /// **'All collections'**
  String get statsScopeAll;

  /// Label of the button that lets the user pick a stats text file and merge its entries into the local stats store.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get btnImportStats;

  /// Snackbar message confirming the import operation.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No stat entries imported} =1{1 stat entry imported} other{{count} stat entries imported}}'**
  String statsImportSuccess(int count);

  /// Snackbar message when the imported file did not contain a single parseable stat line.
  ///
  /// In en, this message translates to:
  /// **'No valid stat entries found in the selected file'**
  String get statsImportNothingValid;

  /// Tooltip displayed while the mouse is over the pause menu
  ///
  /// In en, this message translates to:
  /// **'Pause...'**
  String get tooltipPause;

  /// Subtitle shown on the pause overlay when the game was paused because the idle timeout expired
  ///
  /// In en, this message translates to:
  /// **'Paused due to inactivity'**
  String get pausedDueToIdle;

  /// Subtitle shown on the pause overlay when the game was paused because the window/tab/app lost focus
  ///
  /// In en, this message translates to:
  /// **'Paused because the app lost focus'**
  String get pausedDueToFocusLost;

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

  /// Setting label for hint mode
  ///
  /// In en, this message translates to:
  /// **'Hints'**
  String get settingHintType;

  /// Hint mode: show which cell can be deduced
  ///
  /// In en, this message translates to:
  /// **'Deducible cell'**
  String get settingHintTypeDeducibleCell;

  /// Hint mode: add a new constraint to make the puzzle easier
  ///
  /// In en, this message translates to:
  /// **'Add constraint'**
  String get settingHintTypeAddConstraint;

  /// Setting label for the idle auto-pause timeout
  ///
  /// In en, this message translates to:
  /// **'Auto-pause on inactivity'**
  String get settingIdleTimeout;

  /// Idle timeout value: feature disabled, never auto-pause
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get settingIdleTimeoutDisabled;

  /// Idle timeout value: 5 seconds of inactivity triggers pause
  ///
  /// In en, this message translates to:
  /// **'5 seconds'**
  String get settingIdleTimeoutS5;

  /// Idle timeout value: 10 seconds
  ///
  /// In en, this message translates to:
  /// **'10 seconds'**
  String get settingIdleTimeoutS10;

  /// Idle timeout value: 30 seconds
  ///
  /// In en, this message translates to:
  /// **'30 seconds'**
  String get settingIdleTimeoutS30;

  /// Idle timeout value: 1 minute
  ///
  /// In en, this message translates to:
  /// **'1 minute'**
  String get settingIdleTimeoutM1;

  /// Idle timeout value: 2 minutes
  ///
  /// In en, this message translates to:
  /// **'2 minutes'**
  String get settingIdleTimeoutM2;

  /// Section header for difficulty level settings
  ///
  /// In en, this message translates to:
  /// **'Difficulty level'**
  String get settingDifficultyLevel;

  /// Setting label for player's current level (0-100)
  ///
  /// In en, this message translates to:
  /// **'My level'**
  String get settingPlayerLevel;

  /// Small label shown next to the player level when auto-adaptation is on
  ///
  /// In en, this message translates to:
  /// **'auto'**
  String get settingPlayerLevelAuto;

  /// Setting label for automatic level adaptation
  ///
  /// In en, this message translates to:
  /// **'Auto-adapt'**
  String get settingAutoLevel;

  /// Headline shown at the end of a batch — surfaces a running tally rather than a 'you exhausted everything' message, since with the 20-puzzle batch cap EndOfPlaylist fires repeatedly through a long collection.
  ///
  /// In en, this message translates to:
  /// **'You\'ve played {count} puzzles in this collection.'**
  String endOfPlaylistCongrats(int count);

  /// Message shown when puzzles remain in the catalog but are hidden by user filters
  ///
  /// In en, this message translates to:
  /// **'There are still puzzles available, but your current filters exclude them.'**
  String get endOfPlaylistFiltersBlocking;

  /// Caption displaying the player's current level
  ///
  /// In en, this message translates to:
  /// **'Current level: {level}'**
  String endOfPlaylistCurrentLevel(int level);

  /// Hint message shown when the player clicks the lightbulb to get a clue
  ///
  /// In en, this message translates to:
  /// **'This cell can be deduced from the {constraintName} constraint'**
  String hintDeducedFrom(String constraintName);

  /// Hint message shown when a complicity combines two distinct constraint types to deduce a cell
  ///
  /// In en, this message translates to:
  /// **'This cell can be deduced by combining the {c1} and {c2} constraints'**
  String hintComplicity(String c1, String c2);

  /// Hint message shown when a complicity combines two constraints of the same type
  ///
  /// In en, this message translates to:
  /// **'This cell can be deduced by combining two {c} constraints'**
  String hintComplicityTwin(String c);

  /// Hint message shown when a complicity combines one named constraint with several other constraints (no single secondary type identified)
  ///
  /// In en, this message translates to:
  /// **'This cell can be deduced by combining the {c} constraint with another'**
  String hintComplicityWithAny(String c);

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

  /// Hint message shown when a constraint is added as a hint
  ///
  /// In en, this message translates to:
  /// **'A new constraint has been added'**
  String get hintConstraintAdded;

  /// Hint message shown when a constraint computation is in progress
  ///
  /// In en, this message translates to:
  /// **'A new constraint is being computed'**
  String get hintConstraintInprogress;

  /// Hint message shown when all constraints have been exhausted
  ///
  /// In en, this message translates to:
  /// **'No more constraints available'**
  String get hintConstraintNone;

  /// Hint message shown when a filled cell does not match the puzzle's solution
  ///
  /// In en, this message translates to:
  /// **'This cell is wrong'**
  String get hintCellWrong;

  /// Hint message shown on tap 1 when no error is detected
  ///
  /// In en, this message translates to:
  /// **'Everything filled so far is correct'**
  String get hintAllCorrectSoFar;

  /// Hint message shown on tap 2 of the deducibleCell mode (cell highlighted, source not yet shown)
  ///
  /// In en, this message translates to:
  /// **'This cell can be deduced'**
  String get hintCellDeducible;

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

  /// Name of the majority zone constraint
  ///
  /// In en, this message translates to:
  /// **'majority color'**
  String get constraintMajority;

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

  /// No description provided for @createSecondCorner.
  ///
  /// In en, this message translates to:
  /// **'Tap second corner of MJ zone'**
  String get createSecondCorner;

  /// No description provided for @createZoneTooSmall.
  ///
  /// In en, this message translates to:
  /// **'Zone must be at least 3 cells'**
  String get createZoneTooSmall;

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

  /// Tooltip / label of the AppBar button that saves the current puzzle in its current state to a playlist
  ///
  /// In en, this message translates to:
  /// **'Save progress'**
  String get saveProgress;

  /// Title of the dialog that asks where to save the current puzzle
  ///
  /// In en, this message translates to:
  /// **'Save current state'**
  String get saveProgressTitle;

  /// Default name suggested for the playlist that holds saved-but-not-finished puzzles
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get inProgressPlaylistName;

  /// Snackbar shown after a puzzle has been saved with its current play state
  ///
  /// In en, this message translates to:
  /// **'Progress saved'**
  String get progressSaved;

  /// Top message shown when a puzzle is opened with a saved partial play state
  ///
  /// In en, this message translates to:
  /// **'Your progress has been restored'**
  String get progressRestored;

  /// Drawer entry that lets the player share a link to the current puzzle
  ///
  /// In en, this message translates to:
  /// **'Share puzzle'**
  String get sharePuzzle;

  /// Snackbar shown after the share URL was placed on the clipboard (desktop/web fallback)
  ///
  /// In en, this message translates to:
  /// **'Link copied to clipboard'**
  String get shareLinkCopied;

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

  /// Name of the group count constraint
  ///
  /// In en, this message translates to:
  /// **'group count'**
  String get constraintGroupCount;

  /// Name of the column count constraint
  ///
  /// In en, this message translates to:
  /// **'cells per column'**
  String get constraintColumnCount;

  /// Name of the row count constraint
  ///
  /// In en, this message translates to:
  /// **'cells per row'**
  String get constraintRowCount;

  /// Name of the row transition constraint
  ///
  /// In en, this message translates to:
  /// **'row transition'**
  String get constraintRowTransition;

  /// Name of the column transition constraint
  ///
  /// In en, this message translates to:
  /// **'column transition'**
  String get constraintColumnTransition;

  /// Name of the shape constraint
  ///
  /// In en, this message translates to:
  /// **'shape'**
  String get constraintShape;

  /// Name of the neighbor count constraint
  ///
  /// In en, this message translates to:
  /// **'neighbor count'**
  String get constraintNeighborCount;

  /// Name of the eyes constraint
  ///
  /// In en, this message translates to:
  /// **'eyes'**
  String get constraintEyes;

  /// Name of the chain constraint
  ///
  /// In en, this message translates to:
  /// **'chain'**
  String get constraintChain;

  /// Title of the dialog shown the first time a player encounters a new constraint
  ///
  /// In en, this message translates to:
  /// **'New rule!'**
  String get newConstraintModalTitle;

  /// Button on the new-rule dialog that lets the player skip onboarding entirely: every rule is marked as seen and the phase counter jumps past all defined phases.
  ///
  /// In en, this message translates to:
  /// **'Skip learning'**
  String get newConstraintModalSkip;

  /// Title of the intro modal shown once before the first rule explanation, on a brand-new player or right after a 'Replay onboarding' reset.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get welcomeModalTitle;

  /// Body of the welcome modal — short pitch of the game's core principle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Get Some Puzzle! Your goal is to color each cell black or white while satisfying a set of constraints. The rule of each constraint will be explained as you encounter it for the first time.'**
  String get welcomeModalBody;

  /// Menu label for the Apprentissage page (constraint reference + memory refresh)
  ///
  /// In en, this message translates to:
  /// **'Learning'**
  String get learning;

  /// Title shown at the top of the learning page
  ///
  /// In en, this message translates to:
  /// **'Learning'**
  String get learningPageTitle;

  /// Status line for a constraint the player has already met. {date} is a localised long date.
  ///
  /// In en, this message translates to:
  /// **'First seen on {date}'**
  String learningSeenOn(String date);

  /// Status line for a constraint the player hasn't met yet
  ///
  /// In en, this message translates to:
  /// **'Not yet encountered'**
  String get learningNeverSeen;

  /// Number of finished, non-skipped puzzles containing this constraint, across every collection
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No puzzles played} =1{1 puzzle played} other{{count} puzzles played}}'**
  String learningPlayCount(int count);

  /// Button on each constraint row that re-displays the explanation modal
  ///
  /// In en, this message translates to:
  /// **'Refresh my memory'**
  String get learningRefreshButton;

  /// Body of the new-constraint explanation modal for the Forbidden Motif (FM) constraint
  ///
  /// In en, this message translates to:
  /// **'A pattern shown above the grid on a violet background must never appear inside the grid.'**
  String get constraintExplainFM;

  /// Body of the new-constraint explanation modal for the Shape (SH) constraint
  ///
  /// In en, this message translates to:
  /// **'A pattern shown above the grid on a light blue background tilted at 45° defines an exact shape: every group of that color must take this shape (rotations and reflections allowed).'**
  String get constraintExplainSH;

  /// Body of the new-constraint explanation modal for the Group Size (GS) constraint
  ///
  /// In en, this message translates to:
  /// **'A cell carrying a number must belong to a group of orthogonally adjacent same-color cells whose size matches that number.'**
  String get constraintExplainGS;

  /// Body of the new-constraint explanation modal for the Parity (PA) constraint
  ///
  /// In en, this message translates to:
  /// **'A cell with an arrow demands the same number of black and white cells in front of the arrow. A double-headed arrow extends the rule to both sides.'**
  String get constraintExplainPA;

  /// Body of the new-constraint explanation modal for the Letter Group (LT) constraint
  ///
  /// In en, this message translates to:
  /// **'Cells marked with the same letter must belong to the same group. A group must not contain two different letters.'**
  String get constraintExplainLT;

  /// Body of the new-constraint explanation modal for the Majority (MJ) constraint
  ///
  /// In en, this message translates to:
  /// **'A dotted rectangle border in a specific color indicates that most cells inside the zone must be of that color (more than half).'**
  String get constraintExplainMJ;

  /// Body of the new-constraint explanation modal for the Quantity (QA) constraint
  ///
  /// In en, this message translates to:
  /// **'A number on a blue background above the grid sets the total number of cells of that color the solution must contain.'**
  String get constraintExplainQA;

  /// Body of the new-constraint explanation modal for the Symmetry (SY) constraint
  ///
  /// In en, this message translates to:
  /// **'A cell carrying ⟍, |, ⟋, ― or 🞋 forces its group (same-color connected cells) to be symmetric along that axis. The 🞋 symbol means central symmetry — equivalent to a half-turn.'**
  String get constraintExplainSY;

  /// Body of the new-constraint explanation modal for the Different From (DF) constraint
  ///
  /// In en, this message translates to:
  /// **'Two cells separated by a ≠ symbol must be of different colors.'**
  String get constraintExplainDF;

  /// Body of the new-constraint explanation modal for the Column Count (CC) constraint
  ///
  /// In en, this message translates to:
  /// **'A circled number above a column tells how many cells of that color must appear in this specific column.'**
  String get constraintExplainCC;

  /// Body of the new-constraint explanation modal for the Row Count (RC) constraint
  ///
  /// In en, this message translates to:
  /// **'A circled number to the left of a row tells how many cells of that color must appear in this specific row.'**
  String get constraintExplainRC;

  /// Body of the new-constraint explanation modal for the Row Transition (RT) constraint
  ///
  /// In en, this message translates to:
  /// **'A square wave with a number beside a row tells how many color changes (transitions) must appear in that row. Each step of the wave is one change; a flat wave with 0 means the whole row is a single color.'**
  String get constraintExplainRT;

  /// Body of the new-constraint explanation modal for the Column Transition (CT) constraint
  ///
  /// In en, this message translates to:
  /// **'A square wave with a number above a column tells how many color changes (transitions) must appear in that column. Each step of the wave is one change; a flat wave with 0 means the whole column is a single color.'**
  String get constraintExplainCT;

  /// Body of the new-constraint explanation modal for the Group Count (GC) constraint
  ///
  /// In en, this message translates to:
  /// **'A boxed number with a chain icon tells how many separate groups (connected components) of that color the solution must contain.'**
  String get constraintExplainGC;

  /// Body of the new-constraint explanation modal for the Neighbor Count (NC) constraint
  ///
  /// In en, this message translates to:
  /// **'A cell shown as a cross containing a number must have exactly that number of orthogonal neighbors of the marked color.'**
  String get constraintExplainNC;

  /// Body of the new-constraint explanation modal for the Eyes (EY) constraint
  ///
  /// In en, this message translates to:
  /// **'A cell with an eye must \"see\" exactly the indicated number of cells of the eye\'s color. Sight travels in a straight line in each of the four orthogonal directions until it hits the grid edge or a cell of the opposite color (which blocks the view).'**
  String get constraintExplainEY;

  /// Body of the new-constraint explanation modal for the Chain (CH) constraint
  ///
  /// In en, this message translates to:
  /// **'A mini-grid icon shows two sides of the grid connected by a chain. The solution must contain an unbroken orthogonal path of that color from the marked side to the other marked side.'**
  String get constraintExplainCH;

  /// Fallback name used when a complicity's secondary slug is the wildcard '*' (kept as a safety fallback; the dedicated 'hintComplicityWithAny' template is preferred for the wildcard case)
  ///
  /// In en, this message translates to:
  /// **'another constraint'**
  String get complicityOtherConstraint;

  /// Label of the custom puzzles collection
  ///
  /// In en, this message translates to:
  /// **'My puzzles'**
  String get collectionMyPuzzles;

  /// Label of the easiest difficulty collection (1-easy.txt) — puzzles solvable by simple propagation only
  ///
  /// In en, this message translates to:
  /// **'Beginner'**
  String get collectionEasy;

  /// Label of the second difficulty collection (2-player.txt) — puzzles requiring harder propagation but no complicity nor force
  ///
  /// In en, this message translates to:
  /// **'Player'**
  String get collectionPlayer;

  /// Label of the advanced difficulty collection (3-advanced.txt) — puzzles using simple complicities
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get collectionAdvanced;

  /// Label of the strong difficulty collection (4-strong.txt) — puzzles using complex complicities
  ///
  /// In en, this message translates to:
  /// **'Strong'**
  String get collectionStrong;

  /// Label of the expert difficulty collection (5-expert.txt) — puzzles requiring one force move
  ///
  /// In en, this message translates to:
  /// **'Expert'**
  String get collectionExpert;

  /// Label of the hardest difficulty collection (6-mad.txt) — puzzles requiring multiple or deep force moves
  ///
  /// In en, this message translates to:
  /// **'Crazy hard'**
  String get collectionMad;

  /// Tooltip on the star badge next to the collection that matches the player's current level
  ///
  /// In en, this message translates to:
  /// **'Recommended for you'**
  String get tooltipRecommendedCollection;

  /// End-of-playlist primary action: load another batch of puzzles from the same collection
  ///
  /// In en, this message translates to:
  /// **'Continue with {collection}'**
  String endOfPlaylistContinueIn(String collection);

  /// End-of-playlist primary action: switch to the recommended collection
  ///
  /// In en, this message translates to:
  /// **'Try {collection}'**
  String endOfPlaylistTrySuggested(String collection);

  /// Subtle hint below the 'Try X' button explaining why this collection is suggested
  ///
  /// In en, this message translates to:
  /// **'Based on your level, you might enjoy this collection.'**
  String get endOfPlaylistSuggestedHint;

  /// Note displayed at end-of-batch while onboarding is still active (strict phase or post-strict soft filter)
  ///
  /// In en, this message translates to:
  /// **'You haven\'t met every rule yet — keep playing to discover them one at a time.'**
  String get endOfPlaylistOnboardingNote;

  /// End-of-playlist secondary link sending the player to the open page to pick a collection
  ///
  /// In en, this message translates to:
  /// **'Pick another collection'**
  String get endOfPlaylistPickAnother;

  /// Button label that wipes every play stat across every collection
  ///
  /// In en, this message translates to:
  /// **'Clear all stats'**
  String get settingClearStats;

  /// Button label that resets the constraint-discovery progress so the new-rule modals fire again
  ///
  /// In en, this message translates to:
  /// **'Replay onboarding'**
  String get settingReplayOnboarding;

  /// Title of the confirmation dialog for the replay-onboarding action
  ///
  /// In en, this message translates to:
  /// **'Replay onboarding?'**
  String get settingReplayOnboardingConfirmTitle;

  /// Body text of the confirmation dialog for the replay-onboarding action
  ///
  /// In en, this message translates to:
  /// **'The new-rule explanations will appear again as you encounter each constraint. Your play stats are preserved.'**
  String get settingReplayOnboardingConfirmBody;

  /// Snackbar message shown after the onboarding has been reset
  ///
  /// In en, this message translates to:
  /// **'Onboarding reset.'**
  String get settingOnboardingReplayed;

  /// Title of the confirmation dialog for the clear-all-stats action
  ///
  /// In en, this message translates to:
  /// **'Clear all stats?'**
  String get settingClearStatsConfirmTitle;

  /// Body text of the confirmation dialog for the clear-all-stats action
  ///
  /// In en, this message translates to:
  /// **'Every play history will be erased: timings, ratings, played/skipped flags. This cannot be undone.'**
  String get settingClearStatsConfirmBody;

  /// Snackbar message shown after all stats have been cleared
  ///
  /// In en, this message translates to:
  /// **'All stats cleared.'**
  String get settingStatsCleared;

  /// Top-of-screen message shown during play when at least one constraint of the current puzzle is violated
  ///
  /// In en, this message translates to:
  /// **'Some constraints are not valid.'**
  String get someConstraintsInvalid;

  /// Top-of-screen message shown during play to indicate how many constraints are currently violated (shown when errors are hidden cell-by-cell, so only the count is revealed)
  ///
  /// In en, this message translates to:
  /// **'{count} errors.'**
  String errorsCount(int count);

  /// Drawer section header that groups actions targeting the puzzle currently displayed
  ///
  /// In en, this message translates to:
  /// **'Current puzzle'**
  String get menuSectionCurrentPuzzle;

  /// Drawer section header that groups ways to obtain a puzzle to play (browse, generate, create)
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get menuSectionLibrary;

  /// Drawer section header that groups player analytics views (stats, learning)
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get menuSectionProgress;

  /// Drawer section header that groups configuration entries (settings, help)
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get menuSectionPreferences;

  /// Drawer entry that skips the current puzzle and loads the next one in the playlist
  ///
  /// In en, this message translates to:
  /// **'Next puzzle'**
  String get nextPuzzle;

  /// Reason shown under the disabled Play button when the current user_ playlist has no unplayed puzzles left
  ///
  /// In en, this message translates to:
  /// **'All puzzles in this playlist have been played. Pick another collection or create a new playlist.'**
  String get emptyPlaylistUserAllPlayed;

  /// Reason shown under the disabled Play button when the puzzle list failed to load or is empty
  ///
  /// In en, this message translates to:
  /// **'No puzzles loaded for this collection.'**
  String get emptyPlaylistNoPuzzlesLoaded;

  /// Reason shown under the disabled Play button when filter() returns 0 puzzles
  ///
  /// In en, this message translates to:
  /// **'Your filters exclude every puzzle in this collection. Try relaxing the dimensions, rules or flags.'**
  String get emptyPlaylistFiltersTooStrict;

  /// Generic fallback reason shown under the disabled Play button
  ///
  /// In en, this message translates to:
  /// **'No puzzle is currently available.'**
  String get emptyPlaylistGeneric;

  /// Banner on OpenPage while the player is still in the onboarding journey, explaining that the rule filter chips were preset by the learning track.
  ///
  /// In en, this message translates to:
  /// **'These filters reflect your learning track. You can override them — tap the reset icon to restore the recommendation.'**
  String get bannerOnboardingFiltersDefault;

  /// Variant of the onboarding-filters banner shown when the player has manually changed the rule filters away from the learning track defaults.
  ///
  /// In en, this message translates to:
  /// **'You\'re using your own filters. Tap reset to return to the learning track\'s recommendation.'**
  String get bannerOnboardingFiltersOverridden;

  /// Drawer entry that opens the puzzle selection page (filters, collections)
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get browse;

  /// Title of the dialog shown when the player has completed all onboarding steps (every rule encountered).
  ///
  /// In en, this message translates to:
  /// **'Onboarding complete!'**
  String get onboardingCompleteTitle;

  /// Body of the onboarding-complete dialog — congratulates the player and mentions future rule additions.
  ///
  /// In en, this message translates to:
  /// **'You\'ve learned all the rules currently available! You can now play freely. When new rules are added to the game, you\'ll be notified.'**
  String get onboardingCompleteBody;
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
