import 'package:flutter/material.dart';

class FlagsSelector extends StatefulWidget {
  final Set<String> wanted;
  final Set<String> banned;
  final List<(String, String)> choices;
  final ValueChanged<(Set<String>, Set<String>)> apply;
  final Widget? Function(String key)? iconBuilder;

  const FlagsSelector({
    super.key,
    required this.choices,
    required this.wanted,
    required this.banned,
    required this.apply,
    this.iconBuilder,
  });

  @override
  State<FlagsSelector> createState() => _FlagsSelectorState();
}

class _FlagsSelectorState extends State<FlagsSelector> {
  List<GlobalKey> _chipKeys = [];
  double? _maxChipWidth;

  @override
  void initState() {
    super.initState();
    _chipKeys = List.generate(widget.choices.length, (_) => GlobalKey());
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(covariant FlagsSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.choices.length != widget.choices.length) {
      _chipKeys = List.generate(widget.choices.length, (_) => GlobalKey());
      _maxChipWidth = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }
  }

  void _measure() {
    double max = 0;
    for (final key in _chipKeys) {
      final size = key.currentContext?.size;
      if (size != null && size.width > max) max = size.width;
    }
    if (max > 0 && max != _maxChipWidth) {
      setState(() => _maxChipWidth = max);
    }
  }

  Widget _buildChip((String, String) entry, int index) {
    final chip = ActionChip(
      key: _chipKeys[index],
      avatar: widget.iconBuilder != null
          ? SizedBox(
              width: 24,
              height: 24,
              child:
                  widget.iconBuilder!(entry.$1) ??
                  Icon(
                    widget.wanted.contains(entry.$1)
                        ? Icons.check
                        : widget.banned.contains(entry.$1)
                        ? Icons.cancel
                        : Icons.question_mark,
                  ),
            )
          : Icon(
              widget.wanted.contains(entry.$1)
                  ? Icons.check
                  : widget.banned.contains(entry.$1)
                  ? Icons.cancel
                  : Icons.question_mark,
            ),
      label: Text(entry.$2),
      backgroundColor: widget.wanted.contains(entry.$1)
          ? Colors.green[200]
          : widget.banned.contains(entry.$1)
          ? Colors.red[200]
          : Colors.transparent,
      onPressed: () {
        if (widget.wanted.contains(entry.$1)) {
          widget.apply((
            widget.wanted.difference({entry.$1}),
            widget.banned.union({entry.$1}),
          ));
        } else if (widget.banned.contains(entry.$1)) {
          widget.apply((
            widget.wanted.difference({entry.$1}),
            widget.banned.difference({entry.$1}),
          ));
        } else {
          widget.apply((
            widget.wanted.union({entry.$1}),
            widget.banned.difference({entry.$1}),
          ));
        }
      },
    );

    if (_maxChipWidth == null) return chip;
    return SizedBox(width: _maxChipWidth, child: chip);
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.choices;
    return Column(
      children: [
        for (int start = 0; start < entries.length; start += 4)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int i = start; i < (start + 4).clamp(0, entries.length); i++)
                _buildChip(entries[i], i),
            ],
          ),
      ],
    );
  }
}
