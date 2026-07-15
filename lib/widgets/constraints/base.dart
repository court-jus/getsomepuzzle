import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/app_theme.dart';

extension ConstraintDisplay on Constraint {
  bool get isGrayedOut => isComplete && isValid && !isHighlighted;

  Color borderColor(PuzzleColors pc) {
    if (isHighlighted && isValid) return pc.highlight;
    if (isGrayedOut) return Colors.grey;
    if (!isValid) return pc.constraintInvalid;
    return pc.constraintValid;
  }

  double get borderWidth => (isHighlighted || !isValid) ? 5.0 : 2.0;
}
