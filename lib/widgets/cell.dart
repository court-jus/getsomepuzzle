import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constants.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/different_from.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/to_flutter.dart';
import 'package:getsomepuzzle/utils/platform_utils.dart';

final bgColors = {
  CellValue.free: Color.fromARGB(255, 192, 235, 241),
  CellValue.black: Colors.black,
  CellValue.white: Colors.white,
  CellValue.purple: Colors.purple[100],
};
const fgColors = {
  CellValue.free: Colors.black,
  CellValue.black: Colors.white,
  CellValue.white: Colors.black,
  CellValue.purple: Colors.green,
};

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
    required this.onDrag,
    required this.onDragEnd,
    this.onSecondaryTap,
    this.constraints,
    this.borderColor,
    this.borderWidth,
    this.cornerIndicatorValue,
    this.onRightDrag,
    this.onRightDragEnd,
    this.getCellGroupSize,
    this.optionDots,
  });

  // Attributes
  final CellValue value;
  final int idx;
  final bool readonly;
  final bool isHighlighted;
  final List<Constraint>? constraints;
  final VoidCallback onTap;
  final VoidCallback? onSecondaryTap;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onDragEnd;
  final double cellSize;

  /// Custom border color (overrides default when set)
  final Color? borderColor;

  /// Custom border width (overrides default when set)
  final double? borderWidth;

  /// If set, draws a small colored triangle in the top-left corner
  final CellValue? cornerIndicatorValue;

  final ValueChanged<Offset>? onRightDrag;
  final VoidCallback? onRightDragEnd;

  /// Callback to get the actual group size for a cell (for GroupSize constraint)
  final int Function(int idx)? getCellGroupSize;

  /// One coloured dot per remaining option, drawn at the bottom of the cell.
  /// Used on 3+ colour puzzles so the player can see why a cell is "narrowed"
  /// — `Cell.options` drives every deduction now but is otherwise invisible.
  /// Callers pass `null` when the dots should not be rendered (cell already
  /// has a value, or domain has 2 colours so option pruning is equivalent to
  /// setValue and the dots would be redundant).
  final List<CellValue>? optionDots;

  // Build UI
  @override
  Widget build(BuildContext context) {
    final color = bgColors[value];

    int widgetScale = 1;
    if (constraints != null) {
      // DF is rendered on the cell border by DifferentFromPainter, not inside
      // the cell, so it must not shrink the in-cell widgets.
      final inCellCount = constraints!
          .where((c) => c is! DifferentFromConstraint)
          .length;
      if (inCellCount > 0) widgetScale = sqrt(inCellCount).ceil();
    }
    final Widget emptyText = Text(" ");
    final Widget label = constraints == null
        ? emptyText
        : Wrap(
            alignment: WrapAlignment.center,
            children: [
              for (final constraint in constraints!)
                if (constraint is! DifferentFromConstraint)
                  constraintToFlutter(
                    constraint,
                    constraint.isHighlighted
                        ? highlightColor
                        : (fgColors[value] ?? Colors.black),
                    cellSize,
                    count: widgetScale,
                    actualGroupSize: getCellGroupSize?.call(idx) ?? 0,
                  ),
            ],
          );

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: isDesktopOrWeb
          ? (event) {
              if (event.kind == PointerDeviceKind.mouse &&
                  event.buttons == kSecondaryMouseButton) {
                final localPos = event.localPosition;
                final offsetX = (localPos.dx / cellSize).floor();
                final offsetY = (localPos.dy / cellSize).floor();
                onRightDrag?.call(
                  Offset(offsetX.toDouble(), offsetY.toDouble()),
                );
              }
            }
          : null,
      onPointerMove: isDesktopOrWeb
          ? (event) {
              if (event.kind == PointerDeviceKind.mouse &&
                  event.buttons == kSecondaryMouseButton) {
                final localPos = event.localPosition;
                final offsetX = (localPos.dx / cellSize).floor();
                final offsetY = (localPos.dy / cellSize).floor();
                onRightDrag?.call(
                  Offset(offsetX.toDouble(), offsetY.toDouble()),
                );
              }
            }
          : null,
      onPointerUp: isDesktopOrWeb
          ? (event) {
              if (event.kind == PointerDeviceKind.mouse) {
                onRightDragEnd?.call();
              }
            }
          : null,
      child: GestureDetector(
        onTap: onTap,
        onVerticalDragUpdate: (details) {
          final localPos = details.localPosition;
          final offsetX = localPos.dx / cellSize;
          final offsetY = localPos.dy / cellSize;
          onDrag(
            Offset(offsetX.floor().toDouble(), offsetY.floor().toDouble()),
          );
        },
        onVerticalDragEnd: (details) => onDragEnd(),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            border: BoxBorder.all(
              width: borderWidth ?? ((readonly || isHighlighted) ? 6 : 1),
              color:
                  borderColor ??
                  (isHighlighted ? highlightColor : Colors.blueAccent),
            ),
          ),
          child: SizedBox(
            width: cellSize,
            height: cellSize,
            child: Stack(
              children: [
                Center(child: label),
                if (cornerIndicatorValue != null)
                  Positioned(
                    top: 0,
                    left: 0,
                    child: CustomPaint(
                      size: Size(cellSize * 0.4, cellSize * 0.4),
                      painter: _CornerTrianglePainter(
                        color: cornerIndicatorValue == CellValue.black
                            ? Colors.black
                            : Colors.white,
                        borderColor: Colors.grey,
                      ),
                    ),
                  ),
                if (optionDots != null && optionDots!.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: cellSize * 0.04,
                    child: _OptionDots(
                      options: optionDots!,
                      cellSize: cellSize,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A horizontal row of small coloured dots, one per remaining option for a
/// cell. Drawn at the bottom of the [CellWidget] when the puzzle uses a
/// 3+ colour domain. Dot colour mirrors the cell-background palette so the
/// player can map each dot to a colour they have already seen on filled
/// cells. A subtle outline keeps the white dot visible against the cyan
/// "free" background.
class _OptionDots extends StatelessWidget {
  const _OptionDots({required this.options, required this.cellSize});

  final List<CellValue> options;
  final double cellSize;

  @override
  Widget build(BuildContext context) {
    final dotSize = cellSize * 0.10;
    final gap = cellSize * 0.04;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < options.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bgColors[options[i]],
              border: Border.all(color: Colors.black54, width: 0.5),
            ),
          ),
        ],
      ],
    );
  }
}

class _CornerTrianglePainter extends CustomPainter {
  final Color color;
  final Color borderColor;

  _CornerTrianglePainter({required this.color, required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _CornerTrianglePainter oldDelegate) =>
      color != oldDelegate.color;
}
