import 'package:flutter/material.dart';

const bgColors = {0: Colors.transparent, 1: Colors.black, 2: Colors.white};
const motifCellSize = 10.0;
const motifSize = 64.0;

class MotifWidget extends StatelessWidget {
  // Constructor
  const MotifWidget({
    super.key,
    required this.motif,
    required this.bgColor,
    required this.borderColor,
  });

  // Attributes
  final List<List<int>> motif;
  final Color bgColor;
  final Color borderColor;

  // Build UI
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bgColor,
        border: BoxBorder.all(color: borderColor, width: 4),
      ),
      child: SizedBox(
        width: motifSize,
        height: motifSize,
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
