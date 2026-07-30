import 'package:flutter/material.dart';

/// Subtitle overlay displayed by the autopilot's `dialog` action.
///
/// Renders title + body text centred on screen, with a stroked outline
/// (movie-subtitle style) so it remains legible against any background.
/// Wrapped in [IgnorePointer] so it never intercepts input. Intended to
/// be placed in a [Positioned.fill] + [Center] by the caller.
class AutopilotDialog extends StatelessWidget {
  const AutopilotDialog({
    super.key,
    this.title,
    required this.text,
    this.textColor = const Color(0xFF90EE90),
    this.fillColor = Colors.transparent,
    this.borderColor = Colors.black,
  });

  /// Optional title shown above the body text. When null or empty only
  /// the body text is displayed.
  final String? title;

  /// Body text. `\n` escapes are already converted to real newlines by
  /// the scenario parser.
  final String text;

  /// Colour of the filled text content.
  final Color textColor;

  /// Background colour of the subtitle container (transparent by default).
  final Color fillColor;

  /// Colour of the thin outline stroke around each glyph.
  final Color borderColor;

  static const double _borderWidth = 6.0;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        decoration: BoxDecoration(
          color: fillColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null && title!.isNotEmpty) ...[
              _StrokedText(
                text: title!,
                textColor: textColor,
                borderColor: borderColor,
                fontSize: 72,
                fontWeight: FontWeight.bold,
              ),
              const SizedBox(height: 16),
            ],
            _StrokedText(
              text: text,
              textColor: textColor,
              borderColor: borderColor,
              fontSize: 64,
              fontWeight: FontWeight.normal,
            ),
          ],
        ),
      ),
    );
  }
}

/// A [Text] widget rendered with a coloured outline stroke so the glyphs
/// are legible against any background — the same technique used for movie
/// subtitles.
class _StrokedText extends StatelessWidget {
  const _StrokedText({
    required this.text,
    required this.textColor,
    required this.borderColor,
    required this.fontSize,
    required this.fontWeight,
  });

  final String text;
  final Color textColor;
  final Color borderColor;
  final double fontSize;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      decoration: TextDecoration.none,
    );
    return Stack(
      children: [
        // Outline / stroke layer (rendered first so it sits behind the fill).
        Text(
          text,
          textAlign: TextAlign.center,
          style: baseStyle.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = AutopilotDialog._borderWidth
              ..color = borderColor,
          ),
        ),
        // Filled text layer.
        Text(
          text,
          textAlign: TextAlign.center,
          style: baseStyle.copyWith(color: textColor),
        ),
      ],
    );
  }
}
