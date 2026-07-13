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
  cellBgUndecided: Color(0xFFC0EBF1),
  cellBgBlack: Colors.black,
  cellBgWhite: Colors.white,
  cellFgUndecided: Colors.black,
  cellFgBlack: Colors.white,
  cellFgWhite: Colors.black,
  cellBgPurple: Color(0xFFE1BEE7),
  cellFgPurple: Color(0xFF4A148C),
  highlight: Color(0xFF8B7D3C),
  forbidden: Color(0xFFB956CA),
  mandatory: Colors.lightBlue,
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
  cellBgUndecided: Color(0xFF3A6070),
  cellBgBlack: Color(0xFF2A2A2A),
  cellBgWhite: Color(0xFFB0B0B0),
  cellFgUndecided: Color(0xFFE0E0E0),
  cellFgBlack: Color(0xFFE0E0E0),
  cellFgWhite: Color(0xFF2A2A2A),
  cellBgPurple: Color(0xFF6A4C93),
  cellFgPurple: Color(0xFFE0E0E0),
  highlight: Color(0xFFD4B84A),
  forbidden: Color(0xFFCE80E0),
  mandatory: Color(0xFF4FC3F7),
  gridBorder: Color(0xFF64B5F6),
  drawerHeaderBg: Color(0xFF1A237E),
  bottomBarBg: Color(0xFF5D4037),
  validateButtonBg: Color(0xFF66BB6A),
  pauseOverlayBg: Color(0xFF004D40),
  dialogAccent: Color(0xFFFFB74D),
  constraintValid: Color(0xFF81C784),
  constraintInvalid: Color(0xFFE57373),
  constraintGrayed: Color(0xFF757575),
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
    seedColor: Colors.deepPurple,
    brightness: Brightness.light,
  ),
  useMaterial3: true,
  extensions: const [puzzleColorsLight],
);

/// Dark theme.
final darkTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.deepPurple,
    brightness: Brightness.dark,
  ),
  useMaterial3: true,
  extensions: const [puzzleColorsDark],
);
