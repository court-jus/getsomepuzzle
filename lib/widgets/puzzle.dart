import 'package:flutter/material.dart';
import 'package:getsomepuzzle_ng/getsomepuzzle/puzzle.dart';
import 'package:getsomepuzzle_ng/widgets/cell.dart';

class PuzzleWidget extends StatelessWidget {
  const PuzzleWidget({
    super.key,
    required this.currentPuzzle,
    required this.onCellTap,
  });

  final Puzzle currentPuzzle;
  final ValueChanged<int> onCellTap;

  void _handleCellTap(int idx) {
    print("_handle cell tap $idx");
    onCellTap(idx);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Color.fromARGB(255, 235, 235, 235)),
      child: Center(
        child: Table(
          border: TableBorder.all(),
          defaultColumnWidth: FixedColumnWidth(64),
          children: [
            for (var (rowidx, row) in currentPuzzle.getRows().indexed)
              TableRow(
                children: [
                  for (var (cellidx, cell) in row.indexed)
                    CellWidget(
                      value: cell.value,
                      readonly: cell.readonly,
                      constraint:
                          currentPuzzle.cellConstraints[rowidx *
                                  currentPuzzle.width +
                              cellidx],
                      onTap: () => {
                        _handleCellTap(rowidx * currentPuzzle.width + cellidx),
                      },
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
