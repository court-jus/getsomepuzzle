import 'package:flutter/material.dart';

const textColors = {0: Colors.transparent, 1: Colors.black, 2: Colors.white};


class QuantityWidget extends StatelessWidget {
  // Constructor
  const QuantityWidget({
    super.key,
    required this.value,
    required this.count,
    required this.bgColor,
    required this.borderColor,
  });

  // Attributes
  final int value;
  final int count;
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
        width: 64,
        height: 64,
        child: Center(child: Text(
          count.toString(),
           style: TextStyle(fontSize: 36, color: textColors[value]),
        )),
      ),
    );
  }
}
