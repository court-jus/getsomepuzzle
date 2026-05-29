import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constants.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/base_line_constraint.dart';

class TransitionWidget extends StatelessWidget {
  const TransitionWidget({
    super.key,
    required this.constraint,
    required this.cellSize,
    required this.axis,
  });

  final LineCentricConstraint constraint;
  final double cellSize;

  /// Orientation of the constrained line: [Axis.horizontal] for a row (RT),
  /// [Axis.vertical] for a column (CT). Drives the wave direction.
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final bool shouldGrayOut = constraint.isComplete;
    final borderColor = shouldGrayOut
        ? Colors.grey
        : (constraint.isHighlighted
              ? highlightColor
              : (constraint.isValid ? Colors.grey : Colors.redAccent));
    final waveColor = shouldGrayOut ? Colors.grey : Colors.black;
    final squareSize = cellSize * 0.7;

    return SizedBox(
      width: squareSize,
      height: cellSize,
      child: Center(
        child: Container(
          width: squareSize,
          height: squareSize,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: borderColor, width: 2),
          ),
          child: CustomPaint(
            painter: _SquareWavePainter(
              count: constraint.count,
              axis: axis,
              color: waveColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws a "square wave" glyph whose number of vertical edges equals the
/// transition count, with the count digit large and centred on top. The
/// metaphor — a digital signal that toggles N times — makes explicit that
/// RT/CT count *color changes* between adjacent cells, not cells of one colour.
///
/// The wave fills the whole square as a backdrop; the digit is laid over it.
/// Both the wave and the digit are outlined (a wide halo stroke under a
/// narrower core stroke), mirroring the dual-layer rendering of [EyesWidget]:
/// the halo carves the wave away from the digit so the number stays readable
/// even where the two overlap.
///
/// `count == 0` collapses the wave to a flat segment (monochrome line, no
/// change); `count == lineLength - 1` produces a tight alternation
/// (checkerboard).
class _SquareWavePainter extends CustomPainter {
  // Snapshots: the constraint object is mutated in place across builds, so
  // these are captured at construction to make `shouldRepaint` meaningful.
  final int count;
  final Axis axis;
  final Color color;

  // Contrast halo drawn under both the wave and the digit so they read against
  // the grey square and against each other.
  static const Color _halo = Colors.white;

  _SquareWavePainter({
    required this.count,
    required this.axis,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final m = size.shortestSide * 0.14;
    final inner = Rect.fromLTRB(m, m, size.width - m, size.height - m);
    final path = _buildWave(inner);

    // Wave: a wide halo stroke first, then the coloured core on top, giving the
    // line a visible border.
    final coreW = (size.shortestSide * 0.05).clamp(1.2, 2.2);
    final haloW = coreW + (size.shortestSide * 0.045).clamp(1.2, 2.2);
    canvas.drawPath(
      path,
      Paint()
        ..color = _halo
        ..style = PaintingStyle.stroke
        ..strokeWidth = haloW
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = coreW
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Digit: large, centred, outlined (halo stroke + coloured fill on top) so
    // it stays legible over the wave behind it.
    final fontSize = size.shortestSide * 0.66;
    final outlineWidth = (size.shortestSide * 0.09).clamp(2.0, 4.0);
    final strokePainter = TextPainter(
      text: TextSpan(
        text: count.toString(),
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = outlineWidth
            ..strokeJoin = StrokeJoin.round
            ..color = _halo,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    final fillPainter = TextPainter(
      text: TextSpan(
        text: count.toString(),
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    strokePainter.layout();
    fillPainter.layout();
    final offset = Offset(
      (size.width - fillPainter.width) / 2,
      (size.height - fillPainter.height) / 2,
    );
    strokePainter.paint(canvas, offset);
    fillPainter.paint(canvas, offset);
  }

  /// Builds the wave path inside [r]. For [Axis.horizontal] plateaus run along
  /// x and edges are vertical; for [Axis.vertical] axes are swapped. The wave
  /// swings around the centre with a moderate amplitude (rather than the full
  /// span) so its edges stay short and don't run through the overlaid digit.
  Path _buildWave(Rect r) {
    final path = Path();

    if (axis == Axis.horizontal) {
      final amp = r.height * 0.28;
      final lo = r.center.dy + amp;
      final hi = r.center.dy - amp;
      if (count == 0) {
        // Flat line through the centre = "no transition".
        path.moveTo(r.left, r.center.dy);
        path.lineTo(r.right, r.center.dy);
        return path;
      }
      final seg = r.width / (count + 1);
      double cur = lo; // start on the low level
      path.moveTo(r.left, cur);
      for (int i = 0; i <= count; i++) {
        final xEnd = r.left + (i + 1) * seg;
        path.lineTo(xEnd, cur); // plateau
        if (i < count) {
          cur = (cur == lo) ? hi : lo;
          path.lineTo(xEnd, cur); // vertical edge = one transition
        }
      }
    } else {
      final amp = r.width * 0.28;
      final lo = r.center.dx + amp;
      final hi = r.center.dx - amp;
      if (count == 0) {
        path.moveTo(r.center.dx, r.top);
        path.lineTo(r.center.dx, r.bottom);
        return path;
      }
      final seg = r.height / (count + 1);
      double cur = lo;
      path.moveTo(cur, r.top);
      for (int i = 0; i <= count; i++) {
        final yEnd = r.top + (i + 1) * seg;
        path.lineTo(cur, yEnd); // plateau
        if (i < count) {
          cur = (cur == lo) ? hi : lo;
          path.lineTo(cur, yEnd); // horizontal edge = one transition
        }
      }
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _SquareWavePainter old) =>
      old.count != count || old.axis != axis || old.color != color;
}
