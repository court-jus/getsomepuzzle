import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/app_theme.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';

String _colorName(AppLocalizations loc, CellValue value) {
  return switch (value) {
    CellValue.black => loc.colorBlack,
    CellValue.white => loc.colorWhite,
    CellValue.purple => loc.colorPurple,
    _ => '',
  };
}

class ColorDot extends StatelessWidget {
  final CellValue value;
  final double size;
  final bool selected;
  final VoidCallback? onTap;

  const ColorDot({
    super.key,
    required this.value,
    this.size = 24,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pc = Theme.of(context).extension<PuzzleColors>()!;
    final loc = AppLocalizations.of(context)!;
    final color = pc.constraintColors[value] ?? pc.constraintInvalid;
    final borderColor =
        selected ? Theme.of(context).colorScheme.primary : Colors.black54;

    return Tooltip(
      message: _colorName(loc, value),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
              color: borderColor,
              width: selected ? 2.5 : 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class ColorDotPicker extends StatelessWidget {
  final List<CellValue> domain;
  final CellValue selected;
  final ValueChanged<CellValue> onChanged;
  final double dotSize;

  const ColorDotPicker({
    super.key,
    required this.domain,
    required this.selected,
    required this.onChanged,
    this.dotSize = 28,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      children: [
        for (final v in domain)
          ColorDot(
            value: v,
            size: dotSize,
            selected: v == selected,
            onTap: () => onChanged(v),
          ),
      ],
    );
  }
}
