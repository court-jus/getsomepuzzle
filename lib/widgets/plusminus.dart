import 'dart:ui' as ui;

import 'package:flutter/material.dart';

double _textWidth(String text, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: ui.TextDirection.ltr,
  )..layout();
  return tp.width;
}

class PlusMinusField extends StatefulWidget {
  const PlusMinusField({
    super.key,
    required this.onChanged,
    required this.initialMin,
    required this.initialMax,
    this.minimum = 2,
    this.maximum = 10,
    this.increment = 1,
    this.showReset = false,
  });
  final Function(int minValue, int maxValue) onChanged;
  final int initialMin;
  final int initialMax;
  final int minimum;
  final int maximum;
  final int increment;
  final bool showReset;

  @override
  State<PlusMinusField> createState() => _PlusMinusFieldState();
}

class _PlusMinusFieldState extends State<PlusMinusField> {
  late int minValue;
  late int maxValue;

  @override
  void initState() {
    minValue = widget.initialMin;
    maxValue = widget.initialMax;
    super.initState();
  }

  void _increment(bool minOrMax, bool incr) {
    setState(() {
      if (minOrMax) {
        // Change min value
        if (incr && minValue < (widget.maximum - widget.increment)) {
          // Raise min value
          minValue += widget.increment;
          if (minValue == maxValue) maxValue += widget.increment;
        } else if (!incr && minValue > widget.minimum) {
          // Lower min value
          minValue -= widget.increment;
        }
      } else {
        // Change max value
        if (incr && maxValue < widget.maximum) {
          maxValue += widget.increment;
        } else if (!incr && maxValue > (widget.minimum + widget.increment)) {
          maxValue -= widget.increment;
          if (minValue == maxValue) minValue -= widget.increment;
        }
      }
      if (widget.increment != 1) {
        minValue = (minValue / widget.increment).floor() * widget.increment;
        maxValue = (maxValue / widget.increment).floor() * widget.increment;
      }
      if (minValue < widget.minimum) minValue = widget.minimum;
      if (maxValue > widget.maximum) maxValue = widget.maximum;
      widget.onChanged(minValue, maxValue);
    });
  }

  void _reset() {
    setState(() {
      minValue = widget.minimum;
      maxValue = widget.maximum;
      widget.onChanged(minValue, maxValue);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDefault = minValue == widget.minimum && maxValue == widget.maximum;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Focus(
          descendantsAreFocusable: false,
          canRequestFocus: false,
          child: IconButton(
            icon: Icon(Icons.remove),
            onPressed: () => _increment(true, false),
          ),
        ),
        Focus(
          descendantsAreFocusable: false,
          canRequestFocus: false,
          child: IconButton(
            icon: Icon(Icons.add),
            onPressed: () => _increment(true, true),
          ),
        ),
        SizedBox(
          width:
              _textWidth('100 ⇔ 100', DefaultTextStyle.of(context).style) + 8,
          child: Text("$minValue ⇔ $maxValue", textAlign: TextAlign.center),
        ),
        Focus(
          descendantsAreFocusable: false,
          canRequestFocus: false,
          child: IconButton(
            icon: Icon(Icons.remove),
            onPressed: () => _increment(false, false),
          ),
        ),
        Focus(
          descendantsAreFocusable: false,
          canRequestFocus: false,
          child: IconButton(
            icon: Icon(Icons.add),
            onPressed: () => _increment(false, true),
          ),
        ),
        if (widget.showReset)
          Focus(
            descendantsAreFocusable: false,
            canRequestFocus: false,
            child: IconButton(
              icon: Icon(
                Icons.restart_alt,
                color: isDefault ? Colors.grey : Colors.blue,
              ),
              onPressed: isDefault ? null : _reset,
            ),
          ),
      ],
    );
  }
}
