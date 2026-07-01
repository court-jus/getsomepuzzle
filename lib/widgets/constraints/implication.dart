import 'package:flutter/material.dart';

/// Placeholder widget for IM constraints. The actual arrow rendering
/// is handled by [ImplicationPainter] as a background overlay — this
/// widget is only used by the UI registry for previews.
class ImplicationWidget extends StatelessWidget {
  final Color fgcolor;
  final double cellSize;

  const ImplicationWidget({
    super.key,
    required this.fgcolor,
    required this.cellSize,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      '→',
      style: TextStyle(fontSize: cellSize * 0.7, color: fgcolor),
    );
  }
}
