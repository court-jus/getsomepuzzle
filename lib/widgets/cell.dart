import 'package:flutter/material.dart';
import 'package:getsomepuzzle_ng/getsomepuzzle/constraint.dart';

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
    final fgcolor = constraint != null
        ? (constraint!.isValid ? fgColors[value] : Colors.redAccent)
        : Colors.green;
    final label = constraint == null ? " " : constraint.toString();
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
          child: Center(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall!.copyWith(color: fgcolor),
            ),
          ),
        ),
      ),
    );
  }
}
