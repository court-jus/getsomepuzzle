import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/different_from.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/implication.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/majority.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/app_theme.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/widgets/cell_background_painter.dart';
import 'package:getsomepuzzle/widgets/constraints/majority.dart';
import 'package:getsomepuzzle/widgets/different_from_painter.dart';
import 'package:getsomepuzzle/widgets/implication_painter.dart';

/// The layered puzzle grid shared by the game ([PuzzleWidget]) and the editor
/// (`create_page`): cell-colour background, the cross-cell constraint painters
/// (IM / DF / MJ) and the `Table` of cells, stacked in one canonical order.
///
/// Both call sites render their grid through this widget so the painter
/// layering can never drift apart again (the regression that lost the editor's
/// cell backgrounds when IM moved colouring into [CellBackgroundPainter]).
/// Each caller keeps its own cell widget (via [cellBuilder]) and its own
/// surrounding chrome; only the stack of background/painters/table is shared.
class PuzzleGridStack extends StatelessWidget {
  const PuzzleGridStack({
    super.key,
    required this.puzzle,
    required this.cellSize,
    required this.cellBuilder,
    this.dfDefaultColor = Colors.black87,
    this.dfHighlightColor,
    this.overlays = const [],
  });

  /// Source of cell values (background painter) and grid dimensions; the
  /// IM/DF/MJ painters are derived from its `constraints`.
  final Puzzle puzzle;
  final double cellSize;

  /// Builds the cell widget for a flat cell index `row * width + col`.
  final Widget Function(int index) cellBuilder;

  /// DF arrow colours: game uses black87 / theme highlight, editor uses
  /// blueGrey / green. When [dfHighlightColor] is null the theme's
  /// `PuzzleColors.highlight` is used.
  final Color dfDefaultColor;
  final Color? dfHighlightColor;

  /// Extra stack children drawn above the constraint painters (e.g. the game's
  /// option dots overlay).
  final List<Widget> overlays;

  @override
  Widget build(BuildContext context) {
    final pc = Theme.of(context).extension<PuzzleColors>()!;
    final width = puzzle.width;
    final height = puzzle.height;
    final imConstraints = puzzle.constraints
        .whereType<ImplicationConstraint>()
        .toList();
    final dfConstraints = puzzle.constraints
        .whereType<DifferentFromConstraint>()
        .toList();
    final mjConstraints = puzzle.constraints
        .whereType<MajorityConstraint>()
        .toList();

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: CellBackgroundPainter(
                puzzle: puzzle,
                cellSize: cellSize,
                puzzleColors: pc,
              ),
            ),
          ),
        ),
        if (imConstraints.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: ImplicationPainter(
                  constraints: imConstraints,
                  cellSize: cellSize,
                  gridWidth: width,
                  highlightColor: pc.highlight,
                ),
              ),
            ),
          ),
        Table(
          border: TableBorder.all(),
          defaultColumnWidth: FixedColumnWidth(cellSize),
          children: [
            for (var row = 0; row < height; row++)
              TableRow(
                children: [
                  for (var col = 0; col < width; col++)
                    cellBuilder(row * width + col),
                ],
              ),
          ],
        ),
        if (dfConstraints.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: DifferentFromPainter(
                  constraints: dfConstraints,
                  cellSize: cellSize,
                  gridWidth: width,
                  defaultColor: dfDefaultColor,
                  highlightColor: dfHighlightColor ?? pc.highlight,
                  fillColor: pc.mandatory,
                ),
              ),
            ),
          ),
        if (mjConstraints.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: MajorityZonePainter(
                  constraints: mjConstraints,
                  cellSize: cellSize,
                  gridWidth: width,
                  highlightColor: pc.highlight,
                ),
              ),
            ),
          ),
        ...overlays,
      ],
    );
  }
}
