import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/constraints/registry.dart';
import 'package:getsomepuzzle/widgets/create_page/shared/color_dot_picker.dart';

// Preview widgets inside the picker render at the same size as a small grid
// cell so players see the actual constraint glyph they will encounter on the
// board, rather than a generic Material icon that doesn't visually match.
const _previewSize = 44.0;

Future<String?> showConstraintTypePicker(
  BuildContext context, {
  List<CellValue> domain = defaultDomain,
  Set<String> disabledSlugs = const {},
}) {
  final loc = AppLocalizations.of(context)!;
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final fgcolor =
          IconTheme.of(ctx).color ?? Theme.of(ctx).colorScheme.onSurface;
      return AlertDialog(
        title: Text(loc.createChooseType),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // `Wrap` avoids the viewport-intrinsic-dimensions crash that
              // `GridView` triggers inside an `AlertDialog`. It's wrapped in a
              // Flexible+SingleChildScrollView so the tiles scroll on short
              // viewports while the fixBlack/fixWhite row stays pinned below.
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in constraintRegistry)
                        SizedBox(
                          width: 148,
                          height: 104,
                          child: _TypeTile(
                            preview: previewForSlug(
                              entry.slug,
                              fgcolor,
                              _previewSize,
                            ),
                            label: constraintNameForSlug(loc, entry.slug),
                            enabled: !disabledSlugs.contains(entry.slug),
                            onTap: () => Navigator.pop(ctx, entry.slug),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => Navigator.pop(ctx, 'fixBlack'),
                      icon: ColorDot(value: CellValue.black, size: 20),
                      label: Text(loc.createFixBlack),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => Navigator.pop(ctx, 'fixWhite'),
                      icon: ColorDot(value: CellValue.white, size: 20),
                      label: Text(loc.createFixWhite),
                    ),
                  ),
                  if (domain.length > 2)
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () => Navigator.pop(ctx, 'fixPurple'),
                        icon: ColorDot(value: CellValue.purple, size: 20),
                        label: Text(loc.createFixPurple),
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
        ],
      );
    },
  );
}

class _TypeTile extends StatelessWidget {
  final Widget preview;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  const _TypeTile({
    required this.preview,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.35,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: _previewSize + 4,
                child: Center(child: preview),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
