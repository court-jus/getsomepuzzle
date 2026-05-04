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
  String get labelAdvancedFilters => 'Filtres avancés';

  @override
  String get labelWidgetWantedrules => 'Règles désirées';

  @override
  String get labelWidgetBannedrules => 'Règles refusées';

  @override
  String get msgCountMatchingPuzzles => 'Nombre de puzzles correspondant';

  @override
  String get btnShareStats => 'Partager';

  @override
  String get statsCopiedToClipboard => 'Stats copiées dans le presse-papier';

  @override
  String get tooltipPause => 'Pause...';

  @override
  String get pausedDueToIdle => 'Mis en pause pour inactivité';

  @override
  String get pausedDueToFocusLost =>
      'Mis en pause car l\'application a perdu le focus';

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
  String get settingHintType => 'Astuces';

  @override
  String get settingHintTypeDeducibleCell => 'Cellule déductible';

  @override
  String get settingHintTypeAddConstraint => 'Ajout de contrainte';

  @override
  String get settingIdleTimeout => 'Pause auto sur inactivité';

  @override
  String get settingIdleTimeoutDisabled => 'Désactivée';

  @override
  String get settingIdleTimeoutS5 => '5 secondes';

  @override
  String get settingIdleTimeoutS10 => '10 secondes';

  @override
  String get settingIdleTimeoutS30 => '30 secondes';

  @override
  String get settingIdleTimeoutM1 => '1 minute';

  @override
  String get settingIdleTimeoutM2 => '2 minutes';

  @override
  String get settingDifficultyLevel => 'Niveau de difficulte';

  @override
  String get settingPlayerLevel => 'Mon niveau';

  @override
  String get settingPlayerLevelAuto => 'auto';

  @override
  String get settingAutoLevel => 'Adaptation automatique';

  @override
  String endOfPlaylistCongrats(int count) {
    return 'Tu as joué $count puzzles dans cette collection.';
  }

  @override
  String get endOfPlaylistFiltersBlocking =>
      'Il reste des puzzles disponibles, mais vos filtres actuels les excluent.';

  @override
  String endOfPlaylistCurrentLevel(int level) {
    return 'Niveau actuel : $level';
  }

  @override
  String hintDeducedFrom(String constraintName) {
    return 'Cette cellule peut être déduite grâce à la contrainte : $constraintName';
  }

  @override
  String hintComplicity(String c1, String c2) {
    return 'Cette cellule peut être déduite en combinant les contraintes $c1 et $c2';
  }

  @override
  String hintComplicityTwin(String c) {
    return 'Cette cellule peut être déduite en combinant deux contraintes $c';
  }

  @override
  String hintComplicityWithAny(String c) {
    return 'Cette cellule peut être déduite en combinant la contrainte $c avec une autre';
  }

  @override
  String get hintForce =>
      'Cette cellule peut être déduite en combinant plusieurs contraintes';

  @override
  String get hintImpossible =>
      'Une contrainte est violée — une erreur a été commise';

  @override
  String get hintConstraintAdded => 'Une nouvelle contrainte a été ajoutée';

  @override
  String get hintConstraintNone => 'Plus de contraintes disponibles';

  @override
  String get hintCellWrong => 'Cette cellule est fausse';

  @override
  String get hintAllCorrectSoFar => 'Tout ce que vous avez rempli est correct';

  @override
  String get hintCellDeducible => 'Cette cellule est déductible';

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
  String get saveProgress => 'Enregistrer la progression';

  @override
  String get saveProgressTitle => 'Enregistrer l\'état actuel';

  @override
  String get inProgressPlaylistName => 'En cours';

  @override
  String get progressSaved => 'Progression enregistrée';

  @override
  String get progressRestored => 'Votre progression a été restaurée';

  @override
  String get sharePuzzle => 'Partager le puzzle';

  @override
  String get shareLinkCopied => 'Lien copié dans le presse-papiers';

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
  String get constraintGroupCount => 'nombre de groupes';

  @override
  String get constraintColumnCount => 'cellules par colonne';

  @override
  String get constraintRowCount => 'cellules par ligne';

  @override
  String get constraintShape => 'forme';

  @override
  String get constraintNeighborCount => 'nombre de voisins';

  @override
  String get constraintEyes => 'yeux';

  @override
  String get newConstraintModalTitle => 'Nouvelle règle !';

  @override
  String get learning => 'Apprentissage';

  @override
  String get learningPageTitle => 'Apprentissage';

  @override
  String learningSeenOn(String date) {
    return 'Vue pour la première fois le $date';
  }

  @override
  String get learningNeverSeen => 'Pas encore rencontrée';

  @override
  String learningPlayCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count puzzles joués',
      one: '1 puzzle joué',
      zero: 'Aucun puzzle joué',
    );
    return '$_temp0';
  }

  @override
  String get learningRefreshButton => 'Me rafraîchir la mémoire';

  @override
  String get constraintExplainFM =>
      'Lorsqu\'un motif est affiché au-dessus de la grille sur un fond violet, ce motif ne doit jamais apparaître dans la grille.';

  @override
  String get constraintExplainSH =>
      'Lorsqu\'un motif est affiché au-dessus de la grille sur un fond bleu clair et incliné à 45°, tous les groupes de cette couleur doivent avoir cette forme exacte (les rotations et symétries sont autorisées).';

  @override
  String get constraintExplainGS =>
      'Lorsqu\'une case contient un nombre, elle doit faire partie d\'un groupe de cases de la même couleur, adjacentes orthogonalement, et la taille de ce groupe doit correspondre au nombre.';

  @override
  String get constraintExplainPA =>
      'Lorsqu\'une case contient une flèche, il doit y avoir le même nombre de cases noires et de cases blanches devant la flèche. Une double flèche étend la règle aux deux côtés.';

  @override
  String get constraintExplainLT =>
      'Les cases marquées de la même lettre doivent appartenir au même groupe. Un groupe ne peut pas contenir deux lettres différentes.';

  @override
  String get constraintExplainQA =>
      'Un indice numérique sur fond bleu au-dessus du puzzle indique combien de cases de cette couleur la solution doit contenir au total.';

  @override
  String get constraintExplainSY =>
      'Lorsqu\'une case contient l\'un de ces symboles (⟍, |, ⟋, ―, 🞋), le groupe dont elle fait partie doit respecter la symétrie associée. La symétrie centrale (🞋) équivaut à une rotation d\'un demi-tour.';

  @override
  String get constraintExplainDF =>
      'Lorsque deux cellules sont séparées par le symbole ≠, elles doivent être de couleurs différentes.';

  @override
  String get constraintExplainCC =>
      'Un nombre dans un cercle au-dessus d\'une colonne indique combien de cellules de cette couleur doivent apparaître dans cette colonne précise.';

  @override
  String get constraintExplainRC =>
      'Un nombre dans un cercle à gauche d\'une ligne indique combien de cellules de cette couleur doivent apparaître dans cette ligne précise.';

  @override
  String get constraintExplainGC =>
      'A boxed number with a chain icon tells how many separate groups (connected components) of that color the solution must contain.';

  @override
  String get constraintExplainNC =>
      'A cell shown with crosses on its sides must have exactly the indicated number of orthogonal neighbors of the marked color.';

  @override
  String get constraintExplainEY =>
      'A cell with an eye must \"see\" exactly the indicated number of cells of the eye\'s color. Sight travels in a straight line in each of the four orthogonal directions until it hits the grid edge or a cell of the opposite color (which blocks the view).';

  @override
  String get complicityOtherConstraint => 'une autre contrainte';

  @override
  String get collectionMyPuzzles => 'Mes puzzles';

  @override
  String get collectionEasy => 'Débutant';

  @override
  String get collectionPlayer => 'Joueur';

  @override
  String get collectionAdvanced => 'Avancé';

  @override
  String get collectionStrong => 'Balaise';

  @override
  String get collectionExpert => 'Expert';

  @override
  String get collectionMad => 'Fou furieux';

  @override
  String get tooltipRecommendedCollection => 'Recommandé pour toi';

  @override
  String endOfPlaylistContinueIn(String collection) {
    return 'Continuer dans $collection';
  }

  @override
  String endOfPlaylistTrySuggested(String collection) {
    return 'Essayer $collection';
  }

  @override
  String get endOfPlaylistSuggestedHint =>
      'D\'après ton niveau, tu pourrais aimer cette collection.';

  @override
  String get endOfPlaylistOnboardingNote =>
      'Tu n\'as pas encore croisé toutes les règles — continue à jouer pour les découvrir une par une.';

  @override
  String get endOfPlaylistPickAnother => 'Choisir une autre collection';

  @override
  String get settingClearStats => 'Effacer toutes les statistiques';

  @override
  String get settingReplayOnboarding => 'Rejouer l\'onboarding';

  @override
  String get settingReplayOnboardingConfirmTitle => 'Rejouer l\'onboarding ?';

  @override
  String get settingReplayOnboardingConfirmBody =>
      'Les explications de chaque règle réapparaîtront au fur et à mesure de tes parties. Tes statistiques de jeu sont conservées.';

  @override
  String get settingOnboardingReplayed => 'Onboarding réinitialisé.';

  @override
  String get settingClearStatsConfirmTitle =>
      'Effacer toutes les statistiques ?';

  @override
  String get settingClearStatsConfirmBody =>
      'Tout l\'historique de jeu sera supprimé : temps, notes, statuts joué/passé. Cette action est irréversible.';

  @override
  String get settingStatsCleared => 'Toutes les statistiques ont été effacées.';

  @override
  String get someConstraintsInvalid =>
      'Certaines contraintes ne sont pas valides.';

  @override
  String errorsCount(int count) {
    return '$count erreurs.';
  }
}
