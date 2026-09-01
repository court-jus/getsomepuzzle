import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/base_line_constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/chain.dart';
import 'package:getsomepuzzle/widgets/constraints/base.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/eyes_constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/neighbor_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/row_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constants.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/different_from.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/implication.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/group_size.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/letter_group.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/parity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/same_size.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/symmetry.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/transition_row.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/transition_column.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/rectangular_groups.dart';
import 'package:getsomepuzzle/widgets/constraints/chain.dart';
import 'package:getsomepuzzle/widgets/constraints/column_majority.dart';
import 'package:getsomepuzzle/widgets/constraints/eyes.dart';
import 'package:getsomepuzzle/widgets/constraints/neighbor_count.dart';
import 'package:getsomepuzzle/widgets/constraints/row_count.dart';
import 'package:getsomepuzzle/widgets/constraints/symmetry.dart';
import 'package:getsomepuzzle/widgets/constraints/group_size.dart';
import 'package:getsomepuzzle/widgets/constraints/same_size.dart';
import 'package:getsomepuzzle/widgets/constraints/rectangular_groups.dart';
import 'package:getsomepuzzle/widgets/constraints/transition.dart';

// Arrows for the parity constraint appear smaller so we add a zoom factor
const _parityFontSizeRatio = 40.0 / 36.0;

Widget constraintToFlutter(
  Constraint constraint,
  Color defaultColor,
  double cellSize, {
  required Color highlightColor,
  int count = 1,
  int actualGroupSize = 0,
}) {
  final bool shouldGrayOut = constraint.isGrayedOut;
  final fgcolor = shouldGrayOut
      ? Colors.grey
      : (!constraint.isValid
            ? Colors.redAccent
            : (constraint.isHighlighted ? highlightColor : defaultColor));

  if (constraint is SymmetryConstraint) {
    return _symmetryWidget(constraint, fgcolor, cellSize, count);
  }
  if (constraint is ParityConstraint) {
    return _parityWidget(constraint, fgcolor, cellSize, count);
  }
  if (constraint is GroupSize) {
    return _groupSizeWidget(
      constraint,
      fgcolor,
      cellSize,
      count,
      actualGroupSize,
    );
  }
  if (constraint is LetterGroup) {
    return _textWidget(constraint.letter, fgcolor, cellSize, count);
  }
  if (constraint is SameSize) {
    return _sameSizeWidget(constraint, fgcolor, cellSize, count);
  }
  if (constraint is DifferentFromConstraint) {
    return _textWidget('≠', fgcolor, cellSize, count);
  }
  if (constraint is NeighborCountConstraint) {
    return _neighborCountWidget(constraint, cellSize, count);
  }
  if (constraint is EyesConstraint) {
    return _eyesWidget(constraint, cellSize, count);
  }
  if (constraint is RowCountConstraint) {
    return _rowCountWidget(constraint, cellSize, count);
  }
  if (constraint is ChainConstraint) {
    return _chainWidget(constraint, fgcolor, cellSize, count);
  }
  if (constraint is JRCConstraint) {
    final double widgetSize = cellSize / count;
    return SizedBox(
      width: widgetSize,
      height: widgetSize,
      child: MajorityIndicatorWidget(
        constraint: constraint,
        cellSize: widgetSize,
      ),
    );
  }
  if (constraint is RowTransitionConstraint) {
    return _transitionWidget(constraint, cellSize, count, Axis.horizontal);
  }
  if (constraint is ColumnTransitionConstraint) {
    return _transitionWidget(constraint, cellSize, count, Axis.vertical);
  }
  if (constraint is ImplicationConstraint) {
    return const SizedBox.shrink();
  }
  if (constraint is RectangularGroupsConstraint) {
    return _rectangularGroupsWidget(constraint, cellSize / count);
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
  final double widgetSize = cellSize / count;
  return SizedBox(
    width: widgetSize,
    height: widgetSize,
    child: SymmetryWidget(
      constraint: constraint,
      fgcolor: fgcolor,
      cellSize: widgetSize,
    ),
  );
}

Widget _groupSizeWidget(
  GroupSize constraint,
  Color fgcolor,
  double cellSize,
  int count,
  int actualGroupSize,
) {
  final double widgetSize = cellSize / count;
  return SizedBox(
    width: widgetSize,
    height: widgetSize,
    child: GroupSizeWidget(
      constraint: constraint,
      fgcolor: fgcolor,
      actualGroupSize: actualGroupSize,
      cellSize: widgetSize,
    ),
  );
}

Widget _sameSizeWidget(
  SameSize constraint,
  Color fgcolor,
  double cellSize,
  int count,
) {
  final double widgetSize = cellSize / count;
  return SizedBox(
    width: widgetSize,
    height: widgetSize,
    child: SameSizeWidget(
      constraint: constraint,
      fgcolor: fgcolor,
      cellSize: widgetSize,
    ),
  );
}

Widget _rectangularGroupsWidget(
  RectangularGroupsConstraint constraint,
  double size,
) {
  return SizedBox(
    width: size,
    height: size,
    child: RectangularGroupsWidget(constraint: constraint, cellSize: size),
  );
}

Widget _neighborCountWidget(
  NeighborCountConstraint constraint,
  double cellSize,
  int count,
) {
  final double widgetSize = cellSize / count;
  return SizedBox(
    width: widgetSize,
    height: widgetSize,
    child: NeighborCountWidget(constraint: constraint, cellSize: widgetSize),
  );
}

Widget _eyesWidget(EyesConstraint constraint, double cellSize, int count) {
  final double widgetSize = cellSize / count;
  return SizedBox(
    width: widgetSize,
    height: widgetSize,
    child: EyesWidget(constraint: constraint, cellSize: widgetSize),
  );
}

Widget _rowCountWidget(
  RowCountConstraint constraint,
  double cellSize,
  int count,
) {
  final double widgetSize = cellSize / count;
  return SizedBox(
    width: widgetSize,
    height: widgetSize,
    child: RowCountWidget(constraint: constraint, cellSize: widgetSize),
  );
}

Widget _chainWidget(
  ChainConstraint constraint,
  Color fgcolor,
  double cellSize,
  int count,
) {
  final double widgetSize = cellSize / count;
  return SizedBox(
    width: widgetSize,
    height: widgetSize,
    child: ChainWidget(
      constraint: constraint,
      fgcolor: fgcolor,
      cellSize: widgetSize,
    ),
  );
}

Widget _transitionWidget(
  LineCentricConstraint constraint,
  double cellSize,
  int count,
  Axis axis,
) {
  final double widgetSize = cellSize / count;
  return SizedBox(
    width: widgetSize,
    height: widgetSize,
    child: TransitionWidget(
      constraint: constraint,
      cellSize: widgetSize,
      axis: axis,
    ),
  );
}
