import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

class FlagsSelector extends StatelessWidget {
  final Set<String> wanted;
  final Set<String> banned;
  final List<(String, String)> choices;
  final ValueChanged<(Set<String>, Set<String>)> apply;

  const FlagsSelector({
    super.key,
    required this.choices,
    required this.wanted,
    required this.banned,
    required this.apply,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final rulesRow in choices.slices(5))
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: rulesRow
                .map(
                  (slug) => ActionChip(
                    avatar: Icon(
                      wanted.contains(slug.$1)
                          ? Icons.check
                          : banned.contains(slug.$1)
                          ? Icons.cancel
                          : Icons.question_mark,
                    ),
                    label: Text(slug.$2),
                    backgroundColor: wanted.contains(slug.$1)
                        ? Colors.green[200]
                        : banned.contains(slug.$1)
                        ? Colors.red[200]
                        : Colors.transparent,
                    onPressed: () {
                      if (wanted.contains(slug.$1)) {
                        apply((
                          wanted.difference({slug.$1}),
                          banned.union({slug.$1}),
                        ));
                      } else if (banned.contains(slug.$1)) {
                        apply((
                          wanted.difference({slug.$1}),
                          banned.difference({slug.$1}),
                        ));
                      } else {
                        apply((
                          wanted.union({slug.$1}),
                          banned.difference({slug.$1}),
                        ));
                      }
                    },
                  ),
                )
                .toList(),
          ),
      ],
    );
  }
}
