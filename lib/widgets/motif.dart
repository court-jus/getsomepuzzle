import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constants.dart';

const bgColors = {0: Colors.transparent, 1: Colors.black, 2: Colors.white};

class MotifWidget extends StatelessWidget {
  // Constructor
  const MotifWidget({
    super.key,
    required this.motif,
    required this.bgColor,
    required this.borderColor,
    required this.cellSize,
  });

  // Attributes
  final List<List<int>> motif;
  final Color bgColor;
  final Color borderColor;
  final double cellSize;

  // Build UI
  @override
  Widget build(BuildContext context) {
    double motifCellSize = (cellSize * 0.8) / 3;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bgColor,
        border: BoxBorder.all(color: borderColor, width: 4),
      ),
      child: SizedBox(
        width: cellSize,
        height: cellSize,
        child: Center(
          child: Table(
            defaultColumnWidth: FixedColumnWidth(motifCellSize),
            children: [
              for (var (_, row) in motif.indexed)
                TableRow(
                  children: [
                    for (var (_, cell) in row.indexed)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: bgColors[cell],
                          border: BoxBorder.all(color: Colors.blueGrey),
                        ),
                        child: SizedBox(
                          width: motifCellSize,
                          height: motifCellSize,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
