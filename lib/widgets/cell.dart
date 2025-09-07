import 'dart:math';

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
    this.constraints,
  });

  // Attributes
  final int value;
  final bool readonly;
  final List<Constraint>? constraints;
  final VoidCallback onTap;

  // Methods
  void _handleTap() {
    onTap();
  }

  // Build UI
  @override
  Widget build(BuildContext context) {
    final color = bgColors[value];

    int widgetScale = 1;
    if (constraints != null) {
      // 1: 1, 2: 2, 3: 2, 4: 2, 5: 3
      widgetScale = sqrt(constraints!.length).ceil();
    }
    final Widget label = constraints == null ? Text(" ") : Wrap(
      alignment: WrapAlignment.center,
      children: [
        for (final constraint in constraints!)
        constraint.toWidget(
          fgColors[value] ?? Colors.black,
          count: widgetScale,
        )
      ],
    );
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
