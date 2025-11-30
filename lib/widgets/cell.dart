import 'dart:math';

import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constants.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraint.dart';

const bgColors = {0: Colors.cyan, 1: Colors.black, 2: Colors.white};
const fgColors = {0: Colors.black, 1: Colors.white, 2: Colors.black};

class CellWidget extends StatelessWidget {
  // Constructor
  const CellWidget({
    super.key,
    required this.value,
    required this.idx,
    required this.readonly,
    required this.isHighlighted,
    required this.cellSize,
    required this.onTap,
    required this.onSecondaryTap,
    required this.onDrag,
    required this.onDragEnd,
    this.constraints,
  });

  // Attributes
  final int value;
  final int idx;
  final bool readonly;
  final bool isHighlighted;
  final List<Constraint>? constraints;
  final VoidCallback onTap;
  final VoidCallback onSecondaryTap;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onDragEnd;
  final double cellSize;

  // Build UI
  @override
  Widget build(BuildContext context) {
    final color = bgColors[value];

    int widgetScale = 1;
    if (constraints != null) {
      // 1: 1, 2: 2, 3: 2, 4: 2, 5: 3
      widgetScale = sqrt(constraints!.length).ceil();
    }
    final Widget emptyText = Text(" ");
    // final Widget emptyText = Text(
    //   idx.toString(),
    //   style: TextStyle(color: (fgColors[value] ?? Colors.black)),
    // );
    final Widget label = constraints == null
        ? emptyText
        : Wrap(
            alignment: WrapAlignment.center,
            children: [
              for (final constraint in constraints!)
                constraint.toWidget(
                  constraint.isHighlighted
                      ? highlightColor
                      : (fgColors[value] ?? Colors.black),
                  cellSize,
                  count: widgetScale,
                ),
            ],
          );
    return GestureDetector(
      onTap: onTap,
      onSecondaryTap: onSecondaryTap,
      onVerticalDragUpdate: (details) {
        final localPos = details.localPosition;
        final offsetX = localPos.dx / cellSize;
        final offsetY = localPos.dy / cellSize;
        onDrag(Offset(offsetX.floor().toDouble(), offsetY.floor().toDouble()));
      },
      onVerticalDragEnd: (details) => onDragEnd(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          border: BoxBorder.all(
            width: (readonly || isHighlighted) ? 6 : 1,
            color: isHighlighted ? highlightColor : Colors.blueAccent,
          ),
        ),
        child: SizedBox(
          width: cellSize,
          height: cellSize,
          child: Center(child: label),
        ),
      ),
    );
  }
}
