import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/app_theme.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constants.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/bounding_box.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/chain.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/column_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/row_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/group_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/majority.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/transition_row.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/transition_column.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/groups.dart';
import 'package:getsomepuzzle/widgets/cell.dart';
import 'package:getsomepuzzle/widgets/constraints/bounding_box.dart';
import 'package:getsomepuzzle/widgets/constraints/chain.dart';
import 'package:getsomepuzzle/widgets/constraints/column_count.dart';
import 'package:getsomepuzzle/widgets/constraints/row_count.dart';
import 'package:getsomepuzzle/widgets/constraints/group_count.dart';
import 'package:getsomepuzzle/widgets/puzzle_grid_stack.dart';
import 'package:getsomepuzzle/widgets/constraints/motif.dart';
import 'package:getsomepuzzle/widgets/constraints/quantity.dart';
import 'package:getsomepuzzle/widgets/constraints/transition.dart';
import 'package:getsomepuzzle/utils/platform_utils.dart';

class PuzzleWidget extends StatefulWidget {
  const PuzzleWidget({
    super.key,
    required this.currentPuzzle,
    required this.onCellTap,
    required this.onCellDrag,
    required this.onCellDragEnd,
    required this.cellSize,
    this.hintText = "",
    this.hintIsError = false,
    this.onCellRightDrag,
    this.onCellRightDragEnd,
    this.onCellLongPress,
  });

  final Puzzle currentPuzzle;
  final ValueChanged<int> onCellTap;
  final ValueChanged<int> onCellDrag;
  final VoidCallback onCellDragEnd;
  final double cellSize;
  final String hintText;
  final bool hintIsError;
  final ValueChanged<int>? onCellRightDrag;
  final VoidCallback? onCellRightDragEnd;

  /// Long-press = cycle backward. Mobile equivalent of the right-click
  /// on desktop — the host wires both to the same `GameModel` entry.
  final ValueChanged<int>? onCellLongPress;

  @override
  State<PuzzleWidget> createState() => _PuzzleWidgetState();
}

class _PuzzleWidgetState extends State<PuzzleWidget> {
  final Map<Object, GlobalKey> _arrowKeys = {};
  final GlobalKey _cellKey = GlobalKey();
  final GlobalKey _stackKey = GlobalKey();
  final GlobalKey _gridKey = GlobalKey();
  List<Offset>? _arrowStarts;
  Offset? _arrowEnd;

  void _handleCellTap(int idx, {bool secondary = false}) {
    widget.onCellTap(idx);
    if (secondary) widget.onCellTap(idx);
  }

  /// Convert a per-cell drag [offset] (in cell units, relative to the
  /// starting cell at `(rowidx, cellidx)`) into a flat grid index, or
  /// return `null` when the cursor has left the grid. The bounds check
  /// is per-axis so a cursor leaving the grid horizontally does NOT
  /// silently wrap onto the previous/next row via row-major
  /// arithmetic — that wrap puts the painted cell visually far from
  /// the pointer and is the symptom the player sees as a "stray paint"
  /// when their drag exits the side of the grid.
  int? _dragTargetIdx(int rowidx, int cellidx, Offset offset) {
    final targetRow = rowidx + offset.dy.floor();
    final targetCell = cellidx + offset.dx.floor();
    final w = widget.currentPuzzle.width;
    final h = widget.currentPuzzle.height;
    if (targetRow < 0 || targetRow >= h) return null;
    if (targetCell < 0 || targetCell >= w) return null;
    return targetRow * w + targetCell;
  }

  @override
  void didUpdateWidget(PuzzleWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hintText.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _computeArrowPositions();
      });
    } else {
      _arrowStarts = null;
      _arrowEnd = null;
    }
  }

  void _computeArrowPositions() {
    final cellBox = _cellKey.currentContext?.findRenderObject() as RenderBox?;
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (cellBox == null || stackBox == null) {
      if (_arrowStarts != null || _arrowEnd != null) {
        setState(() {
          _arrowStarts = null;
          _arrowEnd = null;
        });
      }
      return;
    }

    final end =
        cellBox.localToGlobal(Offset.zero, ancestor: stackBox) +
        Offset(cellBox.size.width / 2, cellBox.size.height / 2);

    final starts = <Offset>[];
    for (final c in widget.currentPuzzle.constraints) {
      if (!c.isHighlighted) continue;
      final pos = _computeConstraintOrigin(c, stackBox);
      if (pos != null) starts.add(pos);
    }

    if (starts.isEmpty) return;

    setState(() {
      _arrowStarts = starts;
      _arrowEnd = end;
    });
  }

  Offset? _computeConstraintOrigin(Constraint c, RenderObject stackBox) {
    if (c is MajorityConstraint) return _computeMajorityOrigin(c, stackBox);
    if (c is CellsCentricConstraint) {
      return _computeCellCentricOrigin(c, stackBox);
    }
    final key = _arrowKeys[c];
    if (key == null) return null;
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final pos = box.localToGlobal(Offset.zero, ancestor: stackBox);
    return pos + Offset(box.size.width / 2, box.size.height / 2);
  }

  Offset _computeMajorityOrigin(MajorityConstraint mj, RenderObject stackBox) {
    final gridBox = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    final gridPos = gridBox!.localToGlobal(Offset.zero, ancestor: stackBox);
    return gridPos +
        Offset(
          (mj.c0 + mj.c1 + 1) / 2 * widget.cellSize,
          (mj.r0 + mj.r1 + 1) / 2 * widget.cellSize,
        );
  }

  Offset _computeCellCentricOrigin(
    CellsCentricConstraint c,
    RenderObject stackBox,
  ) {
    final gridBox = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    final gridPos = gridBox!.localToGlobal(Offset.zero, ancestor: stackBox);
    final cellIdx = c.indices.first;
    final col = cellIdx % widget.currentPuzzle.width;
    final row = cellIdx ~/ widget.currentPuzzle.width;
    return gridPos +
        Offset((col + 0.5) * widget.cellSize, (row + 0.5) * widget.cellSize);
  }

  @override
  Widget build(BuildContext context) {
    final pc = Theme.of(context).extension<PuzzleColors>()!;
    double maxConstraintsInTopBarSize = widget.cellSize;
    int numberOfTopBarConstraints = widget.currentPuzzle.constraints
        .where(
          (constraint) =>
              (constraint is Motif ||
              constraint is QuantityConstraint ||
              constraint is GroupCountConstraint ||
              constraint is BoundingBoxConstraint ||
              constraint is ChainConstraint),
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

    // Build a map of column index → ColumnCountConstraint for the column header row
    final ccByColumn = <int, ColumnCountConstraint>{};
    for (final c in widget.currentPuzzle.constraints) {
      if (c is ColumnCountConstraint) {
        ccByColumn[c.columnIdx] = c;
      }
    }

    // Build a map of column index → ColumnTransitionConstraint for CT in column header
    final ctByCol = <int, ColumnTransitionConstraint>{};
    for (final c in widget.currentPuzzle.constraints) {
      if (c is ColumnTransitionConstraint) {
        ctByCol[c.columnIdx] = c;
      }
    }

    // Build a map of row index → RowCountConstraint for the left-side bar
    final rcByRow = <int, RowCountConstraint>{};
    for (final c in widget.currentPuzzle.constraints) {
      if (c is RowCountConstraint) {
        rcByRow[c.rowIdx] = c;
      }
    }

    // Build a map of row index → RowTransitionConstraint for RT in left bar
    final rtByRow = <int, RowTransitionConstraint>{};
    for (final c in widget.currentPuzzle.constraints) {
      if (c is RowTransitionConstraint) {
        rtByRow[c.rowIdx] = c;
      }
    }

    // Collect all highlighted constraints for multi-arrow rendering
    final highlightedConstraints = widget.currentPuzzle.constraints
        .where((c) => c.isHighlighted)
        .toList();

    // For MJ zone highlights: union of all highlighted MJ zones
    Set<int>? mjZoneHighlightIndices;
    for (final c in highlightedConstraints.whereType<MajorityConstraint>()) {
      mjZoneHighlightIndices ??= <int>{};
      mjZoneHighlightIndices.addAll(c.indicesFor(widget.currentPuzzle.width));
    }

    // For cell-centric constraints: set of home cell indices
    final constraintHomeCells = <int>{};
    for (final c
        in highlightedConstraints.whereType<CellsCentricConstraint>()) {
      constraintHomeCells.add(c.indices.first);
    }

    // Compute groups once per build so GC widgets and per-cell
    // getCellGroupSize callbacks share a single O(N) flood-fill.
    final groups = getGroups(widget.currentPuzzle);

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
                            : pc.highlight,
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
                          key: constraint.isHighlighted
                              ? _arrowKeys.putIfAbsent(
                                  constraint,
                                  () => GlobalKey(),
                                )
                              : null,
                          constraint: constraint,
                          cellSize: topBarConstraintsSize,
                        )
                      else if (constraint is QuantityConstraint)
                        QuantityWidget(
                          key: constraint.isHighlighted
                              ? _arrowKeys.putIfAbsent(
                                  constraint,
                                  () => GlobalKey(),
                                )
                              : null,
                          constraint: constraint,
                          actualCount: widget.currentPuzzle.cellValues
                              .where((val) => val == constraint.color)
                              .length,
                          oppositeActual: widget.currentPuzzle.cellValues
                              .where(
                                (val) =>
                                    val ==
                                    widget.currentPuzzle.domain
                                        .whereNot((v) => v == constraint.color)
                                        .first,
                              )
                              .length,
                          oppositeTotal:
                              (widget.currentPuzzle.width *
                                  widget.currentPuzzle.height) -
                              constraint.count,
                          cellSize: topBarConstraintsSize,
                          domainLength: widget.currentPuzzle.domain.length,
                        )
                      else if (constraint is GroupCountConstraint)
                        GroupCountWidget(
                          key: constraint.isHighlighted
                              ? _arrowKeys.putIfAbsent(
                                  constraint,
                                  () => GlobalKey(),
                                )
                              : null,
                          constraint: constraint,
                          actualGroupCount: groups
                              .where(
                                (grp) =>
                                    widget.currentPuzzle.cellValues[grp
                                        .first] ==
                                    constraint.color,
                              )
                              .length,
                          cellSize: topBarConstraintsSize,
                        )
                      else if (constraint is BoundingBoxConstraint)
                        BoundingBoxWidget(
                          key: constraint.isHighlighted
                              ? _arrowKeys.putIfAbsent(
                                  constraint,
                                  () => GlobalKey(),
                                )
                              : null,
                          constraint: constraint,
                          cellSize: topBarConstraintsSize,
                        )
                      else if (constraint is ChainConstraint)
                        ChainWidget(
                          key: constraint.isHighlighted
                              ? _arrowKeys.putIfAbsent(
                                  constraint,
                                  () => GlobalKey(),
                                )
                              : null,
                          constraint: constraint,
                          cellSize: topBarConstraintsSize,
                        ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Left side: RC and RT indicators
                    if (rcByRow.isNotEmpty || rtByRow.isNotEmpty)
                      Column(
                        children: [
                          for (
                            int row = 0;
                            row < widget.currentPuzzle.height;
                            row++
                          )
                            if (rcByRow.containsKey(row) ||
                                rtByRow.containsKey(row))
                              Column(
                                children: [
                                  if (rcByRow.containsKey(row))
                                    RowCountWidget(
                                      key: rcByRow[row]!.isHighlighted
                                          ? _arrowKeys.putIfAbsent(
                                              rcByRow[row]!,
                                              () => GlobalKey(),
                                            )
                                          : null,
                                      constraint: rcByRow[row]!,
                                      cellSize: adjustedCellSize,
                                    ),
                                  if (rtByRow.containsKey(row))
                                    TransitionWidget(
                                      key: rtByRow[row]!.isHighlighted
                                          ? _arrowKeys.putIfAbsent(
                                              rtByRow[row]!,
                                              () => GlobalKey(),
                                            )
                                          : null,
                                      constraint: rtByRow[row]!,
                                      cellSize: adjustedCellSize,
                                      axis: Axis.horizontal,
                                    ),
                                ],
                              )
                            else
                              SizedBox(
                                width: adjustedCellSize * 0.7,
                                height: adjustedCellSize,
                              ),
                        ],
                      ),
                    // Right side: CC row + Grid
                    Column(
                      children: [
                        if (ccByColumn.isNotEmpty || ctByCol.isNotEmpty)
                          SizedBox(
                            width: gridWidth,
                            child: Row(
                              children: [
                                for (
                                  int col = 0;
                                  col < widget.currentPuzzle.width;
                                  col++
                                )
                                  if (ccByColumn.containsKey(col) ||
                                      ctByCol.containsKey(col))
                                    SizedBox(
                                      width: adjustedCellSize,
                                      child: Column(
                                        children: [
                                          if (ctByCol.containsKey(col))
                                            TransitionWidget(
                                              key: ctByCol[col]!.isHighlighted
                                                  ? _arrowKeys.putIfAbsent(
                                                      ctByCol[col]!,
                                                      () => GlobalKey(),
                                                    )
                                                  : null,
                                              constraint: ctByCol[col]!,
                                              cellSize: adjustedCellSize,
                                              axis: Axis.vertical,
                                            ),
                                          if (ccByColumn.containsKey(col))
                                            ColumnCountWidget(
                                              key:
                                                  ccByColumn[col]!.isHighlighted
                                                  ? _arrowKeys.putIfAbsent(
                                                      ccByColumn[col]!,
                                                      () => GlobalKey(),
                                                    )
                                                  : null,
                                              constraint: ccByColumn[col]!,
                                              cellSize: adjustedCellSize,
                                            ),
                                        ],
                                      ),
                                    )
                                  else
                                    SizedBox(width: adjustedCellSize),
                              ],
                            ),
                          ),
                        SizedBox(
                          key: _gridKey,
                          width: gridWidth,
                          height: gridHeight,
                          child: PuzzleGridStack(
                            puzzle: widget.currentPuzzle,
                            cellSize: adjustedCellSize,
                            cellBuilder: (idx) => _buildCell(
                              widget.currentPuzzle.cells[idx],
                              idx ~/ widget.currentPuzzle.width,
                              idx % widget.currentPuzzle.width,
                              adjustedCellSize,
                              groups,
                              mjZoneHighlightIndices,
                              constraintHomeCells,
                              pc.highlight,
                            ),
                            overlays: [
                              _buildOptionDotsOverlay(adjustedCellSize),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            if (_arrowStarts != null && _arrowEnd != null)
              for (final start in _arrowStarts!)
                Positioned.fill(
                  key: ValueKey('arrow_${start.hashCode}'),
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ArrowPainter(
                        start: start,
                        end: _arrowEnd!,
                        color: pc.highlight,
                      ),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }

  Widget _buildOptionDotsOverlay(double cellSize) {
    final puzzle = widget.currentPuzzle;
    if (puzzle.domain.length <= 2) return const SizedBox.shrink();

    final list = <Widget>[];
    for (var i = 0; i < puzzle.cells.length; i++) {
      final cell = puzzle.cells[i];
      if (cell.value != CellValue.free) continue;
      final col = i % puzzle.width;
      final row = i ~/ puzzle.width;
      list.add(
        Positioned(
          left: col * cellSize,
          width: cellSize,
          bottom: (puzzle.height - row - 1) * cellSize + cellSize * 0.04,
          child: IgnorePointer(
            child: OptionDots(options: cell.options, cellSize: cellSize),
          ),
        ),
      );
    }

    if (list.isEmpty) return const SizedBox.shrink();
    return Positioned.fill(child: Stack(children: list));
  }

  Widget _buildCell(
    dynamic cell,
    int rowidx,
    int cellidx,
    double adjustedCellSize,
    List<List<int>> groups,
    Set<int>? mjZoneHighlightIndices,
    Set<int> constraintHomeCells,
    Color highlightColor,
  ) {
    final idx = rowidx * widget.currentPuzzle.width + cellidx;

    final Color? zoneTint =
        mjZoneHighlightIndices != null && mjZoneHighlightIndices.contains(idx)
        ? highlightColor.withValues(alpha: 0.15)
        : null;

    // Assign _cellKey to the highlighted cell (arrow endpoint).
    // Cell-centric constraint origins are computed geometrically
    // from the grid position — no GlobalKey needed for them.
    GlobalKey? cellKeyToUse;
    if (cell.isHighlighted) {
      cellKeyToUse = _cellKey;
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
      onLongPress: widget.onCellLongPress != null
          ? () => widget.onCellLongPress!(idx)
          : null,
      onDrag: (Offset offset) {
        final idx = _dragTargetIdx(rowidx, cellidx, offset);
        if (idx != null) widget.onCellDrag(idx);
      },
      onDragEnd: widget.onCellDragEnd,
      onRightDrag: widget.onCellRightDrag != null
          ? (Offset offset) {
              final idx = _dragTargetIdx(rowidx, cellidx, offset);
              if (idx != null) widget.onCellRightDrag!(idx);
            }
          : null,
      onRightDragEnd: widget.onCellRightDragEnd,
      getCellGroupSize: (cellIdx) {
        for (final grp in groups) {
          if (grp.contains(cellIdx)) {
            return grp.length;
          }
        }
        return 0;
      },
      zoneHighlightColor: zoneTint,
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
