import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constants.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/different_from.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraint_to_flutter.dart';
import 'package:getsomepuzzle/utils/platform_utils.dart';

const bgColors = {
  0: Color.fromARGB(255, 192, 235, 241),
  1: Colors.black,
  2: Colors.white,
};
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
    required this.onDrag,
    required this.onDragEnd,
    this.onSecondaryTap,
    this.constraints,
    this.borderColor,
    this.borderWidth,
    this.cornerIndicatorValue,
    this.onRightDrag,
    this.onRightDragEnd,
  });

  // Attributes
  final int value;
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
  final int? cornerIndicatorValue;

  final ValueChanged<Offset>? onRightDrag;
  final VoidCallback? onRightDragEnd;

  // Build UI
  @override
  Widget build(BuildContext context) {
    final color = bgColors[value];

    int widgetScale = 1;
    if (constraints != null) {
      widgetScale = sqrt(constraints!.length).ceil();
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
                        color: cornerIndicatorValue == 1
                            ? Colors.black
                            : Colors.white,
                        borderColor: Colors.grey,
                      ),
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
