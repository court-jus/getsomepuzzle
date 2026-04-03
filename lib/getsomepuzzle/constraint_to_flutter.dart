import 'dart:math';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:getsomepuzzle/getsomepuzzle/constants.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/different_from.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/parity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/symmetry.dart';

// Arrows for the parity constraint appear smaller so we add a zoom factor
const _parityFontSizeRatio = 40.0 / 36.0;

Widget constraintToFlutter(
  Constraint constraint,
  Color defaultColor,
  double cellSize, {
  int count = 1,
}) {
  final fgcolor = constraint.isHighlighted
      ? highlightColor
      : (constraint.isValid ? defaultColor : Colors.redAccent);

  if (constraint is SymmetryConstraint) {
    return _symmetryWidget(constraint, fgcolor, cellSize, count);
  }
  if (constraint is ParityConstraint) {
    return _parityWidget(constraint, fgcolor, cellSize, count);
  }
  if (constraint is GroupSize) {
    return _textWidget(constraint.toString(), fgcolor, cellSize, count);
  }
  if (constraint is LetterGroup) {
    return _textWidget(constraint.letter, fgcolor, cellSize, count);
  }
  if (constraint is DifferentFromConstraint) {
    return _textWidget('≠', fgcolor, cellSize, count);
  }

  // Default: use toString()
  return _textWidget(constraint.toString(), fgcolor, cellSize, count);
}

Widget _textWidget(String text, Color color, double cellSize, int count) {
  return SizedBox(
    width: cellSize / count,
    height: cellSize / count,
    child: Center(
      child: Text(
        text,
        style: TextStyle(
          fontSize: cellSize * cellSizeToFontSize / count,
          color: color,
        ),
      ),
    ),
  );
}

Widget _parityWidget(
  ParityConstraint constraint,
  Color fgcolor,
  double cellSize,
  int count,
) {
  const icons = {
    "left": Icons.arrow_circle_left_outlined,
    "right": Icons.arrow_circle_right_outlined,
    "horizontal": Icons.swap_horizontal_circle_outlined,
    "vertical": Icons.swap_vert_circle_outlined,
    "top": Icons.arrow_circle_up_outlined,
    "bottom": Icons.arrow_circle_down_outlined,
  };
  if (icons.containsKey(constraint.side)) {
    return SizedBox(
      width: cellSize / count,
      height: cellSize / count,
      child: Center(
        child: Icon(
          icons[constraint.side],
          size: cellSize * cellSizeToFontSize * _parityFontSizeRatio / count,
          color: fgcolor,
        ),
      ),
    );
  }
  return Text("");
}

Widget _symmetryWidget(
  SymmetryConstraint constraint,
  Color fgcolor,
  double cellSize,
  int count,
) {
  final double size = cellSize * cellSizeToFontSize / count;
  Widget icon = FaIcon(FontAwesomeIcons.circleDot, color: fgcolor, size: size);
  if (constraint.axis == 1) {
    icon = FaIcon(FontAwesomeIcons.slash, color: fgcolor, size: size);
  } else if (constraint.axis == 2) {
    icon = FaIcon(
      FontAwesomeIcons.gripLinesVertical,
      color: fgcolor,
      size: size,
    );
  } else if (constraint.axis == 3) {
    icon = Transform.rotate(
      angle: pi / 2,
      child: FaIcon(FontAwesomeIcons.slash, color: fgcolor, size: size),
    );
  } else if (constraint.axis == 4) {
    icon = FaIcon(FontAwesomeIcons.gripLines, color: fgcolor, size: size);
  }
  return SizedBox(
    width: cellSize / count,
    height: cellSize / count,
    child: Center(child: icon),
  );
}
