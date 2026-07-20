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
  String get viewPrivacyPolicy => 'Voir la politique de confidentialité';

  @override
  String get stats => 'Stats';

  @override
  String get open => 'Ouvrir';

  @override
  String get restart => 'Redémarrer';

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
  String get labelWidgetDomain => 'Nombre de couleurs';

  @override
  String get labelDomainTwoColors => '2 couleurs';

  @override
  String get labelDomainThreeColors => '3 couleurs';

  @override
  String get msgCountMatchingPuzzles => 'Nombre de puzzles correspondant';

  @override
  String get btnShareStats => 'Partager';

  @override
  String get statsCopiedToClipboard => 'Stats copiées dans le presse-papier';

  @override
  String get statsScopeCurrent => 'Collection courante';

  @override
  String get statsScopeAll => 'Toutes les collections';

  @override
  String get btnImportStats => 'Importer';

  @override
  String statsImportSuccess(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count statistiques importées',
      one: '1 statistique importée',
      zero: 'Aucune statistique importée',
    );
    return '$_temp0';
  }

  @override
  String get statsImportNothingValid =>
      'Aucune statistique valide dans le fichier sélectionné';

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
  String get tooltipTapModeIncrValue => 'Cliquer change la couleur';

  @override
  String get tooltipTapModeRemoveOption => 'Cliquer retire une option';

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
  String get settingsLiveCheckType => 'Erreurs';

  @override
  String get settingsLiveCheckTypeAll => 'Temps réel';

  @override
  String get settingsLiveCheckTypeCount => 'Décompte';

  @override
  String get settingsLiveCheckTypeComplete => 'Attendre';

  @override
  String get settingGrayoutEnabled => 'Griser les contraintes complètes';

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
  String get hintConstraintInprogress =>
      'Une nouvelle contrainte est en cours de calcul...';

  @override
  String get hintConstraintNone => 'Plus de contraintes disponibles';

  @override
  String get hintCellWrong => 'Cette cellule est fausse';

  @override
  String get hintAllCorrectSoFar => 'Tout ce que vous avez rempli est correct';

  @override
  String get hintCellDeducible => 'Cette cellule est déductible';

  @override
  String get hintCellOptionRemovable =>
      'Une option de cette cellule peut être éliminée';

  @override
  String get hintForceRemoveOption =>
      'Une option peut être éliminée en combinant plusieurs contraintes';

  @override
  String hintRemoveOptionDeducedFrom(String constraintName) {
    return 'Une option peut être éliminée à partir de la contrainte $constraintName';
  }

  @override
  String hintRemoveOptionComplicity(String c1, String c2) {
    return 'Une option peut être éliminée en combinant les contraintes $c1 et $c2';
  }

  @override
  String hintRemoveOptionComplicityTwin(String c) {
    return 'Une option peut être éliminée en combinant deux contraintes $c';
  }

  @override
  String get constraintForbiddenPattern => 'motif interdit';

  @override
  String get constraintGroupSize => 'taille de groupe';

  @override
  String get constraintLetterGroup => 'groupe de lettres';

  @override
  String get constraintMajority => 'couleur majoritaire';

  @override
  String get constraintColumnMajority => 'majorité colonne';

  @override
  String get constraintRowMajority => 'majorité ligne';

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
  String get generateRequiredRules => 'Règles requises';

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
    return '$current / $total puzzles générés';
  }

  @override
  String get generateComplete => 'Génération terminée !';

  @override
  String get generateConstraints => 'Contraintes';

  @override
  String get generateFailed =>
      'Aucun puzzle n\'a pu être généré avec ces paramètres. Essaie d\'autres réglages.';

  @override
  String get generatePlay => 'Jouer';

  @override
  String get generateMore => 'Plus';

  @override
  String get noCustomPuzzles =>
      'Pas encore de puzzles personnalisés. Utilise la page Générer pour en créer !';

  @override
  String get create => 'Créer';

  @override
  String get createTitle => 'Créer un puzzle';

  @override
  String get createNewPuzzle => 'Nouveau puzzle';

  @override
  String get createStart => 'Commencer l\'édition';

  @override
  String get createTest => 'Tester';

  @override
  String get createSolverChecking => 'Vérification en cours…';

  @override
  String createSolverDeducible(String deduced, String total) {
    return 'Cellules déductibles : $deduced / $total';
  }

  @override
  String createSolverBruteForce(String count) {
    return 'dont $count par force brute';
  }

  @override
  String get createSolverIncomplete =>
      'Votre puzzle ne peut pas être entièrement résolu, ajoutez des contraintes supplémentaires';

  @override
  String createSolverValid(String collection) {
    return 'Bravo, votre puzzle est valable, sa complexité estimée est $collection';
  }

  @override
  String createSolverContradiction(String culprit) {
    return 'Contradiction détectée ($culprit) : le puzzle n\'a pas de solution';
  }

  @override
  String get createValidate => 'Valider';

  @override
  String get createSave => 'Enregistrer';

  @override
  String get createSaved => 'Puzzle enregistré !';

  @override
  String get createSolvable => 'Résoluble';

  @override
  String get createNotSolvable => 'Insoluble';

  @override
  String get createUniqueSolution => 'Solution unique';

  @override
  String get createMultipleSolutions => 'Plusieurs solutions';

  @override
  String get createNoSolution => 'Aucune solution';

  @override
  String get createComplexity => 'Complexité';

  @override
  String get createNoConstraints =>
      'Touche une case pour ajouter une contrainte';

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
  String createImplicationSource(int total) {
    return 'Cellule source ($total cellules, base 0)';
  }

  @override
  String createImplicationTarget(int total) {
    return 'Cellule cible ($total cellules, base 0)';
  }

  @override
  String get createImplicationInvalid => 'Source/cible invalide';

  @override
  String get colorBlack => 'Noir';

  @override
  String get colorWhite => 'Blanc';

  @override
  String get colorPurple => 'Violet';

  @override
  String get createChooseCount => 'Nombre';

  @override
  String get createMotifWidth => 'Largeur du motif';

  @override
  String get createMotifHeight => 'Hauteur du motif';

  @override
  String get createSecondCorner => 'Tapez le second coin de la zone MJ';

  @override
  String get createZoneTooSmall => 'La zone doit contenir au moins 3 cellules';

  @override
  String createLetterGroupMode(String letter) {
    return 'Touche les cases pour les ajouter au groupe $letter, puis appuie sur Terminer';
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
  String get createFixPurple => 'Fixer en violet';

  @override
  String get createDomainLabel => 'Couleurs';

  @override
  String get createRemoveFixed => 'Retirer la couleur fixée';

  @override
  String get createPasteHint =>
      'Coller une représentation de puzzle pour l\'éditer';

  @override
  String get constraintGroupCount => 'nombre de groupes';

  @override
  String get constraintLineCount => 'cellules par ligne';

  @override
  String get constraintTransition => 'transition';

  @override
  String get constraintShape => 'forme';

  @override
  String get constraintNeighborCount => 'nombre de voisins';

  @override
  String get constraintEyes => 'yeux';

  @override
  String get constraintChain => 'chaîne';

  @override
  String get constraintImplication => 'implication';

  @override
  String get constraintBoundingBox => 'boîte englobante';

  @override
  String get newConstraintModalTitle => 'Nouvelle règle !';

  @override
  String get newConstraintModalSkip => 'Ignorer l\'apprentissage';

  @override
  String get thirdColorSuggestionTitle => 'Prêt pour les 3 couleurs ?';

  @override
  String get thirdColorSuggestionBody =>
      'Vous avez résolu un bon nombre de puzzles en noir et blanc. Envie d\'essayer le mode 3 couleurs ? Une nouvelle couleur — le violet — rejoint le noir et le blanc, et les règles s\'appliquent à chaque couleur indépendamment. C\'est un nouveau type de défi qui s\'appuie sur ce que vous savez déjà.';

  @override
  String get thirdColorSuggestionTryLabel => 'J\'essaie';

  @override
  String get thirdColorSuggestionLaterLabel => 'Plus tard';

  @override
  String get thirdColorSuggestionFiltersReminder =>
      'N\'oubliez pas que vous pouvez toujours choisir le type de puzzles que vous voulez dans les filtres avancés de la bibliothèque.';

  @override
  String get welcomeModalTitle => 'Bienvenue';

  @override
  String get welcomeModalBody =>
      'Bienvenue dans Get Some Puzzle ! Votre objectif est de colorer chaque case en noir ou en blanc en respectant un ensemble de contraintes. Les règles de chaque contrainte vous seront expliquées au fur et à mesure que vous les rencontrerez.';

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
  String get constraintExplainMJ =>
      'Un cadre en pointillés d\'une couleur donnée indique que la majorité des cellules à l\'intérieur de la zone doivent être de cette couleur (plus de la moitié).';

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
  String get constraintExplainLineCount =>
      'Un nombre dans un cercle à côté d\'une ligne ou d\'une colonne indique combien de cellules de cette couleur doivent apparaître dans cette ligne.';

  @override
  String get constraintExplainLineMajority =>
      'Des cercles concentriques colorés à côté d\'une ligne ou d\'une colonne imposent un ordre strict des couleurs par nombre : la couleur la plus extérieure doit avoir plus de cellules que la suivante, et ainsi de suite.';

  @override
  String get constraintExplainTransition =>
      'Une onde carrée avec un nombre à côté d\'une ligne ou d\'une colonne indique combien de changements de couleur doivent apparaître dans cette ligne. Chaque marche de l\'onde est un changement ; une onde plate avec 0 signifie que toute la ligne est d\'une seule couleur.';

  @override
  String get constraintExplainGC =>
      'Un nombre encadré avec une icône de chaîne indique combien de groupes distincts (composantes connexes) de cette couleur la solution doit contenir.';

  @override
  String get constraintExplainBB =>
      'Chaque groupe connexe de cette couleur doit occuper une boîte englobante d\'exactement cette largeur et cette hauteur — le plus petit rectangle entourant le groupe couvre exactement ce nombre de colonnes et de lignes (le groupe n\'a pas besoin de la remplir).';

  @override
  String get constraintExplainNC =>
      'Une case affichée sous forme de croix contenant un chiffre doit avoir exactement ce nombre de voisins orthogonaux de la couleur indiquée.';

  @override
  String get constraintExplainEY =>
      'Une case affichée comme un œil doit « voir » exactement le nombre indiqué de cases de la couleur de l\'œil. Le regard se propage en ligne droite dans chacune des quatre directions orthogonales jusqu\'à atteindre le bord de la grille ou une case de la couleur opposée (qui bloque la vue).';

  @override
  String get constraintExplainCH =>
      'Une icône de mini-grille montre deux côtés de la grille reliés par une chaîne. La solution doit contenir un chemin orthogonal ininterrompu de cette couleur allant du côté marqué à l\'autre côté marqué.';

  @override
  String get constraintExplainIM =>
      'Une flèche d\'une case à une autre signifie : si la case source prend la couleur de la flèche, la case cible doit aussi prendre cette couleur. La contraposée s\'applique aussi : si la cible est d\'une couleur différente, la source ne peut pas prendre la couleur de la flèche.';

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

  @override
  String get menuSectionCurrentPuzzle => 'Puzzle en cours';

  @override
  String get menuSectionLibrary => 'Bibliothèque';

  @override
  String get menuSectionProgress => 'Progression';

  @override
  String get menuSectionPreferences => 'Préférences';

  @override
  String get nextPuzzle => 'Puzzle suivant';

  @override
  String get emptyPlaylistUserEmpty =>
      'Cette playlist est vide. Ajoute des puzzles avant d\'appuyer sur Jouer.';

  @override
  String get emptyPlaylistUserAllPlayed =>
      'Tous les puzzles de cette playlist ont été joués. Choisis une autre collection ou crée une nouvelle playlist.';

  @override
  String get emptyPlaylistNoPuzzlesLoaded =>
      'Aucun puzzle chargé pour cette collection.';

  @override
  String get emptyPlaylistFiltersTooStrict =>
      'Tes filtres excluent tous les puzzles de cette collection. Essaie d\'élargir les dimensions, les règles ou les marqueurs.';

  @override
  String get emptyPlaylistGeneric =>
      'Aucun puzzle n\'est actuellement disponible.';

  @override
  String get bannerOnboardingFiltersDefault =>
      'Ces filtres correspondent à ta progression d\'apprentissage. Tu peux les modifier — appuie sur l\'icône reset pour revenir aux recommandations.';

  @override
  String get bannerOnboardingFiltersOverridden =>
      'Tu utilises tes propres filtres. Appuie sur reset pour revenir aux filtres recommandés par l\'apprentissage.';

  @override
  String get browse => 'Parcourir';

  @override
  String get onboardingCompleteTitle => 'Apprentissage terminé !';

  @override
  String get onboardingCompleteBody =>
      'Vous avez découvert toutes les règles disponibles ! Vous pouvez désormais jouer librement. Lorsque de nouvelles règles seront ajoutées au jeu, vous serez averti.';

  @override
  String get scenarioFilterLabel => 'Scénario';

  @override
  String get scenarioAny => 'Tout scénario';

  @override
  String get scenarioClassic => 'Classique';

  @override
  String get scenarioExplainClassic =>
      'Puzzle général sans style de jeu dominant.';

  @override
  String get scenarioSh => 'Forme';

  @override
  String get scenarioExplainSh =>
      'Au moins une contrainte de forme définit la forme exacte d\'un groupe.';

  @override
  String get scenarioBb => 'Boîte englobante';

  @override
  String get scenarioExplainBb =>
      'Chaque groupe d\'une couleur tient dans la même boîte englobante.';

  @override
  String get scenarioPathBased => 'Chemin';

  @override
  String get scenarioExplainPathBased =>
      'Des groupes de lettres se connectent dans la grille — trouve le chemin.';

  @override
  String get scenarioSyBased => 'Symétrie';

  @override
  String get scenarioExplainSyBased =>
      'Les contraintes de symétrie reflètent les groupes le long d\'axes.';

  @override
  String get scenarioMinesweeper => 'Démineur';

  @override
  String get scenarioExplainMinesweeper =>
      'Comptages de voisins et yeux — joue comme au Démineur.';

  @override
  String get scenarioNonogram => 'Nonogramme';

  @override
  String get scenarioExplainNonogram =>
      'Comptages de colonnes et lignes — déduction façon hanjie.';

  @override
  String get scenarioLocal => 'Local';

  @override
  String get scenarioExplainLocal =>
      'Motifs interdits et contraintes de différence définissent des règles locales.';

  @override
  String get scenarioGroup => 'Groupe';

  @override
  String get scenarioExplainGroup =>
      'Tailles et comptages de groupes axés sur la topologie des composantes connexes.';

  @override
  String get statsSyncDirectory => 'Dossier de synchronisation';

  @override
  String get statsSyncDirectoryChoose => 'Choisir le dossier';

  @override
  String get statsSyncDirectoryChange => 'Changer';

  @override
  String get statsSyncDirectoryClear => 'Effacer';

  @override
  String get statsSyncDirectoryWebUnsupported => 'Non disponible sur le web.';

  @override
  String get statsSyncDirectoryInvalid =>
      'Le dossier sélectionné n\'est pas accessible. Veuillez en choisir un nouveau.';

  @override
  String get statsSyncDirectoryAutoCleared =>
      'Le dossier de synchronisation a été effacé car il n\'est plus accessible. Vous pouvez en définir un nouveau dans les paramètres.';

  @override
  String get settingTheme => 'Thème';

  @override
  String get settingThemeSystem => 'Système';

  @override
  String get settingThemeLight => 'Clair';

  @override
  String get settingThemeDark => 'Sombre';

  @override
  String get statsSectionDifficulty => 'Par complexité';

  @override
  String get statsSectionConstraint => 'Par contrainte';

  @override
  String get statsSectionCollection => 'Par collection';

  @override
  String get statsSectionRating => 'Appréciation';

  @override
  String get statsSectionRecent => 'Dernières parties';

  @override
  String get statsDashboardPlayed => 'Joués';

  @override
  String get statsDashboardFinished => 'Finis';

  @override
  String get statsDashboardAvgDuration => 'Durée moy.';

  @override
  String get statsDashboardTotalHints => 'Hints';

  @override
  String get statsDashboardHintsPerPuzzle => 'Hints/pz';

  @override
  String get statsDashboardApproval => 'Appréciation';

  @override
  String get statsDashboardLiked => 'Aimés';

  @override
  String get statsDashboardDisliked => 'Pas aimés';

  @override
  String get statsDashboardAvgScore => 'Score moyen';
}
