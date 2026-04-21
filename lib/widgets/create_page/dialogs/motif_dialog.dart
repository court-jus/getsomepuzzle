import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/shape.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constants.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';

/// Generic 3x3 motif editor — shared by Forbidden Motif and Shape.
/// Returns the motif string (rows joined by '.') or null on cancel.
Future<String?> _showMotifDialog(
  BuildContext context, {
  required String titleText,
  required Color backgroundColor,
}) {
  int motifWidth = 2;
  int motifHeight = 2;
  final grid = List.generate(3, (_) => List.filled(3, 0));
  final bgColors = {0: backgroundColor, 1: Colors.black, 2: Colors.white};

  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final loc = AppLocalizations.of(context)!;
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text(titleText),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text('${loc.createMotifWidth}: '),
                      DropdownButton<int>(
                        value: motifWidth,
                        items: [1, 2, 3]
                            .map(
                              (v) =>
                                  DropdownMenuItem(value: v, child: Text('$v')),
                            )
                            .toList(),
                        onChanged: (v) {
                          setDialogState(() => motifWidth = v!);
                        },
                      ),
                      const SizedBox(width: 16),
                      Text('${loc.createMotifHeight}: '),
                      DropdownButton<int>(
                        value: motifHeight,
                        items: [1, 2, 3]
                            .map(
                              (v) =>
                                  DropdownMenuItem(value: v, child: Text('$v')),
                            )
                            .toList(),
                        onChanged: (v) {
                          setDialogState(() => motifHeight = v!);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Table(
                    defaultColumnWidth: const FixedColumnWidth(50),
                    children: [
                      for (var row = 0; row < motifHeight; row++)
                        TableRow(
                          children: [
                            for (var col = 0; col < motifWidth; col++)
                              GestureDetector(
                                onTap: () {
                                  setDialogState(() {
                                    grid[row][col] = (grid[row][col] + 1) % 3;
                                  });
                                },
                                child: Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: bgColors[grid[row][col]],
                                    border: Border.all(color: Colors.blueGrey),
                                  ),
                                ),
                              ),
                            for (var col = motifWidth; col < 3; col++)
                              const SizedBox(width: 50, height: 50),
                          ],
                        ),
                      for (var row = motifHeight; row < 3; row++)
                        TableRow(
                          children: List.generate(
                            3,
                            (_) => const SizedBox(width: 50, height: 50),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
              ),
              TextButton(
                onPressed: () {
                  final motifRows = <String>[];
                  bool hasNonZero = false;
                  for (var row = 0; row < motifHeight; row++) {
                    final rowStr = grid[row]
                        .sublist(0, motifWidth)
                        .map((v) => v.toString())
                        .join('');
                    motifRows.add(rowStr);
                    if (rowStr.contains(RegExp('[12]'))) hasNonZero = true;
                  }
                  if (!hasNonZero) return;
                  Navigator.pop(ctx, motifRows.join('.'));
                },
                child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<ForbiddenMotif?> showForbiddenMotifDialog(BuildContext context) async {
  final loc = AppLocalizations.of(context)!;
  final motifStr = await _showMotifDialog(
    context,
    titleText: loc.constraintForbiddenPattern,
    backgroundColor: forbiddenColor,
  );
  return motifStr == null ? null : ForbiddenMotif(motifStr);
}

Future<ShapeConstraint?> showShapeDialog(BuildContext context) async {
  final loc = AppLocalizations.of(context)!;
  final motifStr = await _showMotifDialog(
    context,
    titleText: loc.constraintShape,
    backgroundColor: mandatoryColor,
  );
  return motifStr == null ? null : ShapeConstraint(motifStr);
}
