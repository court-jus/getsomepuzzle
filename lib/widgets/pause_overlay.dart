import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/app_theme.dart';

/// Full-screen overlay shown when the game is paused.
///
/// With only [onResume] it is a single teal button (tap anywhere to resume).
/// When [onRestart] is non-null it splits the area into two halves — a teal
/// "resume" half (identical look to the pause-only case) and a red "restart"
/// half — used as a restart confirmation step. The split is horizontal on
/// landscape ([width] > [height]) and vertical otherwise.
class PauseOverlay extends StatelessWidget {
  const PauseOverlay({
    super.key,
    required this.onResume,
    required this.width,
    required this.height,
    required this.iconSize,
    this.subtitle,
    this.onRestart,
    this.restartLabel,
  });

  final VoidCallback onResume;
  final double width;
  final double height;
  final double iconSize;

  /// Optional explanation of why the game is paused (idle, focus lost).
  /// Rendered below the pause icon when non-null.
  final String? subtitle;

  /// When non-null, a second red "restart" button is shown next to the resume
  /// button to confirm a restart. When null, the overlay is resume-only.
  final VoidCallback? onRestart;

  /// Text label of the red restart button (shown next to its icon).
  final String? restartLabel;

  @override
  Widget build(BuildContext context) {
    final pc = Theme.of(context).extension<PuzzleColors>()!;
    if (onRestart == null) {
      // Resume-only: a single full-size button (the historical pause overlay).
      return _button(
        context: context,
        color: pc.pauseOverlayBg,
        icon: Icons.pause,
        iconSize: iconSize,
        onPressed: onResume,
        width: width,
        height: height,
        subtitle: subtitle,
      );
    }

    // Two halves: resume + restart confirmation. Smaller icons leave room for
    // the restart label and for both buttons to fit side by side.
    // Gap between the two halves; subtracted from the split dimension so the
    // buttons plus the gap still sum to exactly the available size.
    const double gap = 8;
    final bool horizontal = width > height;
    final double halfWidth = horizontal ? (width - gap) / 2 : width;
    final double halfHeight = horizontal ? height : (height - gap) / 2;
    final double splitIconSize = iconSize * 0.6;

    final resume = _button(
      context: context,
      color: pc.pauseOverlayBg,
      icon: Icons.pause,
      iconSize: splitIconSize,
      onPressed: onResume,
      width: halfWidth,
      height: halfHeight,
      subtitle: subtitle,
      compact: true,
    );
    final restart = _button(
      context: context,
      color: Colors.redAccent.shade100,
      icon: Icons.restart_alt_outlined,
      iconSize: splitIconSize,
      onPressed: onRestart!,
      width: halfWidth,
      height: halfHeight,
      label: restartLabel,
      compact: true,
    );

    return horizontal
        ? Row(
            mainAxisSize: MainAxisSize.min,
            spacing: gap,
            children: [resume, restart],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            spacing: gap,
            children: [resume, restart],
          );
  }

  /// One overlay button: a coloured rounded box of [width] x [height] with a
  /// centred [icon] and optional [label]/[subtitle], wrapped in a [TextButton].
  Widget _button({
    required BuildContext context,
    required Color color,
    required IconData icon,
    required double iconSize,
    required VoidCallback onPressed,
    required double width,
    required double height,
    String? label,
    String? subtitle,
    bool compact = false,
  }) {
    return TextButton(
      onPressed: onPressed,
      // In the split layout the two halves must sum to exactly the available
      // size: strip the default button padding so they don't overflow.
      style: compact
          ? TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            )
          : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(15),
        ),
        child: SizedBox(
          width: width,
          height: height,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: iconSize),
                if (label != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
                if (subtitle != null) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
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
