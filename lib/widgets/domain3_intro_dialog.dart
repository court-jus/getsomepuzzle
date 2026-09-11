import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/app_theme.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/cell.dart';

/// One-shot modal explaining the 3-colour play surface, shown the first
/// time the player opens a domain-3 puzzle. Two sections, each with a
/// live sample of the real widget it explains:
///
/// - the [OptionDots] row drawn at the bottom of every empty cell;
/// - the paintbrush toolbar button that toggles the "remove option"
///   interaction mode.
///
/// Styled like [NewConstraintDialog] — accent icon + title header,
/// scrollable body, single OK action — so the two first-contact
/// explanations read as one family. The caller owns the "already shown"
/// side effect ([Database.noteDomain3IntroShown]) and the gating
/// ([Database.shouldShowDomain3Intro]).
class Domain3IntroDialog extends StatelessWidget {
  const Domain3IntroDialog({super.key});

  /// Show the modal. Completes once the player dismissed it.
  static Future<void> show(BuildContext context) async {
    await showDialog<void>(
      context: context,
      // Mandatory tap on a button — same rationale as
      // NewConstraintDialog: a stray tap outside would dismiss the only
      // in-app explanation of the 3-colour UI without the player reading
      // it.
      barrierDismissible: false,
      builder: (_) => const Domain3IntroDialog(),
    );
  }

  /// Width of the leading sample column. Both sections reserve the same
  /// width so the dots sample and the paintbrush icon line up, and the
  /// explanation text starts at the same x on both rows.
  static const double _leadingWidth = 88;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final pc = Theme.of(context).extension<PuzzleColors>()!;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.palette, color: pc.dialogAccent),
          const SizedBox(width: 8),
          Expanded(child: Text(l.domain3IntroTitle)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.domain3IntroBody),
            const SizedBox(height: 16),
            _Section(
              // Sample of the real dots row, rendered from the canonical
              // 3-colour domain so it shows one dot per possible colour.
              leading: OptionDots(options: fullDomain, cellSize: 80),
              title: l.domain3IntroDotsTitle,
              body: l.domain3IntroDotsBody,
            ),
            const SizedBox(height: 16),
            _Section(
              leading: Icon(
                Icons.format_paint,
                size: 36,
                color: pc.dialogAccent,
              ),
              title: l.domain3IntroPaintbrushTitle,
              body: l.domain3IntroPaintbrushBody,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}

/// Leading sample + header + explanation, mirroring one
/// `ConstraintExplanationList` section so the two first-contact modals
/// share the same visual rhythm.
class _Section extends StatelessWidget {
  const _Section({
    required this.leading,
    required this.title,
    required this.body,
  });

  final Widget leading;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: Domain3IntroDialog._leadingWidth,
          child: Center(child: leading),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(body),
            ],
          ),
        ),
      ],
    );
  }
}
