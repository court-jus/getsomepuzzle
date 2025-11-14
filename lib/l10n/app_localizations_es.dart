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
  String get labelWidgetWantedrules => 'Reglas deseadas';

  @override
  String get labelWidgetBannedrules => 'Reglas prohibidas';

  @override
  String get msgCountMatchingPuzzles => 'Puzzles que coinciden con filtros';

  @override
  String get btnCopyClipboard => 'Copiar al portapapeles';
}
