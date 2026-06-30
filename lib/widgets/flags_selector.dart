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
  Widget _buildChip((String, String) entry, int index) {
    return ActionChip(
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
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.choices;
    return Wrap(
      alignment: WrapAlignment.center,
      runSpacing: 4,
      children: [
        for (int i = 0; i < entries.length; i++) _buildChip(entries[i], i),
      ],
    );
  }
}
