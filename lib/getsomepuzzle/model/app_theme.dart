import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/settings.dart';

/// Theme extension carrying all puzzle-specific colors.
///
/// Attach an instance to each [ThemeData] via `extensions: [puzzleColorsLight]`
/// (or `puzzleColorsDark`) and consume in widgets with
/// `Theme.of(context).extension<PuzzleColors>()!`.
class PuzzleColors extends ThemeExtension<PuzzleColors> {
  // --- Cell colors ---
  final Color cellBgUndecided;
  final Color cellBgBlack;
  final Color cellBgWhite;
  final Color cellFgUndecided;
  final Color cellFgBlack;
  final Color cellFgWhite;
  final Color cellBgPurple;
  final Color cellFgPurple;

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
    required this.cellBgUndecided,
    required this.cellBgBlack,
    required this.cellBgWhite,
    required this.cellFgUndecided,
    required this.cellFgBlack,
    required this.cellFgWhite,
    required this.cellBgPurple,
    required this.cellFgPurple,
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
    Color? cellBgUndecided,
    Color? cellBgBlack,
    Color? cellBgWhite,
    Color? cellFgUndecided,
    Color? cellFgBlack,
    Color? cellFgWhite,
    Color? cellBgPurple,
    Color? cellFgPurple,
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
      cellBgUndecided: cellBgUndecided ?? this.cellBgUndecided,
      cellBgBlack: cellBgBlack ?? this.cellBgBlack,
      cellBgWhite: cellBgWhite ?? this.cellBgWhite,
      cellFgUndecided: cellFgUndecided ?? this.cellFgUndecided,
      cellFgBlack: cellFgBlack ?? this.cellFgBlack,
      cellFgWhite: cellFgWhite ?? this.cellFgWhite,
      cellBgPurple: cellBgPurple ?? this.cellBgPurple,
      cellFgPurple: cellFgPurple ?? this.cellFgPurple,
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
      cellBgUndecided: Color.lerp(cellBgUndecided, other.cellBgUndecided, t)!,
      cellBgBlack: Color.lerp(cellBgBlack, other.cellBgBlack, t)!,
      cellBgWhite: Color.lerp(cellBgWhite, other.cellBgWhite, t)!,
      cellFgUndecided: Color.lerp(cellFgUndecided, other.cellFgUndecided, t)!,
      cellFgBlack: Color.lerp(cellFgBlack, other.cellFgBlack, t)!,
      cellFgWhite: Color.lerp(cellFgWhite, other.cellFgWhite, t)!,
      cellBgPurple: Color.lerp(cellBgPurple, other.cellBgPurple, t)!,
      cellFgPurple: Color.lerp(cellFgPurple, other.cellFgPurple, t)!,
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
}

const puzzleColorsLight = PuzzleColors(
  cellBgUndecided: Color(0xFFEEE8D5), // base2
  cellBgBlack: Color(0xFFB58900), // jaune (valeur 1)
  cellBgWhite: Color(0xFFD33682), // magenta (valeur 2)
  cellBgPurple: Color(0xFF2AA198), // cyan (valeur 3)
  cellFgUndecided: Color(0xFF657B83), // base00
  cellFgBlack: Color(0xFF002B36), // base03 (contraste sur jaune)
  cellFgWhite: Color(0xFFFDF6E3), // base3 (contraste sur magenta)
  cellFgPurple: Color(0xFF002B36), // base03 (contraste sur cyan)
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
  constraintInvalid: Color(0xFFDC322F), // rouge
  constraintGrayed: Color(0xFF93A1A1), // base1
);

const puzzleColorsDark = PuzzleColors(
  cellBgUndecided: Color(0xFF073642), // base02
  cellBgBlack: Color(0xFFB58900), // jaune (valeur 1)
  cellBgWhite: Color(0xFFD33682), // magenta (valeur 2)
  cellBgPurple: Color(0xFF2AA198), // cyan (valeur 3)
  cellFgUndecided: Color(0xFF839496), // base0
  cellFgBlack: Color(0xFF002B36), // base03 (contraste sur jaune)
  cellFgWhite: Color(0xFFFDF6E3), // base3 (contraste sur magenta)
  cellFgPurple: Color(0xFF002B36), // base03 (contraste sur cyan)
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
  constraintInvalid: Color(0xFFDC322F), // rouge
  constraintGrayed: Color(0xFF586E75), // base01
);

/// Maps our [ThemeModeType] to Flutter's [ThemeMode].
ThemeMode resolveThemeMode(ThemeModeType type) {
  switch (type) {
    case ThemeModeType.system:
      return ThemeMode.system;
    case ThemeModeType.light:
      return ThemeMode.light;
    case ThemeModeType.dark:
      return ThemeMode.dark;
  }
}

/// Light theme.
final lightTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFFB58900), // solarized yellow
    brightness: Brightness.light,
  ),
  useMaterial3: true,
  extensions: const [puzzleColorsLight],
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
