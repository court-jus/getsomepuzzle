import 'package:flutter/material.dart';

class PauseOverlay extends StatelessWidget {
  const PauseOverlay({
    super.key,
    required this.onResume,
    required this.width,
    required this.height,
    required this.iconSize,
    this.subtitle,
  });

  final VoidCallback onResume;
  final double width;
  final double height;
  final double iconSize;

  /// Optional explanation of why the game is paused (idle, focus lost).
  /// Rendered below the pause icon when non-null.
  final String? subtitle;

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
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.pause, size: iconSize),
                if (subtitle != null) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      subtitle!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
