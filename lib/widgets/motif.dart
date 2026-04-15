import 'dart:math';

import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/shape.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constants.dart';

const _bgColors = {0: Colors.transparent, 1: Colors.black, 2: Colors.white};
const forbiddenColor = Color.fromARGB(255, 185, 86, 202);

class MotifWidget extends StatelessWidget {
  const MotifWidget({
    super.key,
    required this.constraint,
    required this.cellSize,
  });

  final Motif constraint;
  final double cellSize;

  @override
  Widget build(BuildContext context) {
    final isShapeConstraint = constraint is ShapeConstraint;
    final bgColor = constraint is ForbiddenMotif
        ? forbiddenColor
        : mandatoryColor;
    final borderColor = constraint.isHighlighted
        ? highlightColor
        : (constraint.isValid ? Colors.green : Colors.deepOrange);
    final rows = constraint.motif.length;
    final cols = constraint.motif.isNotEmpty ? constraint.motif[0].length : 0;
    final maxDim = rows > cols ? rows : cols;
    double motifCellSize = maxDim > 3
        ? (cellSize * motifConstraintInTopBarFillRatio) / maxDim
        : (cellSize * motifConstraintInTopBarFillRatio) / 3;
    final tableWidget = Table(
      defaultColumnWidth: FixedColumnWidth(motifCellSize),
      children: [
        for (var (_, row) in constraint.motif.indexed)
          TableRow(
            children: [
              for (var (_, cell) in row.indexed)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: _bgColors[cell],
                    border: BoxBorder.all(color: Colors.blueGrey),
                  ),
                  child: SizedBox(width: motifCellSize, height: motifCellSize),
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
          width: constraint.isHighlighted ? 8 : 4,
        ),
      ),
      child: SizedBox(
        width: cellSize,
        height: cellSize,
        child: Center(
          child: isShapeConstraint
              ? Transform.rotate(
                  angle: -pi / 4,
                  alignment: Alignment.center,
                  child: tableWidget,
                )
              : tableWidget,
        ),
      ),
    );
  }
}
