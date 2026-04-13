import 'package:flutter/material.dart';

class PauseOverlay extends StatelessWidget {
  const PauseOverlay({
    super.key,
    required this.onResume,
    required this.width,
    required this.height,
    required this.iconSize,
  });

  final VoidCallback onResume;
  final double width;
  final double height;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onResume,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.teal,
          borderRadius: BorderRadius.circular(15),
        ),
        child: SizedBox(
          width: width,
          height: height,
          child: Center(child: Icon(Icons.pause, size: iconSize)),
        ),
      ),
    );
  }
}
