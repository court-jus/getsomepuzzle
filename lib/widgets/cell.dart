import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraint.dart';

const bgColors = {0: Colors.cyan, 1: Colors.black, 2: Colors.white};
const fgColors = {0: Colors.black, 1: Colors.white, 2: Colors.black};

class CellWidget extends StatelessWidget {
  // Constructor
  const CellWidget({
    super.key,
    required this.value,
    required this.readonly,
    required this.onTap,
    this.constraint,
  });

  // Attributes
  final int value;
  final bool readonly;
  final Constraint? constraint;
  final VoidCallback onTap;

  // Methods
  void _handleTap() {
    onTap();
  }

  // Build UI
  @override
  Widget build(BuildContext context) {
    final color = bgColors[value];

    final Widget label = constraint == null ? Text(" ") : constraint!.toWidget(fgColors[value] ?? Colors.black);
    return GestureDetector(
      onTap: _handleTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          border: BoxBorder.all(
            width: readonly ? 4 : 1,
            color: Colors.blueAccent,
          ),
        ),
        child: SizedBox(
          width: 64,
          height: 64,
          child: Center(child: label),
        ),
      ),
    );
  }
}
