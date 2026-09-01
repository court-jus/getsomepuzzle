import 'package:flutter/material.dart';
import 'package:getsomepuzzle/widgets/constraints/base.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/rectangular_groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/app_theme.dart';

/// Renders the RE marker: a small blue rectangle in the cell's top-right
/// corner (length = 1/3 of the cell, short side = 1/4, 5% margin from the
/// corner). Default colour is the theme blue ([PuzzleColors.mandatory]); red
/// ([PuzzleColors.constraintInvalid]) appears only in the invalid state.
class RectangularGroupsWidget extends StatelessWidget {
  const RectangularGroupsWidget({
    super.key,
    required this.constraint,
    required this.cellSize,
  });

  final RectangularGroupsConstraint constraint;
  final double cellSize;

  @override
  Widget build(BuildContext context) {
    final pc = Theme.of(context).extension<PuzzleColors>()!;
    final Color color;
    if (constraint.isGrayedOut) {
      color = Colors.grey;
    } else if (!constraint.isValid) {
      color = pc.constraintInvalid;
    } else if (constraint.isHighlighted) {
      color = pc.highlight;
    } else {
      color = pc.mandatory;
    }
    return SizedBox(
      width: cellSize,
      height: cellSize,
      child: Align(
        alignment: Alignment.topRight,
        child: Container(
          margin: EdgeInsets.all(cellSize * 0.05),
          width: cellSize / 3,
          height: cellSize / 4,
          color: color,
        ),
      ),
    );
  }
}
