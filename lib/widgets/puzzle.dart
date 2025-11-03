import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constants.dart';
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

  void _handleCellTap(int idx, {bool secondary = false}) {
    onCellTap(idx);
    if (secondary) onCellTap(idx);
  }

  @override
  Widget build(BuildContext context) {
    double maxConstraintsInTopBarSize = cellSize;
    int numberOfTopBarConstraints = currentPuzzle.constraints.where((constraint) => (constraint is Motif || constraint is QuantityConstraint)).length;
    double totalWidth = MediaQuery.sizeOf(context).width;
    double targetSize = (totalWidth / numberOfTopBarConstraints) - 2; // 2 pixels of spacing between items
    double topBarConstraintsSize = targetSize;
    double adjustedCellSize = cellSize;
    if (targetSize > maxConstraintsInTopBarSize) topBarConstraintsSize = maxConstraintsInTopBarSize;
    if (targetSize < minConstraintsInTopBarSize) {
      // We need to put them on two or more rows and reduce the cells size
      topBarConstraintsSize = minConstraintsInTopBarSize;
      int constraintsPerRow = (totalWidth / topBarConstraintsSize).toInt();
      int numberOfRows = (numberOfTopBarConstraints / constraintsPerRow).ceil();
      double marginNeeded = (numberOfRows - 1) * topBarConstraintsSize;
      adjustedCellSize -= marginNeeded / currentPuzzle.height;
    }
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
                  cellSize: topBarConstraintsSize,
                )
              else if (constraint is QuantityConstraint)
                QuantityWidget(
                  value: constraint.value,
                  count: constraint.count,
                  bgColor: mandatoryColor,
                  borderColor: constraint.isValid ? Colors.green : Colors.red,
                  cellSize: topBarConstraintsSize,
                ),
          ],
        ),
        Table(
          border: TableBorder.all(),
          defaultColumnWidth: FixedColumnWidth(adjustedCellSize),
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
                      cellSize: adjustedCellSize,
                      onTap: () => {
                        _handleCellTap(rowidx * currentPuzzle.width + cellidx)
                      },
                      onSecondaryTap: () => {
                        _handleCellTap(rowidx * currentPuzzle.width + cellidx, secondary: true)
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
