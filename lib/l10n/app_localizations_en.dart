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
  String get stats => 'Stats';

  @override
  String get newgame => 'New';

  @override
  String get open => 'Open';

  @override
  String get restart => 'Restart';

  @override
  String get report => 'Report';

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
  String get settingShareData => 'Share data';

  @override
  String get settingShareDataYes => 'Yes';

  @override
  String get settingShareDataNo => 'No';

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
  String get endOfPlaylistCongrats =>
      'Congratulations! You\'ve solved every puzzle in this collection.';

  @override
  String get endOfPlaylistFiltersBlocking =>
      'There are still puzzles available, but your current filters exclude them.';

  @override
  String endOfPlaylistCurrentLevel(int level) {
    return 'Current level: $level';
  }

  @override
  String get endOfPlaylistTutorialFinished => 'You\'ve finished the tutorial.';

  @override
  String get endOfPlaylistTutorialHaveFun => 'Have fun!';

  @override
  String get endOfPlaylistTutorialStartPlaying => 'Start playing';

  @override
  String get endOfPlaylistTutorialAutoLevelNote =>
      'The difficulty will adapt automatically to your skill. You can disable this in settings.';

  @override
  String hintDeducedFrom(String constraintName) {
    return 'This cell can be deduced from the $constraintName constraint';
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
  String get constraintShape => 'shape';

  @override
  String get constraintNeighborCount => 'neighbor count';

  @override
  String get constraintEyes => 'eyes';

  @override
  String get collectionMyPuzzles => 'My puzzles';

  @override
  String get settingTutorialSection => 'Tutorial';

  @override
  String get settingRestartTutorial => 'Restart tutorial';

  @override
  String get settingRestartTutorialConfirmTitle => 'Restart tutorial?';

  @override
  String get settingRestartTutorialConfirmBody =>
      'Your progress on tutorial puzzles will be erased. This cannot be undone.';

  @override
  String get settingTutorialRestarted => 'Tutorial stats cleared.';

  @override
  String get settingClearStats => 'Clear all stats';

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
}
