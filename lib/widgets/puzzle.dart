import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constants.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/column_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/different_from.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/helptext.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/widgets/cell.dart';
import 'package:getsomepuzzle/widgets/column_count.dart';
import 'package:getsomepuzzle/widgets/different_from_painter.dart';
import 'package:getsomepuzzle/widgets/motif.dart';
import 'package:getsomepuzzle/widgets/quantity.dart';
import 'package:getsomepuzzle/widgets/textpuzzle.dart';
import 'package:getsomepuzzle/utils/platform_utils.dart';

class PuzzleWidget extends StatefulWidget {
  const PuzzleWidget({
    super.key,
    required this.currentPuzzle,
    required this.onCellTap,
    required this.onCellDrag,
    required this.onCellDragEnd,
    required this.cellSize,
    required this.locale,
    this.hintText = "",
    this.hintIsError = false,
    this.onCellRightDrag,
    this.onCellRightDragEnd,
  });

  final Puzzle currentPuzzle;
  final ValueChanged<int> onCellTap;
  final ValueChanged<int> onCellDrag;
  final VoidCallback onCellDragEnd;
  final double cellSize;
  final String locale;
  final String hintText;
  final bool hintIsError;
  final ValueChanged<int>? onCellRightDrag;
  final VoidCallback? onCellRightDragEnd;

  @override
  State<PuzzleWidget> createState() => _PuzzleWidgetState();
}

class _PuzzleWidgetState extends State<PuzzleWidget> {
  final GlobalKey _constraintKey = GlobalKey();
  final GlobalKey _cellKey = GlobalKey();
  final GlobalKey _stackKey = GlobalKey();
  Offset? _arrowStart;
  Offset? _arrowEnd;

  void _handleCellTap(int idx, {bool secondary = false}) {
    widget.onCellTap(idx);
    if (secondary) widget.onCellTap(idx);
  }

  @override
  void didUpdateWidget(PuzzleWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hintText.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _computeArrowPositions();
      });
    } else {
      _arrowStart = null;
      _arrowEnd = null;
    }
  }

  void _computeArrowPositions() {
    final constraintBox =
        _constraintKey.currentContext?.findRenderObject() as RenderBox?;
    final cellBox = _cellKey.currentContext?.findRenderObject() as RenderBox?;
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (constraintBox == null || cellBox == null || stackBox == null) {
      if (_arrowStart != null || _arrowEnd != null) {
        setState(() {
          _arrowStart = null;
          _arrowEnd = null;
        });
      }
      return;
    }
    final constraintPos = constraintBox.localToGlobal(
      Offset.zero,
      ancestor: stackBox,
    );
    final cellPos = cellBox.localToGlobal(Offset.zero, ancestor: stackBox);
    final start =
        constraintPos +
        Offset(constraintBox.size.width / 2, constraintBox.size.height / 2);
    final end =
        cellPos + Offset(cellBox.size.width / 2, cellBox.size.height / 2);
    if (start != _arrowStart || end != _arrowEnd) {
      setState(() {
        _arrowStart = start;
        _arrowEnd = end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    double maxConstraintsInTopBarSize = widget.cellSize;
    int numberOfTopBarConstraints = widget.currentPuzzle.constraints
        .where(
          (constraint) =>
              (constraint is Motif || constraint is QuantityConstraint),
        )
        .length;
    double totalWidth = MediaQuery.sizeOf(context).width;
    double targetSize =
        (totalWidth / numberOfTopBarConstraints) -
        2; // 2 pixels of spacing between items
    double topBarConstraintsSize = targetSize;
    double adjustedCellSize = widget.cellSize;
    if (targetSize > maxConstraintsInTopBarSize) {
      topBarConstraintsSize = maxConstraintsInTopBarSize;
    }
    if (targetSize < minConstraintsInTopBarSize) {
      topBarConstraintsSize = minConstraintsInTopBarSize;
      int constraintsPerRow = (totalWidth / topBarConstraintsSize).toInt();
      int numberOfRows = (numberOfTopBarConstraints / constraintsPerRow).ceil();
      double marginNeeded = (numberOfRows - 1) * topBarConstraintsSize;
      adjustedCellSize -= marginNeeded / widget.currentPuzzle.height;
    }

    // Find the highlighted constraint (for arrow source)
    Constraint? highlightedConstraint;
    for (var c in widget.currentPuzzle.constraints) {
      if (c.isHighlighted) {
        highlightedConstraint = c;
        break;
      }
    }

    // Build a map of column index → ColumnCountConstraint for the column header row
    final ccByColumn = <int, ColumnCountConstraint>{};
    for (final c in widget.currentPuzzle.constraints) {
      if (c is ColumnCountConstraint) {
        ccByColumn[c.columnIdx] = c;
      }
    }

    // Find if the highlighted constraint is a cell-centric one
    final bool constraintIsInTopBar =
        highlightedConstraint is Motif ||
        highlightedConstraint is QuantityConstraint ||
        highlightedConstraint is ColumnCountConstraint;

    // For cell-centric constraints, find the constraint's home cell index
    int? constraintCellIdx;
    if (highlightedConstraint != null &&
        !constraintIsInTopBar &&
        highlightedConstraint is CellsCentricConstraint) {
      constraintCellIdx = highlightedConstraint.indices.first;
    }

    // Only assign arrow keys when there's a highlighted cell (arrow endpoint).
    // Without a highlighted cell, there's no arrow to draw, so no need for
    // _constraintKey on a Table cell (avoids GlobalKey migration conflicts).
    final hasHighlightedCell = widget.currentPuzzle.cells.any(
      (c) => c.isHighlighted,
    );

    final hasDF = widget.currentPuzzle.constraints.any(
      (c) => c is DifferentFromConstraint,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final gridHeight = adjustedCellSize * widget.currentPuzzle.height;
        final gridWidth = adjustedCellSize * widget.currentPuzzle.width;

        return Stack(
          key: _stackKey,
          clipBehavior: Clip.none,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.start,
              spacing: 2,
              children: [
                if (widget.hintText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      widget.hintText,
                      style: TextStyle(
                        color: widget.hintIsError
                            ? Colors.deepOrange
                            : highlightColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                Wrap(
                  direction: Axis.horizontal,
                  alignment: WrapAlignment.center,
                  spacing: 2,
                  runSpacing: 2,
                  children: [
                    for (var constraint in widget.currentPuzzle.constraints)
                      if (constraint is Motif)
                        MotifWidget(
                          key:
                              (constraint.isHighlighted && constraintIsInTopBar)
                              ? _constraintKey
                              : null,
                          constraint: constraint,
                          cellSize: topBarConstraintsSize,
                        )
                      else if (constraint is QuantityConstraint)
                        QuantityWidget(
                          key:
                              (constraint.isHighlighted && constraintIsInTopBar)
                              ? _constraintKey
                              : null,
                          constraint: constraint,
                          actualCount: widget.currentPuzzle.cellValues
                              .where((val) => val == constraint.value)
                              .length,
                          oppositeActual: widget.currentPuzzle.cellValues
                              .where(
                                (val) =>
                                    val ==
                                    widget.currentPuzzle.domain
                                        .whereNot((v) => v == constraint.value)
                                        .first,
                              )
                              .length,
                          oppositeTotal:
                              (widget.currentPuzzle.width *
                                  widget.currentPuzzle.height) -
                              constraint.count,
                          cellSize: topBarConstraintsSize,
                        )
                      else if (constraint is HelpText)
                        SizedBox(
                          width: totalWidth - 20,
                          child: TextpuzzleWidget(
                            textName: constraint.text,
                            locale: widget.locale,
                          ),
                        ),
                  ],
                ),
                const SizedBox(height: 10),
                if (ccByColumn.isNotEmpty)
                  SizedBox(
                    width: gridWidth,
                    child: Row(
                      children: [
                        for (
                          int col = 0;
                          col < widget.currentPuzzle.width;
                          col++
                        )
                          if (ccByColumn.containsKey(col))
                            ColumnCountWidget(
                              key:
                                  (ccByColumn[col]!.isHighlighted &&
                                      constraintIsInTopBar)
                                  ? _constraintKey
                                  : null,
                              constraint: ccByColumn[col]!,
                              cellSize: adjustedCellSize,
                            )
                          else
                            SizedBox(width: adjustedCellSize),
                      ],
                    ),
                  ),
                SizedBox(
                  width: gridWidth,
                  height: gridHeight,
                  child: Stack(
                    children: [
                      Table(
                        border: TableBorder.all(),
                        defaultColumnWidth: FixedColumnWidth(adjustedCellSize),
                        children: [
                          for (var (rowidx, row)
                              in widget.currentPuzzle.getRows().indexed)
                            TableRow(
                              children: [
                                for (var (cellidx, cell) in row.indexed)
                                  _buildCell(
                                    cell,
                                    rowidx,
                                    cellidx,
                                    adjustedCellSize,
                                    constraintIsInTopBar,
                                    constraintCellIdx,
                                    hasHighlightedCell,
                                  ),
                              ],
                            ),
                        ],
                      ),
                      if (hasDF)
                        IgnorePointer(
                          child: CustomPaint(
                            painter: DifferentFromPainter(
                              constraints: widget.currentPuzzle.constraints
                                  .whereType<DifferentFromConstraint>()
                                  .toList(),
                              cellSize: adjustedCellSize,
                              gridWidth: widget.currentPuzzle.width,
                              defaultColor: Colors.black87,
                              highlightColor: highlightColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (_arrowStart != null && _arrowEnd != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ArrowPainter(
                      start: _arrowStart!,
                      end: _arrowEnd!,
                      color: highlightColor,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCell(
    dynamic cell,
    int rowidx,
    int cellidx,
    double adjustedCellSize,
    bool constraintIsInTopBar,
    int? constraintCellIdx,
    bool hasHighlightedCell,
  ) {
    final idx = rowidx * widget.currentPuzzle.width + cellidx;

    // Assign _cellKey to highlighted cell, _constraintKey to constraint's home cell.
    // Only assign _constraintKey when there's also a highlighted cell (arrow endpoint),
    // otherwise the key can migrate between Table cells and cause GlobalKey conflicts.
    GlobalKey? cellKeyToUse;
    if (cell.isHighlighted) {
      cellKeyToUse = _cellKey;
    }
    if (!constraintIsInTopBar &&
        constraintCellIdx == idx &&
        hasHighlightedCell) {
      cellKeyToUse = _constraintKey;
    }

    return CellWidget(
      key: cellKeyToUse,
      value: cell.value,
      idx: idx,
      readonly: cell.readonly,
      isHighlighted: cell.isHighlighted,
      constraints: widget.currentPuzzle.cellConstraints[idx],
      cellSize: adjustedCellSize,
      onTap: () => _handleCellTap(idx),
      onSecondaryTap: isDesktopOrWeb
          ? () => _handleCellTap(idx, secondary: true)
          : null,
      onDrag: (Offset offset) {
        final int targetRow = (rowidx + offset.dy).floor();
        final int targetCell = (cellidx + offset.dx).floor();
        widget.onCellDrag(targetRow * widget.currentPuzzle.width + targetCell);
      },
      onDragEnd: widget.onCellDragEnd,
      onRightDrag: widget.onCellRightDrag != null
          ? (Offset offset) {
              final int targetRow = (rowidx + offset.dy).floor();
              final int targetCell = (cellidx + offset.dx).floor();
              widget.onCellRightDrag!(
                targetRow * widget.currentPuzzle.width + targetCell,
              );
            }
          : null,
      onRightDragEnd: widget.onCellRightDragEnd,
      getCellGroupSize: (cellIdx) {
        final groups = widget.currentPuzzle.getGroups();
        for (final grp in groups) {
          if (grp.contains(cellIdx)) {
            return grp.length;
          }
        }
        return 0;
      },
    );
  }
}

class _ArrowPainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;

  _ArrowPainter({required this.start, required this.end, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke;

    // Curve the arrow to the side that has more room
    final midY = (start.dy + end.dy) / 2;
    final curveAmount = (end.dx - start.dx).abs() * 0.3 + 20;
    // Pick the side: if going left-to-right, curve left; if right-to-left, curve right
    final side = start.dx <= end.dx ? -1.0 : 1.0;
    final ctrlX1 = start.dx + side * curveAmount;
    final ctrlX2 = end.dx + side * curveAmount;
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(ctrlX1, midY, ctrlX2, midY, end.dx, end.dy);
    canvas.drawPath(path, paint);

    // Arrowhead: compute tangent from last control point to end
    final arrowSize = 30.0;
    final angle = atan2(end.dy - midY, end.dx - ctrlX2);
    final shiftedEnd = end + Offset.fromDirection(angle, arrowSize / 2);
    final p1 = end - Offset.fromDirection(angle - 0.8, arrowSize / 2);
    final p2 = end - Offset.fromDirection(angle + 0.8, arrowSize / 2);
    final arrowPath = Path()
      ..moveTo(shiftedEnd.dx, shiftedEnd.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();
    canvas.drawPath(
      arrowPath,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter oldDelegate) =>
      start != oldDelegate.start || end != oldDelegate.end;
}
