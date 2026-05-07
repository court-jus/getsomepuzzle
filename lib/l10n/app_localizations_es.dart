// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get help => 'Ayuda';

  @override
  String get viewPrivacyPolicy => 'Ver la política de privacidad';

  @override
  String get stats => 'Stats';

  @override
  String get open => 'Abrir';

  @override
  String get restart => 'Reiniciar';

  @override
  String get pause => 'Pausa';

  @override
  String get msgPuzzleSolved => '¡Problema Resuelto!';

  @override
  String get questionFunToPlay => '¿Ha sido divertido jugar?';

  @override
  String get infoNoPuzzle => 'Ningún puzzle cargado.';

  @override
  String get titleOpenPuzzlePage => 'Abrir puzzle';

  @override
  String get infoFilterCollection =>
      'Puedes filtrar para encontrar el tipo de rompecabezas que te gusta.';

  @override
  String get labelSelectCollection => 'Colección';

  @override
  String get labelToggleShuffle => 'Mezclar';

  @override
  String get labelChooseOnly => 'Solamente';

  @override
  String get labelStatePlayed => 'Jugado';

  @override
  String get labelStateSkipped => 'Omitido';

  @override
  String get labelStateLiked => 'Gustado';

  @override
  String get labelStateDisliked => 'Disgustado';

  @override
  String get labelChooseNot => 'No';

  @override
  String get placeholderWidgetPastePuzzle =>
      'Pega una representación de rompecabezas aquí para abrirla';

  @override
  String get labelWidgetDimensions => 'Dimensiones';

  @override
  String get labelWidgetWidth => 'Largo';

  @override
  String get labelWidgetHeight => 'Alto';

  @override
  String get labelWidgetFillRatio => 'Relación de relleno';

  @override
  String get labelAdvancedFilters => 'Filtros avanzados';

  @override
  String get labelWidgetWantedrules => 'Reglas deseadas';

  @override
  String get labelWidgetBannedrules => 'Reglas prohibidas';

  @override
  String get msgCountMatchingPuzzles => 'Puzzles que coinciden con filtros';

  @override
  String get btnShareStats => 'Compartir';

  @override
  String get statsCopiedToClipboard => 'Estadísticas copiadas al portapapeles';

  @override
  String get tooltipPause => 'Pausa...';

  @override
  String get pausedDueToIdle => 'Pausado por inactividad';

  @override
  String get pausedDueToFocusLost =>
      'Pausado porque la aplicación perdió el foco';

  @override
  String get tooltipMore => 'Más...';

  @override
  String get tooltipClue => 'Pista';

  @override
  String get tooltipUndo => 'Deshacer';

  @override
  String get tooltipLanguage => 'Idioma';

  @override
  String get closeMenu => 'Cerrar';

  @override
  String get settings => 'Ajustes';

  @override
  String get manuallyValidatePuzzle => 'Validar';

  @override
  String get settingValidateType => 'Tipo de validación';

  @override
  String get settingValidateTypeManual => 'A mano';

  @override
  String get settingValidateTypeDefault => 'Predeterminado';

  @override
  String get settingValidateTypeAutomatic => 'Automático';

  @override
  String get settingShowRating => 'Calificar';

  @override
  String get settingShowRatingYes => 'Sí';

  @override
  String get settingShowRatingNo => 'No';

  @override
  String get settingsLiveCheckType => 'Comprobación de errores';

  @override
  String get settingsLiveCheckTypeAll => 'Tiempo real';

  @override
  String get settingsLiveCheckTypeCount => 'Recuento';

  @override
  String get settingsLiveCheckTypeComplete => 'Esperar';

  @override
  String get settingHintType => 'Pistas';

  @override
  String get settingHintTypeDeducibleCell => 'Celda deducible';

  @override
  String get settingHintTypeAddConstraint => 'Añadir restricción';

  @override
  String get settingIdleTimeout => 'Pausa auto por inactividad';

  @override
  String get settingIdleTimeoutDisabled => 'Desactivada';

  @override
  String get settingIdleTimeoutS5 => '5 segundos';

  @override
  String get settingIdleTimeoutS10 => '10 segundos';

  @override
  String get settingIdleTimeoutS30 => '30 segundos';

  @override
  String get settingIdleTimeoutM1 => '1 minuto';

  @override
  String get settingIdleTimeoutM2 => '2 minutos';

  @override
  String get settingDifficultyLevel => 'Nivel de dificultad';

  @override
  String get settingPlayerLevel => 'Mi nivel';

  @override
  String get settingPlayerLevelAuto => 'auto';

  @override
  String get settingAutoLevel => 'Adaptación automática';

  @override
  String endOfPlaylistCongrats(int count) {
    return 'Has jugado $count puzzles en esta colección.';
  }

  @override
  String get endOfPlaylistFiltersBlocking =>
      'Quedan puzzles disponibles, pero tus filtros actuales los excluyen.';

  @override
  String endOfPlaylistCurrentLevel(int level) {
    return 'Nivel actual: $level';
  }

  @override
  String hintDeducedFrom(String constraintName) {
    return 'Esta celda se puede deducir gracias a la restricción: $constraintName';
  }

  @override
  String hintComplicity(String c1, String c2) {
    return 'Esta celda se puede deducir combinando las restricciones $c1 y $c2';
  }

  @override
  String hintComplicityTwin(String c) {
    return 'Esta celda se puede deducir combinando dos restricciones $c';
  }

  @override
  String hintComplicityWithAny(String c) {
    return 'Esta celda se puede deducir combinando la restricción $c con otra';
  }

  @override
  String get hintForce =>
      'Esta celda se puede deducir combinando múltiples restricciones';

  @override
  String get hintImpossible =>
      'Una restricción está violada — se ha cometido un error';

  @override
  String get hintConstraintAdded => 'Se ha añadido una nueva restricción';

  @override
  String get hintConstraintNone => 'No hay más restricciones disponibles';

  @override
  String get hintCellWrong => 'Esta celda está mal';

  @override
  String get hintAllCorrectSoFar => 'Todo lo rellenado hasta ahora es correcto';

  @override
  String get hintCellDeducible => 'Esta celda es deducible';

  @override
  String get constraintForbiddenPattern => 'patrón prohibido';

  @override
  String get constraintGroupSize => 'tamaño de grupo';

  @override
  String get constraintLetterGroup => 'grupo de letras';

  @override
  String get constraintParity => 'paridad';

  @override
  String get constraintQuantity => 'cantidad';

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
  String get createLetterGroupDone => 'Listo';

  @override
  String get createAddNew => 'Agregar restricción';

  @override
  String get createDeleteConstraint => 'Eliminar una restricción';

  @override
  String get createConfirmDelete => '¿Eliminar esta restricción?';

  @override
  String get createValidating => 'Validando...';

  @override
  String get createSolutions => 'Soluciones';

  @override
  String get constraintDifferentFrom => 'diferente de';

  @override
  String get createPlaylist => 'Nueva playlist';

  @override
  String get deletePlaylist => 'Eliminar playlist';

  @override
  String get importPlaylist => 'Importar archivo';

  @override
  String get playlistName => 'Nombre de la playlist';

  @override
  String get playlistCreated => 'Playlist creada';

  @override
  String get confirmDeletePlaylist =>
      '¿Eliminar esta playlist y todos sus puzzles?';

  @override
  String get targetPlaylist => 'Guardar en';

  @override
  String get newPlaylist => 'Nueva playlist...';

  @override
  String get saveProgress => 'Guardar progreso';

  @override
  String get saveProgressTitle => 'Guardar estado actual';

  @override
  String get inProgressPlaylistName => 'En curso';

  @override
  String get progressSaved => 'Progreso guardado';

  @override
  String get progressRestored => 'Tu progreso ha sido restaurado';

  @override
  String get sharePuzzle => 'Compartir puzzle';

  @override
  String get shareLinkCopied => 'Enlace copiado al portapapeles';

  @override
  String get createFixedCellMode => 'Fijar color de celda';

  @override
  String get createFixBlack => 'Fijar a negro';

  @override
  String get createFixWhite => 'Fijar a blanco';

  @override
  String get createRemoveFixed => 'Quitar color fijo';

  @override
  String get createPasteHint =>
      'Pegar una representación de puzzle para editarlo';

  @override
  String get constraintGroupCount => 'número de grupos';

  @override
  String get constraintColumnCount => 'células por columna';

  @override
  String get constraintRowCount => 'células por fila';

  @override
  String get constraintShape => 'forma';

  @override
  String get constraintNeighborCount => 'número de vecinos';

  @override
  String get constraintEyes => 'ojos';

  @override
  String get newConstraintModalTitle => '¡Regla nueva!';

  @override
  String get newConstraintModalSkip => 'Saltar aprendizaje';

  @override
  String get welcomeModalTitle => 'Bienvenido';

  @override
  String get welcomeModalBody =>
      '¡Bienvenido a Get Some Puzzle! Tu objetivo es colorear cada casilla en negro o blanco respetando un conjunto de restricciones. Las reglas de cada restricción se explicarán a medida que las encuentres por primera vez.';

  @override
  String get learning => 'Aprendizaje';

  @override
  String get learningPageTitle => 'Aprendizaje';

  @override
  String learningSeenOn(String date) {
    return 'Vista por primera vez el $date';
  }

  @override
  String get learningNeverSeen => 'Aún no encontrada';

  @override
  String learningPlayCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count puzzles jugados',
      one: '1 puzzle jugado',
      zero: 'Ningún puzzle jugado',
    );
    return '$_temp0';
  }

  @override
  String get learningRefreshButton => 'Refrescarme la memoria';

  @override
  String get constraintExplainFM =>
      'Cuando se muestra un motivo sobre la cuadrícula con fondo violeta, ese motivo nunca debe aparecer en la cuadrícula.';

  @override
  String get constraintExplainSH =>
      'Cuando se muestra un motivo sobre la cuadrícula con fondo azul claro inclinado 45°, todos los grupos de ese color deben tener exactamente esa forma (se permiten rotaciones y simetrías).';

  @override
  String get constraintExplainGS =>
      'Cuando una casilla contiene un número, debe pertenecer a un grupo de casillas del mismo color, adyacentes ortogonalmente, cuyo tamaño coincida con ese número.';

  @override
  String get constraintExplainPA =>
      'Cuando una casilla contiene una flecha, debe haber el mismo número de casillas negras y blancas delante de la flecha. Una flecha doble extiende la regla a ambos lados.';

  @override
  String get constraintExplainLT =>
      'Las casillas marcadas con la misma letra deben pertenecer al mismo grupo. Un grupo no puede contener dos letras diferentes.';

  @override
  String get constraintExplainQA =>
      'Un indicador numérico sobre fondo azul encima del puzzle señala cuántas casillas de ese color debe contener la solución en total.';

  @override
  String get constraintExplainSY =>
      'Cuando una casilla contiene uno de estos símbolos (⟍, |, ⟋, ―, 🞋), el grupo del que forma parte debe respetar la simetría asociada. La simetría central (🞋) equivale a un giro de media vuelta.';

  @override
  String get constraintExplainDF =>
      'Cuando dos celdas están separadas por el símbolo ≠, deben ser de colores diferentes.';

  @override
  String get constraintExplainCC =>
      'Un número dentro de un círculo sobre una columna indica cuántas celdas de ese color deben aparecer en esa columna específica.';

  @override
  String get constraintExplainRC =>
      'Un número dentro de un círculo a la izquierda de una fila indica cuántas celdas de ese color deben aparecer en esa fila específica.';

  @override
  String get constraintExplainGC =>
      'A boxed number with a chain icon tells how many separate groups (connected components) of that color the solution must contain.';

  @override
  String get constraintExplainNC =>
      'Una casilla mostrada como una cruz que contiene un número debe tener exactamente ese número de vecinos ortogonales del color indicado.';

  @override
  String get constraintExplainEY =>
      'Una casilla mostrada como un ojo debe «ver» exactamente el número indicado de casillas del color del ojo. La vista se propaga en línea recta en cada una de las cuatro direcciones ortogonales hasta alcanzar el borde de la cuadrícula o una casilla del color opuesto (que bloquea la vista).';

  @override
  String get complicityOtherConstraint => 'otra restricción';

  @override
  String get collectionMyPuzzles => 'Mis puzzles';

  @override
  String get collectionEasy => 'Principiante';

  @override
  String get collectionPlayer => 'Jugador';

  @override
  String get collectionAdvanced => 'Avanzado';

  @override
  String get collectionStrong => 'Fuerte';

  @override
  String get collectionExpert => 'Experto';

  @override
  String get collectionMad => 'Locamente difícil';

  @override
  String get tooltipRecommendedCollection => 'Recomendado para ti';

  @override
  String endOfPlaylistContinueIn(String collection) {
    return 'Seguir con $collection';
  }

  @override
  String endOfPlaylistTrySuggested(String collection) {
    return 'Probar $collection';
  }

  @override
  String get endOfPlaylistSuggestedHint =>
      'Según tu nivel, podría gustarte esta colección.';

  @override
  String get endOfPlaylistOnboardingNote =>
      'Aún no has visto todas las reglas — sigue jugando para descubrirlas una a una.';

  @override
  String get endOfPlaylistPickAnother => 'Elegir otra colección';

  @override
  String get settingClearStats => 'Borrar todas las estadísticas';

  @override
  String get settingReplayOnboarding => 'Repetir la introducción';

  @override
  String get settingReplayOnboardingConfirmTitle => '¿Repetir la introducción?';

  @override
  String get settingReplayOnboardingConfirmBody =>
      'Las explicaciones de cada regla aparecerán de nuevo mientras juegas. Tus estadísticas de juego se conservan.';

  @override
  String get settingOnboardingReplayed => 'Introducción reiniciada.';

  @override
  String get settingClearStatsConfirmTitle => '¿Borrar todas las estadísticas?';

  @override
  String get settingClearStatsConfirmBody =>
      'Se borrará todo el historial de partidas: tiempos, valoraciones, estados jugado/saltado. Esta acción no se puede deshacer.';

  @override
  String get settingStatsCleared => 'Todas las estadísticas borradas.';

  @override
  String get someConstraintsInvalid => 'Algunas restricciones no son válidas.';

  @override
  String errorsCount(int count) {
    return '$count errores.';
  }

  @override
  String get menuSectionCurrentPuzzle => 'Puzzle actual';

  @override
  String get menuSectionLibrary => 'Biblioteca';

  @override
  String get menuSectionProgress => 'Progreso';

  @override
  String get menuSectionPreferences => 'Preferencias';

  @override
  String get nextPuzzle => 'Próximo puzzle';

  @override
  String get browse => 'Explorar';
}
