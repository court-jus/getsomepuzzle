import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/settings.dart';

const Map<CellValue, Color> defaultConstraintColors = {
  CellValue.black: Color(0xFF000000),
  CellValue.white: Color(0xFFFFFFFF),
  CellValue.purple: Color(0xFFD33682),
};

const Map<CellValue, Color> defaultOppositeColors = {
  CellValue.white: Color(0xFF000000),
  CellValue.black: Color(0xFFFFFFFF),
  CellValue.purple: Color(0xFFFFFFFF),
};

// Those are used when we need to display white on a light background or black on a dark background
// (IM and MJ constraints)
const Color contrastWhite = Color(0xFF93A1A1);
const Color constrastBlack = Color(0xFF586E75);

const Color defaultInvalidColor = Color(0xFFDC322F);

// Restored legacy (pre-solarized, v1.6.22) palette for the light theme.
const Map<CellValue, Color> lightConstraintColors = {
  CellValue.black: Color(0xFF000000),
  CellValue.white: Color(0xFFFFFFFF),
  CellValue.purple: Color(0xFFE1BEE7),
};

const Map<CellValue, Color> lightOppositeColors = {
  CellValue.black: Color(0xFFFFFFFF),
  CellValue.white: Color(0xFF000000),
  CellValue.purple: Color(0xFF4A148C),
};

// Contrast colors for IM/MJ lines drawn on a light background (legacy look).
const Map<CellValue, Color> lightConstrastedColors = {
  CellValue.black: Color(0xFF333333),
  CellValue.white: Color(0xFFDDDDDD),
  CellValue.purple: Color(0xFF9C27B0),
};

/// Theme extension carrying all puzzle-specific colors.
///
/// Attach an instance to each [ThemeData] via `extensions: [puzzleColorsLight]`
/// (or `puzzleColorsDark`) and consume in widgets with
/// `Theme.of(context).extension<PuzzleColors>()!`.
class PuzzleColors extends ThemeExtension<PuzzleColors> {
  // --- Main colors ---
  final Map<CellValue, Color> constraintColors;
  final Map<CellValue, Color> oppositeColors;
  final Map<CellValue, Color> constrastedColors;
  final Color rawBlack;
  final Color rawWhite;

  // --- Cell colors ---
  final Color cellBgUndecided;
  final Color cellFgUndecided;
  final Color cellFgReadonly;

  // --- Semantic colors ---
  final Color highlight;
  final Color forbidden;
  final Color mandatory;

  // --- Grid ---
  final Color gridBorder;

  // --- UI chrome ---
  final Color drawerHeaderBg;
  final Color bottomBarBg;
  final Color validateButtonBg;
  final Color pauseOverlayBg;
  final Color dialogAccent;

  // --- Constraint states ---
  final Color constraintValid;
  final Color constraintInvalid;
  final Color constraintGrayed;

  const PuzzleColors({
    required this.constraintColors,
    required this.oppositeColors,
    required this.constrastedColors,
    required this.cellBgUndecided,
    required this.rawBlack,
    required this.rawWhite,
    required this.cellFgUndecided,
    required this.cellFgReadonly,
    required this.highlight,
    required this.forbidden,
    required this.mandatory,
    required this.gridBorder,
    required this.drawerHeaderBg,
    required this.bottomBarBg,
    required this.validateButtonBg,
    required this.pauseOverlayBg,
    required this.dialogAccent,
    required this.constraintValid,
    required this.constraintInvalid,
    required this.constraintGrayed,
  });

  @override
  PuzzleColors copyWith({
    Map<CellValue, Color>? constraintColors,
    Map<CellValue, Color>? oppositeColors,
    Map<CellValue, Color>? constrastedColors,
    Color? cellBgUndecided,
    Color? rawBlack,
    Color? rawWhite,
    Color? cellFgUndecided,
    Color? cellFgReadonly,
    Color? highlight,
    Color? forbidden,
    Color? mandatory,
    Color? gridBorder,
    Color? drawerHeaderBg,
    Color? bottomBarBg,
    Color? validateButtonBg,
    Color? pauseOverlayBg,
    Color? dialogAccent,
    Color? constraintValid,
    Color? constraintInvalid,
    Color? constraintGrayed,
  }) {
    return PuzzleColors(
      constraintColors: constraintColors ?? this.constraintColors,
      oppositeColors: oppositeColors ?? this.oppositeColors,
      constrastedColors: constrastedColors ?? this.constrastedColors,
      cellBgUndecided: cellBgUndecided ?? this.cellBgUndecided,
      rawBlack: rawBlack ?? this.rawBlack,
      rawWhite: rawWhite ?? this.rawWhite,
      cellFgUndecided: cellFgUndecided ?? this.cellFgUndecided,
      cellFgReadonly: cellFgReadonly ?? this.cellFgReadonly,
      highlight: highlight ?? this.highlight,
      forbidden: forbidden ?? this.forbidden,
      mandatory: mandatory ?? this.mandatory,
      gridBorder: gridBorder ?? this.gridBorder,
      drawerHeaderBg: drawerHeaderBg ?? this.drawerHeaderBg,
      bottomBarBg: bottomBarBg ?? this.bottomBarBg,
      validateButtonBg: validateButtonBg ?? this.validateButtonBg,
      pauseOverlayBg: pauseOverlayBg ?? this.pauseOverlayBg,
      dialogAccent: dialogAccent ?? this.dialogAccent,
      constraintValid: constraintValid ?? this.constraintValid,
      constraintInvalid: constraintInvalid ?? this.constraintInvalid,
      constraintGrayed: constraintGrayed ?? this.constraintGrayed,
    );
  }

  @override
  PuzzleColors lerp(PuzzleColors? other, double t) {
    if (other is! PuzzleColors) return this;
    return PuzzleColors(
      constraintColors: constraintColors,
      oppositeColors: oppositeColors,
      constrastedColors: constrastedColors,
      cellBgUndecided: Color.lerp(cellBgUndecided, other.cellBgUndecided, t)!,
      rawBlack: Color.lerp(rawBlack, other.rawBlack, t)!,
      rawWhite: Color.lerp(rawWhite, other.rawWhite, t)!,
      cellFgUndecided: Color.lerp(cellFgUndecided, other.cellFgUndecided, t)!,
      cellFgReadonly: Color.lerp(cellFgReadonly, other.cellFgReadonly, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      forbidden: Color.lerp(forbidden, other.forbidden, t)!,
      mandatory: Color.lerp(mandatory, other.mandatory, t)!,
      gridBorder: Color.lerp(gridBorder, other.gridBorder, t)!,
      drawerHeaderBg: Color.lerp(drawerHeaderBg, other.drawerHeaderBg, t)!,
      bottomBarBg: Color.lerp(bottomBarBg, other.bottomBarBg, t)!,
      validateButtonBg: Color.lerp(
        validateButtonBg,
        other.validateButtonBg,
        t,
      )!,
      pauseOverlayBg: Color.lerp(pauseOverlayBg, other.pauseOverlayBg, t)!,
      dialogAccent: Color.lerp(dialogAccent, other.dialogAccent, t)!,
      constraintValid: Color.lerp(constraintValid, other.constraintValid, t)!,
      constraintInvalid: Color.lerp(
        constraintInvalid,
        other.constraintInvalid,
        t,
      )!,
      constraintGrayed: Color.lerp(
        constraintGrayed,
        other.constraintGrayed,
        t,
      )!,
    );
  }

  /// Resolve a semantic colour name (case-insensitive) to this theme's
  /// value. Returns `null` for unknown names.
  ///
  /// Used by the autopilot `textcolor` action so scenario files can
  /// reference theme colours such as `dialogAccent`, `highlight`, etc.
  Color? resolveByName(String name) {
    switch (name.toLowerCase()) {
      case 'dialogaccent':
        return dialogAccent;
      case 'highlight':
        return highlight;
      case 'forbidden':
        return forbidden;
      case 'mandatory':
        return mandatory;
      case 'constraintvalid':
        return constraintValid;
      case 'constraintinvalid':
        return constraintInvalid;
      case 'constraintgrayed':
        return constraintGrayed;
      case 'gridborder':
        return gridBorder;
      case 'drawerheaderbg':
        return drawerHeaderBg;
      case 'bottombarbg':
        return bottomBarBg;
      case 'validatebuttonbg':
        return validateButtonBg;
      case 'pauseoverlaybg':
        return pauseOverlayBg;
      case 'cellbgundecided':
        return cellBgUndecided;
      case 'rawblack':
        return rawBlack;
      case 'rawwhite':
        return rawWhite;
      case 'transparent':
        return const Color(0x00000000);
      default:
        return null;
    }
  }
}

/// Solarized-light palette. Manual "beige" theme: the light theme as it was
/// before the v1.6.22 colors were restored.
const puzzleColorsBeige = PuzzleColors(
  constraintColors: defaultConstraintColors,
  oppositeColors: defaultOppositeColors,
  cellBgUndecided: Color(0xFFEEE8D5),
  rawBlack: Color(0xFF000000),
  rawWhite: Color(0xFFFFFFFF), // Color(0xFFD33682), // magenta (valeur 2)
  constrastedColors: {
    CellValue.black: Color(0xFF000000),
    CellValue.white: contrastWhite,
    CellValue.purple: Color(0xFFD33682),
  },
  cellFgUndecided: Color(0xFF002B36),
  cellFgReadonly: Color(0xFF2AA198),
  highlight: Color(0xFF859900), // vert
  mandatory: Color(0xFF93A1A1), // base1
  forbidden: Color(0xFF586E75), // base01
  gridBorder: Color(0xFF586E75), // base01
  drawerHeaderBg: Color(0xFF073642), // base02
  bottomBarBg: Color(0xFFEEE8D5), // base2
  validateButtonBg: Color(0xFF859900), // vert
  pauseOverlayBg: Color(0x99073642), // base02 à 60%
  dialogAccent: Color(0xFFCB4B16), // orange
  constraintValid: Color(0xFF859900), // vert
  constraintInvalid: defaultInvalidColor, // rouge
  constraintGrayed: Color(0xFF93A1A1), // base1
);

/// Legacy light palette restored from v1.6.22 (pre-solarized colors).
const puzzleColorsLight = PuzzleColors(
  constraintColors: lightConstraintColors,
  oppositeColors: lightOppositeColors,
  constrastedColors: lightConstrastedColors,
  cellBgUndecided: Color(0xFFC0EBF1),
  rawBlack: Color(0xFF000000),
  rawWhite: Color(0xFFFFFFFF),
  cellFgUndecided: Colors.black,
  cellFgReadonly: Colors.blueAccent,
  highlight: Color(0xFF8B7D3C),
  mandatory: Colors.lightBlue,
  forbidden: Color(0xFFB956CA),
  gridBorder: Colors.blueAccent,
  drawerHeaderBg: Colors.blue,
  bottomBarBg: Colors.amber,
  validateButtonBg: Colors.lightGreen,
  pauseOverlayBg: Colors.teal,
  dialogAccent: Colors.amber,
  constraintValid: Colors.green,
  constraintInvalid: Colors.deepOrange,
  constraintGrayed: Colors.grey,
);

const puzzleColorsDark = PuzzleColors(
  constraintColors: defaultConstraintColors,
  oppositeColors: defaultOppositeColors,
  cellBgUndecided: Color(0xFF073642), // base02
  rawBlack: Color(0xFF000000), // Color(0xFFB58900), // jaune (valeur 1)
  rawWhite: Color(0xFFFFFFFF), // Color(0xFFD33682), // magenta (valeur 2)
  constrastedColors: {
    CellValue.black: constrastBlack,
    CellValue.white: Color(0xFFFFFFFF),
    CellValue.purple: Color(0xFFD33682),
  },
  cellFgUndecided: Color(0xFFFDF6E3),
  cellFgReadonly: Color(0xFF2AA198),
  highlight: Color(0xFF859900), // vert
  mandatory: Color(0xFF93A1A1), // base1
  forbidden: Color(0xFF586E75), // base01
  gridBorder: Color(0xFF93A1A1), // base1
  drawerHeaderBg: Color(0xFF073642), // base02
  bottomBarBg: Color(0xFF073642), // base02
  validateButtonBg: Color(0xFF859900), // vert
  pauseOverlayBg: Color(0xCC002B36), // base03 à 80%
  dialogAccent: Color(0xFFCB4B16), // orange
  constraintValid: Color(0xFF859900), // vert
  constraintInvalid: defaultInvalidColor, // rouge
  constraintGrayed: Color(0xFF586E75), // base01
);

/// Maps our [ThemeModeType] to Flutter's [ThemeMode]. The manual "beige"
/// theme is a light theme, so it resolves to [ThemeMode.light]; the system
/// mode keeps switching between light and dark only.
ThemeMode resolveThemeMode(ThemeModeType type) {
  switch (type) {
    case ThemeModeType.system:
      return ThemeMode.system;
    case ThemeModeType.light:
    case ThemeModeType.beige:
      return ThemeMode.light;
    case ThemeModeType.dark:
      return ThemeMode.dark;
  }
}

/// Light theme (legacy v1.6.22 colors).
final lightTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.deepPurple,
    brightness: Brightness.light,
  ),
  useMaterial3: true,
  extensions: const [puzzleColorsLight],
);

/// Beige theme (solarized light colors), only selectable manually.
final beigeTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFFB58900), // solarized yellow
    brightness: Brightness.light,
  ),
  useMaterial3: true,
  extensions: const [puzzleColorsBeige],
);

/// Dark theme.
final darkTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFFB58900), // solarized yellow
    brightness: Brightness.dark,
  ),
  useMaterial3: true,
  extensions: const [puzzleColorsDark],
);
