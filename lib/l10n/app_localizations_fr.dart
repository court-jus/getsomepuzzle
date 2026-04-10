// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get help => 'Aide';

  @override
  String get stats => 'Stats';

  @override
  String get newgame => 'Nouveau';

  @override
  String get open => 'Ouvrir';

  @override
  String get restart => 'Redémarrer';

  @override
  String get report => 'Signaler';

  @override
  String get pause => 'Pause';

  @override
  String get msgPuzzleSolved => 'Puzzle résolu !';

  @override
  String get questionFunToPlay => 'Il était amusant ?';

  @override
  String get infoNoPuzzle => 'Aucun puzzle n\'est chargé';

  @override
  String get titleOpenPuzzlePage => 'Ouvrir un puzzle';

  @override
  String get infoFilterCollection =>
      'Vous pouvez utiliser ces filtres pour trouver le genre de puzzles que vous aimez.';

  @override
  String get labelSelectCollection => 'Collection';

  @override
  String get labelToggleShuffle => 'Mélanger';

  @override
  String get labelChooseOnly => 'Seulement';

  @override
  String get labelStatePlayed => 'Joué';

  @override
  String get labelStateSkipped => 'Passé';

  @override
  String get labelStateLiked => 'Aimé';

  @override
  String get labelStateDisliked => 'Détesté';

  @override
  String get labelChooseNot => 'Sauf';

  @override
  String get placeholderWidgetPastePuzzle =>
      'Coller ici la représentation d\'un puzzle pour l\'ouvrir';

  @override
  String get labelWidgetDimensions => 'Dimensions';

  @override
  String get labelWidgetWidth => 'Largeur';

  @override
  String get labelWidgetHeight => 'Hauteur';

  @override
  String get labelWidgetFillRatio => 'Taux de remplissage';

  @override
  String get labelWidgetCplx => 'Complexité';

  @override
  String get labelWidgetWantedrules => 'Règles désirées';

  @override
  String get labelWidgetBannedrules => 'Règles refusées';

  @override
  String get msgCountMatchingPuzzles => 'Nombre de puzzles correspondant';

  @override
  String get btnShareStats => 'Partager';

  @override
  String get tooltipPause => 'Pause...';

  @override
  String get tooltipMore => 'Plus...';

  @override
  String get tooltipClue => 'Indice';

  @override
  String get tooltipUndo => 'Annuler';

  @override
  String get tooltipLanguage => 'Langue';

  @override
  String get closeMenu => 'Fermer';

  @override
  String get settings => 'Paramètres';

  @override
  String get manuallyValidatePuzzle => 'Valider';

  @override
  String get settingValidateType => 'Type de validation';

  @override
  String get settingValidateTypeManual => 'Manuel';

  @override
  String get settingValidateTypeDefault => 'Par défaut';

  @override
  String get settingValidateTypeAutomatic => 'Automatique';

  @override
  String get settingShowRating => 'Noter les puzzles';

  @override
  String get settingShowRatingYes => 'Oui';

  @override
  String get settingShowRatingNo => 'Non';

  @override
  String get settingShareData => 'Partager mes données';

  @override
  String get settingShareDataYes => 'Oui';

  @override
  String get settingShareDataNo => 'Non';

  @override
  String get settingsLiveCheckType => 'Erreurs';

  @override
  String get settingsLiveCheckTypeAll => 'Temps réel';

  @override
  String get settingsLiveCheckTypeCount => 'Décompte';

  @override
  String get settingsLiveCheckTypeComplete => 'Attendre';

  @override
  String hintDeducedFrom(String constraintName) {
    return 'Cette cellule peut être déduite grâce à la contrainte : $constraintName';
  }

  @override
  String get hintForce =>
      'Cette cellule peut être déduite en combinant plusieurs contraintes';

  @override
  String get hintImpossible =>
      'Une contrainte est violée — une erreur a été commise';

  @override
  String get constraintForbiddenPattern => 'motif interdit';

  @override
  String get constraintGroupSize => 'taille de groupe';

  @override
  String get constraintLetterGroup => 'groupe de lettres';

  @override
  String get constraintParity => 'parité';

  @override
  String get constraintQuantity => 'quantité';

  @override
  String get constraintSymmetry => 'symétrie';

  @override
  String get generate => 'Générer';

  @override
  String get generateTitle => 'Générer des puzzles';

  @override
  String get generateWidth => 'Largeur';

  @override
  String get generateHeight => 'Hauteur';

  @override
  String get generateRequiredRules => 'Règles obligatoires';

  @override
  String get generateExcludedRules => 'Règles exclues';

  @override
  String get generateMaxTime => 'Temps max';

  @override
  String get generateCount => 'Puzzles';

  @override
  String get generateStart => 'Générer';

  @override
  String get generateStop => 'Arrêter';

  @override
  String generateProgress(int current, int total) {
    return 'Généré $current / $total puzzles';
  }

  @override
  String get generateComplete => 'Génération terminée !';

  @override
  String get generateConstraints => 'Contraintes';

  @override
  String get generateFailed =>
      'Aucun puzzle n\'a pu être généré avec ces paramètres. Essayez d\'autres réglages.';

  @override
  String get generatePlay => 'Jouer';

  @override
  String get generateMore => 'Encore';

  @override
  String get noCustomPuzzles =>
      'Aucun puzzle personnalisé. Utilisez la page Générer pour en créer !';

  @override
  String get create => 'Créer';

  @override
  String get createTitle => 'Créer un puzzle';

  @override
  String get createStart => 'Commencer';

  @override
  String get createTest => 'Tester';

  @override
  String get createValidate => 'Valider';

  @override
  String get createSave => 'Enregistrer';

  @override
  String get createSaved => 'Puzzle enregistré !';

  @override
  String get createSolvable => 'Résoluble';

  @override
  String get createNotSolvable => 'Non résoluble';

  @override
  String get createUniqueSolution => 'Solution unique';

  @override
  String get createMultipleSolutions => 'Solutions multiples';

  @override
  String get createNoSolution => 'Aucune solution';

  @override
  String get createComplexity => 'Complexité';

  @override
  String get createNoConstraints =>
      'Touchez une cellule pour ajouter une contrainte';

  @override
  String get createAddConstraint => 'Ajouter une contrainte';

  @override
  String get createChooseType => 'Type de contrainte';

  @override
  String get createChooseSide => 'Côté';

  @override
  String get createChooseAxis => 'Axe de symétrie';

  @override
  String get createChooseSize => 'Taille du groupe';

  @override
  String get createChooseLetter => 'Lettre';

  @override
  String get createChooseValue => 'Valeur';

  @override
  String get createChooseCount => 'Nombre';

  @override
  String get createMotifWidth => 'Largeur du motif';

  @override
  String get createMotifHeight => 'Hauteur du motif';

  @override
  String createLetterGroupMode(String letter) {
    return 'Touchez les cellules pour le groupe $letter, puis appuyez sur Terminer';
  }

  @override
  String get createLetterGroupDone => 'Terminer';

  @override
  String get createAddNew => 'Ajouter une contrainte';

  @override
  String get createDeleteConstraint => 'Supprimer une contrainte';

  @override
  String get createConfirmDelete => 'Supprimer cette contrainte ?';

  @override
  String get createValidating => 'Validation...';

  @override
  String get createSolutions => 'Solutions';

  @override
  String get constraintDifferentFrom => 'différent de';

  @override
  String get createPlaylist => 'Nouvelle playlist';

  @override
  String get deletePlaylist => 'Supprimer la playlist';

  @override
  String get importPlaylist => 'Importer un fichier';

  @override
  String get playlistName => 'Nom de la playlist';

  @override
  String get playlistCreated => 'Playlist créée';

  @override
  String get confirmDeletePlaylist =>
      'Supprimer cette playlist et tous ses puzzles ?';

  @override
  String get targetPlaylist => 'Enregistrer dans';

  @override
  String get newPlaylist => 'Nouvelle playlist...';

  @override
  String get createFixedCellMode => 'Fixer la couleur';

  @override
  String get createFixBlack => 'Fixer en noir';

  @override
  String get createFixWhite => 'Fixer en blanc';

  @override
  String get createRemoveFixed => 'Retirer la couleur fixée';

  @override
  String get createPasteHint =>
      'Coller une représentation de puzzle pour l\'éditer';

  @override
  String get collectionMyPuzzles => 'Mes puzzles';
}
