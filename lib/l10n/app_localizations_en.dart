// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get help => 'Help';

  @override
  String get viewPrivacyPolicy => 'View privacy policy';

  @override
  String get stats => 'Stats';

  @override
  String get open => 'Open';

  @override
  String get restart => 'Restart';

  @override
  String get pause => 'Pause';

  @override
  String get msgPuzzleSolved => 'Puzzle solved!';

  @override
  String get questionFunToPlay => 'Was if fun to play?';

  @override
  String get infoNoPuzzle => 'No puzzle loaded.';

  @override
  String get titleOpenPuzzlePage => 'Open puzzle';

  @override
  String get infoFilterCollection =>
      'You can filter to find the kind of puzzle you like.';

  @override
  String get labelSelectCollection => 'Collection';

  @override
  String get labelToggleShuffle => 'Shuffle';

  @override
  String get labelChooseOnly => 'Only';

  @override
  String get labelStatePlayed => 'Played';

  @override
  String get labelStateSkipped => 'Skipped';

  @override
  String get labelStateLiked => 'Liked';

  @override
  String get labelStateDisliked => 'Disliked';

  @override
  String get labelChooseNot => 'Not';

  @override
  String get placeholderWidgetPastePuzzle =>
      'Paste a puzzle representation here to open it';

  @override
  String get labelWidgetDimensions => 'Dimensions';

  @override
  String get labelWidgetWidth => 'Width';

  @override
  String get labelWidgetHeight => 'Height';

  @override
  String get labelWidgetFillRatio => 'Fill ratio';

  @override
  String get labelAdvancedFilters => 'Advanced filters';

  @override
  String get labelWidgetWantedrules => 'Wanted rules';

  @override
  String get labelWidgetBannedrules => 'Banned rules';

  @override
  String get msgCountMatchingPuzzles => 'Puzzles matching filters';

  @override
  String get btnShareStats => 'Share';

  @override
  String get statsCopiedToClipboard => 'Stats copied to clipboard';

  @override
  String get statsScopeCurrent => 'Current collection';

  @override
  String get statsScopeAll => 'All collections';

  @override
  String get btnImportStats => 'Import';

  @override
  String statsImportSuccess(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stat entries imported',
      one: '1 stat entry imported',
      zero: 'No stat entries imported',
    );
    return '$_temp0';
  }

  @override
  String get statsImportNothingValid =>
      'No valid stat entries found in the selected file';

  @override
  String get tooltipPause => 'Pause...';

  @override
  String get pausedDueToIdle => 'Paused due to inactivity';

  @override
  String get pausedDueToFocusLost => 'Paused because the app lost focus';

  @override
  String get tooltipMore => 'More...';

  @override
  String get tooltipClue => 'Clue';

  @override
  String get tooltipUndo => 'Undo';

  @override
  String get tooltipLanguage => 'Language...';

  @override
  String get closeMenu => 'Close';

  @override
  String get settings => 'Settings';

  @override
  String get manuallyValidatePuzzle => 'Validate';

  @override
  String get settingValidateType => 'Validation';

  @override
  String get settingValidateTypeManual => 'Manual';

  @override
  String get settingValidateTypeDefault => 'Default';

  @override
  String get settingValidateTypeAutomatic => 'Automatic';

  @override
  String get settingShowRating => 'Show rating';

  @override
  String get settingShowRatingYes => 'Yes';

  @override
  String get settingShowRatingNo => 'No';

  @override
  String get settingsLiveCheckType => 'Errors check';

  @override
  String get settingsLiveCheckTypeAll => 'Live';

  @override
  String get settingsLiveCheckTypeCount => 'Count';

  @override
  String get settingsLiveCheckTypeComplete => 'Wait';

  @override
  String get settingHintType => 'Hints';

  @override
  String get settingHintTypeDeducibleCell => 'Deducible cell';

  @override
  String get settingHintTypeAddConstraint => 'Add constraint';

  @override
  String get settingIdleTimeout => 'Auto-pause on inactivity';

  @override
  String get settingIdleTimeoutDisabled => 'Disabled';

  @override
  String get settingIdleTimeoutS5 => '5 seconds';

  @override
  String get settingIdleTimeoutS10 => '10 seconds';

  @override
  String get settingIdleTimeoutS30 => '30 seconds';

  @override
  String get settingIdleTimeoutM1 => '1 minute';

  @override
  String get settingIdleTimeoutM2 => '2 minutes';

  @override
  String get settingDifficultyLevel => 'Difficulty level';

  @override
  String get settingPlayerLevel => 'My level';

  @override
  String get settingPlayerLevelAuto => 'auto';

  @override
  String get settingAutoLevel => 'Auto-adapt';

  @override
  String endOfPlaylistCongrats(int count) {
    return 'You\'ve played $count puzzles in this collection.';
  }

  @override
  String get endOfPlaylistFiltersBlocking =>
      'There are still puzzles available, but your current filters exclude them.';

  @override
  String endOfPlaylistCurrentLevel(int level) {
    return 'Current level: $level';
  }

  @override
  String hintDeducedFrom(String constraintName) {
    return 'This cell can be deduced from the $constraintName constraint';
  }

  @override
  String hintComplicity(String c1, String c2) {
    return 'This cell can be deduced by combining the $c1 and $c2 constraints';
  }

  @override
  String hintComplicityTwin(String c) {
    return 'This cell can be deduced by combining two $c constraints';
  }

  @override
  String hintComplicityWithAny(String c) {
    return 'This cell can be deduced by combining the $c constraint with another';
  }

  @override
  String get hintForce =>
      'This cell can be deduced by combining multiple constraints';

  @override
  String get hintImpossible => 'A constraint is violated — a mistake was made';

  @override
  String get hintConstraintAdded => 'A new constraint has been added';

  @override
  String get hintConstraintNone => 'No more constraints available';

  @override
  String get hintCellWrong => 'This cell is wrong';

  @override
  String get hintAllCorrectSoFar => 'Everything filled so far is correct';

  @override
  String get hintCellDeducible => 'This cell can be deduced';

  @override
  String get constraintForbiddenPattern => 'forbidden pattern';

  @override
  String get constraintGroupSize => 'group size';

  @override
  String get constraintLetterGroup => 'letter group';

  @override
  String get constraintParity => 'parity';

  @override
  String get constraintQuantity => 'quantity';

  @override
  String get constraintSymmetry => 'symmetry';

  @override
  String get generate => 'Generate';

  @override
  String get generateTitle => 'Generate puzzles';

  @override
  String get generateWidth => 'Width';

  @override
  String get generateHeight => 'Height';

  @override
  String get generateRequiredRules => 'Required rules';

  @override
  String get generateExcludedRules => 'Excluded rules';

  @override
  String get generateMaxTime => 'Max time';

  @override
  String get generateCount => 'Puzzles';

  @override
  String get generateStart => 'Generate';

  @override
  String get generateStop => 'Stop';

  @override
  String generateProgress(int current, int total) {
    return 'Generated $current / $total puzzles';
  }

  @override
  String get generateComplete => 'Generation complete!';

  @override
  String get generateConstraints => 'Constraints';

  @override
  String get generateFailed =>
      'No puzzles could be generated with these parameters. Try different settings.';

  @override
  String get generatePlay => 'Play';

  @override
  String get generateMore => 'More';

  @override
  String get noCustomPuzzles =>
      'No custom puzzles yet. Use the Generate page to create some!';

  @override
  String get create => 'Create';

  @override
  String get createTitle => 'Create a puzzle';

  @override
  String get createStart => 'Start editing';

  @override
  String get createTest => 'Test';

  @override
  String get createValidate => 'Validate';

  @override
  String get createSave => 'Save';

  @override
  String get createSaved => 'Puzzle saved!';

  @override
  String get createSolvable => 'Solvable';

  @override
  String get createNotSolvable => 'Not solvable';

  @override
  String get createUniqueSolution => 'Unique solution';

  @override
  String get createMultipleSolutions => 'Multiple solutions';

  @override
  String get createNoSolution => 'No solution';

  @override
  String get createComplexity => 'Complexity';

  @override
  String get createNoConstraints => 'Tap a cell to add a constraint';

  @override
  String get createAddConstraint => 'Add a constraint';

  @override
  String get createChooseType => 'Constraint type';

  @override
  String get createChooseSide => 'Side';

  @override
  String get createChooseAxis => 'Symmetry axis';

  @override
  String get createChooseSize => 'Group size';

  @override
  String get createChooseLetter => 'Letter';

  @override
  String get createChooseValue => 'Value';

  @override
  String get createChooseCount => 'Count';

  @override
  String get createMotifWidth => 'Pattern width';

  @override
  String get createMotifHeight => 'Pattern height';

  @override
  String createLetterGroupMode(String letter) {
    return 'Tap cells to add to group $letter, then press Done';
  }

  @override
  String get createLetterGroupDone => 'Done';

  @override
  String get createAddNew => 'Add new constraint';

  @override
  String get createDeleteConstraint => 'Delete a constraint';

  @override
  String get createConfirmDelete => 'Delete this constraint?';

  @override
  String get createValidating => 'Validating...';

  @override
  String get createSolutions => 'Solutions';

  @override
  String get constraintDifferentFrom => 'different from';

  @override
  String get createPlaylist => 'New playlist';

  @override
  String get deletePlaylist => 'Delete playlist';

  @override
  String get importPlaylist => 'Import from file';

  @override
  String get playlistName => 'Playlist name';

  @override
  String get playlistCreated => 'Playlist created';

  @override
  String get confirmDeletePlaylist =>
      'Delete this playlist and all its puzzles?';

  @override
  String get targetPlaylist => 'Save to';

  @override
  String get newPlaylist => 'New playlist...';

  @override
  String get saveProgress => 'Save progress';

  @override
  String get saveProgressTitle => 'Save current state';

  @override
  String get inProgressPlaylistName => 'In progress';

  @override
  String get progressSaved => 'Progress saved';

  @override
  String get progressRestored => 'Your progress has been restored';

  @override
  String get sharePuzzle => 'Share puzzle';

  @override
  String get shareLinkCopied => 'Link copied to clipboard';

  @override
  String get createFixedCellMode => 'Fix cell color';

  @override
  String get createFixBlack => 'Fix to black';

  @override
  String get createFixWhite => 'Fix to white';

  @override
  String get createRemoveFixed => 'Remove fixed color';

  @override
  String get createPasteHint => 'Paste a puzzle representation to edit it';

  @override
  String get constraintGroupCount => 'group count';

  @override
  String get constraintColumnCount => 'cells per column';

  @override
  String get constraintRowCount => 'cells per row';

  @override
  String get constraintShape => 'shape';

  @override
  String get constraintNeighborCount => 'neighbor count';

  @override
  String get constraintEyes => 'eyes';

  @override
  String get newConstraintModalTitle => 'New rule!';

  @override
  String get newConstraintModalSkip => 'Skip learning';

  @override
  String get welcomeModalTitle => 'Welcome';

  @override
  String get welcomeModalBody =>
      'Welcome to Get Some Puzzle! Your goal is to color each cell black or white while satisfying a set of constraints. The rule of each constraint will be explained as you encounter it for the first time.';

  @override
  String get learning => 'Learning';

  @override
  String get learningPageTitle => 'Learning';

  @override
  String learningSeenOn(String date) {
    return 'First seen on $date';
  }

  @override
  String get learningNeverSeen => 'Not yet encountered';

  @override
  String learningPlayCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count puzzles played',
      one: '1 puzzle played',
      zero: 'No puzzles played',
    );
    return '$_temp0';
  }

  @override
  String get learningRefreshButton => 'Refresh my memory';

  @override
  String get constraintExplainFM =>
      'A pattern shown above the grid on a violet background must never appear inside the grid.';

  @override
  String get constraintExplainSH =>
      'A pattern shown above the grid on a light blue background tilted at 45° defines an exact shape: every group of that color must take this shape (rotations and reflections allowed).';

  @override
  String get constraintExplainGS =>
      'A cell carrying a number must belong to a group of orthogonally adjacent same-color cells whose size matches that number.';

  @override
  String get constraintExplainPA =>
      'A cell with an arrow demands the same number of black and white cells in front of the arrow. A double-headed arrow extends the rule to both sides.';

  @override
  String get constraintExplainLT =>
      'Cells marked with the same letter must belong to the same group. A group must not contain two different letters.';

  @override
  String get constraintExplainQA =>
      'A number on a blue background above the grid sets the total number of cells of that color the solution must contain.';

  @override
  String get constraintExplainSY =>
      'A cell carrying ⟍, |, ⟋, ― or 🞋 forces its group (same-color connected cells) to be symmetric along that axis. The 🞋 symbol means central symmetry — equivalent to a half-turn.';

  @override
  String get constraintExplainDF =>
      'Two cells separated by a ≠ symbol must be of different colors.';

  @override
  String get constraintExplainCC =>
      'A circled number above a column tells how many cells of that color must appear in this specific column.';

  @override
  String get constraintExplainRC =>
      'A circled number to the left of a row tells how many cells of that color must appear in this specific row.';

  @override
  String get constraintExplainGC =>
      'A boxed number with a chain icon tells how many separate groups (connected components) of that color the solution must contain.';

  @override
  String get constraintExplainNC =>
      'A cell shown as a cross containing a number must have exactly that number of orthogonal neighbors of the marked color.';

  @override
  String get constraintExplainEY =>
      'A cell with an eye must \"see\" exactly the indicated number of cells of the eye\'s color. Sight travels in a straight line in each of the four orthogonal directions until it hits the grid edge or a cell of the opposite color (which blocks the view).';

  @override
  String get complicityOtherConstraint => 'another constraint';

  @override
  String get collectionMyPuzzles => 'My puzzles';

  @override
  String get collectionEasy => 'Beginner';

  @override
  String get collectionPlayer => 'Player';

  @override
  String get collectionAdvanced => 'Advanced';

  @override
  String get collectionStrong => 'Strong';

  @override
  String get collectionExpert => 'Expert';

  @override
  String get collectionMad => 'Crazy hard';

  @override
  String get tooltipRecommendedCollection => 'Recommended for you';

  @override
  String endOfPlaylistContinueIn(String collection) {
    return 'Continue with $collection';
  }

  @override
  String endOfPlaylistTrySuggested(String collection) {
    return 'Try $collection';
  }

  @override
  String get endOfPlaylistSuggestedHint =>
      'Based on your level, you might enjoy this collection.';

  @override
  String get endOfPlaylistOnboardingNote =>
      'You haven\'t met every rule yet — keep playing to discover them one at a time.';

  @override
  String get endOfPlaylistPickAnother => 'Pick another collection';

  @override
  String get settingClearStats => 'Clear all stats';

  @override
  String get settingReplayOnboarding => 'Replay onboarding';

  @override
  String get settingReplayOnboardingConfirmTitle => 'Replay onboarding?';

  @override
  String get settingReplayOnboardingConfirmBody =>
      'The new-rule explanations will appear again as you encounter each constraint. Your play stats are preserved.';

  @override
  String get settingOnboardingReplayed => 'Onboarding reset.';

  @override
  String get settingClearStatsConfirmTitle => 'Clear all stats?';

  @override
  String get settingClearStatsConfirmBody =>
      'Every play history will be erased: timings, ratings, played/skipped flags. This cannot be undone.';

  @override
  String get settingStatsCleared => 'All stats cleared.';

  @override
  String get someConstraintsInvalid => 'Some constraints are not valid.';

  @override
  String errorsCount(int count) {
    return '$count errors.';
  }

  @override
  String get menuSectionCurrentPuzzle => 'Current puzzle';

  @override
  String get menuSectionLibrary => 'Library';

  @override
  String get menuSectionProgress => 'Progress';

  @override
  String get menuSectionPreferences => 'Preferences';

  @override
  String get nextPuzzle => 'Next puzzle';

  @override
  String get browse => 'Browse';
}
