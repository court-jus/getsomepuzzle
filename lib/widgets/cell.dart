import 'package:flutter/material.dart';

class CellWidget extends StatelessWidget {
  final int value;

  const CellWidget({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    final color = value > 0 ? ((value - 1) * 255) : 240;
    final fgcolor = 255 - color;
    final text = value > 0 ? value.toString() : " ";
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.fromARGB(255, color, color, color),
      ),
      child: SizedBox(
        width: 64,
        height: 64,
        child: Text(
          text,
          style: TextStyle(color: Color.fromARGB(255, fgcolor, fgcolor, fgcolor)),
        ),
      ),
    );
  }
}
