import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/same_size.dart';

/// In-cell indicator for a [SameSize] constraint: a small suit glyph in the
/// bottom-right corner, ~1/3 of the cell size, separated from the corner by
/// a margin.
class SameSizeWidget extends StatelessWidget {
  const SameSizeWidget({
    super.key,
    required this.constraint,
    required this.fgcolor,
    required this.cellSize,
  });

  final SameSize constraint;
  final Color fgcolor;
  final double cellSize;

  @override
  Widget build(BuildContext context) {
    // Glyph occupies roughly one third of the cell; margin keeps it clear of
    // the bottom-right corner (and any cell border).
    final glyphSize = cellSize / 3;
    final margin = cellSize * 0.12;
    return SizedBox(
      width: cellSize,
      height: cellSize,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: margin,
            bottom: margin,
            child: Text(
              constraint.glyph,
              style: TextStyle(fontSize: glyphSize, color: fgcolor),
            ),
          ),
        ],
      ),
    );
  }
}
