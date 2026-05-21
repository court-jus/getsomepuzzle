import 'package:flutter/material.dart';

void drawDashedRect(
  Canvas canvas,
  Rect rect,
  Paint paint,
  double dashLength,
  double gapLength,
) {
  final path = Path();

  final double left = rect.left;
  final double top = rect.top;
  final double right = rect.right;
  final double bottom = rect.bottom;

  addDashedLine(
    path,
    Offset(left, top),
    Offset(right, top),
    dashLength,
    gapLength,
  );
  addDashedLine(
    path,
    Offset(right, top),
    Offset(right, bottom),
    dashLength,
    gapLength,
  );
  addDashedLine(
    path,
    Offset(right, bottom),
    Offset(left, bottom),
    dashLength,
    gapLength,
  );
  addDashedLine(
    path,
    Offset(left, bottom),
    Offset(left, top),
    dashLength,
    gapLength,
  );

  canvas.drawPath(path, paint);
}

void addDashedLine(
  Path path,
  Offset start,
  Offset end,
  double dashLength,
  double gapLength,
) {
  final totalLength = (end - start).distance;
  final direction = (end - start) / totalLength;
  final segmentLength = dashLength + gapLength;

  double currentDistance = 0;
  while (currentDistance < totalLength) {
    final dashEnd = currentDistance + dashLength;
    final actualDashEnd = dashEnd > totalLength ? totalLength : dashEnd;

    final p1 = start + direction * currentDistance;
    final p2 = start + direction * actualDashEnd;

    path.moveTo(p1.dx, p1.dy);
    path.lineTo(p2.dx, p2.dy);

    currentDistance += segmentLength;
  }
}
