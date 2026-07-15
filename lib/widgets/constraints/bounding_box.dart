import 'dart:math';

import 'package:flutter/material.dart';
import 'package:getsomepuzzle/widgets/constraints/base.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/bounding_box.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/app_theme.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constants.dart';

/// Renders the BB target as an empty `width × height` grid (transparent cells
/// with borders) on a background tinted with the constraint's colour. Border:
/// green (valid) / deepOrange (invalid) / highlight (highlighted); grayed out
/// when complete and valid. Mirrors the style of [MotifWidget].
class BoundingBoxWidget extends StatelessWidget {
  const BoundingBoxWidget({
    super.key,
    required this.constraint,
    required this.cellSize,
  });

  final BoundingBoxConstraint constraint;
  final double cellSize;

  @override
  Widget build(BuildContext context) {
    final pc = Theme.of(context).extension<PuzzleColors>()!;
    final shouldGrayOut = constraint.isGrayedOut;
    final Color tint;
    switch (constraint.color) {
      case CellValue.black:
        tint = pc.cellBgBlack.withValues(alpha: 0.3);
      case CellValue.white:
        tint = pc.cellBgWhite.withValues(alpha: 0.6);
      case CellValue.purple:
        tint = Colors.purple.withValues(alpha: 0.3);
      case CellValue.free:
        tint = Colors.transparent;
    }
    final bgColor = shouldGrayOut ? Colors.grey.withValues(alpha: 0.3) : tint;
    final borderColor = constraint.borderColor(pc);

    final maxDim = max(constraint.width, constraint.height);
    final boxCellSize =
        (cellSize * motifConstraintInTopBarFillRatio) /
        (maxDim > 3 ? maxDim : 3);

    final grid = Table(
      defaultColumnWidth: FixedColumnWidth(boxCellSize),
      children: [
        for (int r = 0; r < constraint.height; r++)
          TableRow(
            children: [
              for (int c = 0; c < constraint.width; c++)
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: BoxBorder.all(color: Colors.blueGrey),
                  ),
                  child: SizedBox(width: boxCellSize, height: boxCellSize),
                ),
            ],
          ),
      ],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bgColor,
        border: BoxBorder.all(
          color: borderColor,
          width: constraint.borderWidth,
        ),
      ),
      child: SizedBox(
        width: cellSize,
        height: cellSize,
        child: Center(child: grid),
      ),
    );
  }
}
