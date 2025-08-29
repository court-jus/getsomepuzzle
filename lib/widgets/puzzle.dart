import 'package:flutter/material.dart';
import 'package:getsomepuzzle_ng/getsomepuzzle/puzzle.dart';
import 'package:getsomepuzzle_ng/widgets/cell.dart';

class PuzzleWidget extends StatelessWidget {
  final Puzzle currentPuzzle;

  const PuzzleWidget({super.key, required this.currentPuzzle});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Color.fromARGB(255, 235, 235, 235)),
      child: Center(
        child: Table(
          border: TableBorder.all(),
          defaultColumnWidth: FixedColumnWidth(64),
          children: [
            for (var row in currentPuzzle.getRows())
              TableRow(children: [
                for (var cellValue in row)
                  CellWidget(value: cellValue)
              ]),
          ],
        ),
      ),
    );
  }
}
