import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';
import 'package:getsomepuzzle/widgets/cell.dart';
import 'package:getsomepuzzle/widgets/motif.dart';
import 'package:getsomepuzzle/widgets/quantity.dart';

const forbiddenColor = Color.fromARGB(255, 185, 86, 202);
const mandatoryColor = Colors.lightBlue;

class PuzzleWidget extends StatelessWidget {
  const PuzzleWidget({
    super.key,
    required this.currentPuzzle,
    required this.onCellTap,
    required this.cellSize,
  });

  final Puzzle currentPuzzle;
  final ValueChanged<int> onCellTap;
  final double cellSize;

  void _handleCellTap(int idx) {
    onCellTap(idx);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      spacing: 2,
      children: [
        Wrap(
          direction: Axis.horizontal,
          alignment: WrapAlignment.center,
          spacing: 2,
          runSpacing: 2,
          children: [
            for (var constraint in currentPuzzle.constraints)
              if (constraint is Motif)
                MotifWidget(
                  motif: constraint.motif,
                  bgColor: constraint is ForbiddenMotif
                      ? forbiddenColor
                      : mandatoryColor,
                  borderColor: constraint.isValid ? Colors.green : Colors.red,
                  cellSize: cellSize,
                )
              else if (constraint is QuantityConstraint)
                QuantityWidget(
                  value: constraint.value,
                  count: constraint.count,
                  bgColor: mandatoryColor,
                  borderColor: constraint.isValid ? Colors.green : Colors.red,
                  cellSize: cellSize,
                ),
          ],
        ),
        Table(
          border: TableBorder.all(),
          defaultColumnWidth: FixedColumnWidth(cellSize),
          children: [
            for (var (rowidx, row) in currentPuzzle.getRows().indexed)
              TableRow(
                children: [
                  for (var (cellidx, cell) in row.indexed)
                    CellWidget(
                      value: cell.value,
                      readonly: cell.readonly,
                      constraints:
                          currentPuzzle.cellConstraints[rowidx *
                                  currentPuzzle.width +
                              cellidx],
                      cellSize: cellSize,
                      onTap: () => {
                        _handleCellTap(rowidx * currentPuzzle.width + cellidx),
                      },
                    ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
