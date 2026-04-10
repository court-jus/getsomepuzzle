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
  String get stats => 'Stats';

  @override
  String get newgame => 'Nuevo';

  @override
  String get open => 'Abrir';

  @override
  String get restart => 'Reiniciar';

  @override
  String get report => 'Denunciar';

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
  String get labelWidgetCplx => 'Complejidad';

  @override
  String get labelWidgetWantedrules => 'Reglas deseadas';

  @override
  String get labelWidgetBannedrules => 'Reglas prohibidas';

  @override
  String get msgCountMatchingPuzzles => 'Puzzles que coinciden con filtros';

  @override
  String get btnShareStats => 'Compartir';

  @override
  String get tooltipPause => 'Pausa...';

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
  String get settingShareData => 'Compartir';

  @override
  String get settingShareDataYes => 'Sí';

  @override
  String get settingShareDataNo => 'No';

  @override
  String get settingsLiveCheckType => 'Comprobación de errores';

  @override
  String get settingsLiveCheckTypeAll => 'Tiempo real';

  @override
  String get settingsLiveCheckTypeCount => 'Recuento';

  @override
  String get settingsLiveCheckTypeComplete => 'Esperar';

  @override
  String hintDeducedFrom(String constraintName) {
    return 'Esta celda se puede deducir gracias a la restricción: $constraintName';
  }

  @override
  String get hintForce =>
      'Esta celda se puede deducir combinando múltiples restricciones';

  @override
  String get hintImpossible =>
      'Una restricción está violada — se ha cometido un error';

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
  String get constraintSymmetry => 'simetría';

  @override
  String get generate => 'Generar';

  @override
  String get generateTitle => 'Generar puzzles';

  @override
  String get generateWidth => 'Ancho';

  @override
  String get generateHeight => 'Alto';

  @override
  String get generateRequiredRules => 'Reglas obligatorias';

  @override
  String get generateExcludedRules => 'Reglas excluidas';

  @override
  String get generateMaxTime => 'Tiempo máx.';

  @override
  String get generateCount => 'Puzzles';

  @override
  String get generateStart => 'Generar';

  @override
  String get generateStop => 'Detener';

  @override
  String generateProgress(int current, int total) {
    return 'Generados $current / $total puzzles';
  }

  @override
  String get generateComplete => '¡Generación completada!';

  @override
  String get generateConstraints => 'Restricciones';

  @override
  String get generateFailed =>
      'No se pudieron generar puzzles con estos parámetros. Prueba con otros ajustes.';

  @override
  String get generatePlay => 'Jugar';

  @override
  String get generateMore => 'Más';

  @override
  String get noCustomPuzzles =>
      'No hay puzzles personalizados. ¡Usa la página Generar para crear algunos!';

  @override
  String get create => 'Crear';

  @override
  String get createTitle => 'Crear un puzzle';

  @override
  String get createStart => 'Comenzar';

  @override
  String get createTest => 'Probar';

  @override
  String get createValidate => 'Validar';

  @override
  String get createSave => 'Guardar';

  @override
  String get createSaved => '¡Puzzle guardado!';

  @override
  String get createSolvable => 'Resoluble';

  @override
  String get createNotSolvable => 'No resoluble';

  @override
  String get createUniqueSolution => 'Solución única';

  @override
  String get createMultipleSolutions => 'Soluciones múltiples';

  @override
  String get createNoSolution => 'Sin solución';

  @override
  String get createComplexity => 'Complejidad';

  @override
  String get createNoConstraints =>
      'Toca una celda para agregar una restricción';

  @override
  String get createAddConstraint => 'Agregar una restricción';

  @override
  String get createChooseType => 'Tipo de restricción';

  @override
  String get createChooseSide => 'Lado';

  @override
  String get createChooseAxis => 'Eje de simetría';

  @override
  String get createChooseSize => 'Tamaño del grupo';

  @override
  String get createChooseLetter => 'Letra';

  @override
  String get createChooseValue => 'Valor';

  @override
  String get createChooseCount => 'Cantidad';

  @override
  String get createMotifWidth => 'Ancho del patrón';

  @override
  String get createMotifHeight => 'Alto del patrón';

  @override
  String createLetterGroupMode(String letter) {
    return 'Toca celdas para el grupo $letter, luego presiona Listo';
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
  String get collectionMyPuzzles => 'Mis puzzles';
}
