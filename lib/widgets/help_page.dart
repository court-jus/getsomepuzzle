import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_md/flutter_md.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constants.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/constraints/registry.dart';
import 'package:url_launcher/url_launcher.dart';

/// Public URL where the privacy-policy HTML pages are hosted (one per
/// locale). The pages are generated at build-time from
/// `assets/privacy.{en,fr,es}.md` by `bin/build_privacy.dart`, copied
/// into `build/web/` by `flutter build web`, and deployed to gh-pages.
const _privacyBaseUrl = 'https://court-jus.github.io/getsomepuzzle';

class HelpPage extends StatefulWidget {
  const HelpPage({super.key, required this.locale});
  final String locale;

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  String helpEn = '';
  String helpFr = '';
  String helpEs = '';

  @override
  void initState() {
    super.initState();
    loadTexts();
  }

  Future<void> loadTexts() async {
    final textEn = await rootBundle.loadString('assets/help.en.md');
    final textFr = await rootBundle.loadString('assets/help.fr.md');
    final textEs = await rootBundle.loadString('assets/help.es.md');
    setState(() {
      helpEn = textEn;
      helpFr = textFr;
      helpEs = textEs;
    });
  }

  String get _rawMarkdown {
    switch (widget.locale) {
      case 'fr':
        return helpFr;
      case 'es':
        return helpEs;
      default:
        return helpEn;
    }
  }

  /// Split the localized help markdown around its "## Constraints"
  /// heading: everything up to *and including* the heading is rendered
  /// as markdown, then the constraints catalogue (Flutter widgets) is
  /// inserted, then the remainder of the document resumes as markdown.
  ///
  /// `flutter_md` cannot display images, so the per-constraint prose
  /// that used to live under that heading is now rendered by
  /// [_ConstraintCatalog] from the localised `constraintExplain*`
  /// strings instead.
  (Markdown, Markdown?) _splitAroundConstraints(String marker) {
    final raw = _rawMarkdown;
    final idx = raw.indexOf(marker);
    if (raw.isEmpty || idx < 0) {
      // Not loaded yet, or the heading text drifted from the localised
      // string: render everything as-is and append the catalogue at the
      // end.
      return (raw.isEmpty ? Markdown.empty() : Markdown.fromString(raw), null);
    }
    final prefixEnd = idx + marker.length;
    final prefix = Markdown.fromString('${raw.substring(0, prefixEnd)}\n');
    final suffixRaw = raw
        .substring(prefixEnd)
        .replaceFirst(RegExp(r'^\r?\n\r?\n'), '');
    final suffix = suffixRaw.trim().isEmpty
        ? null
        : Markdown.fromString(suffixRaw);
    return (prefix, suffix);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final (prefix, suffix) = _splitAroundConstraints('## ${l.helpConstraints}');
    return Scaffold(
      appBar: AppBar(title: Text(l.help)),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints viewportConstraints) {
            return SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: viewportConstraints.maxHeight,
                ),
                child: Container(
                  margin: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MarkdownTheme(
                        data: mdTheme,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MarkdownWidget(markdown: prefix),
                            const SizedBox(height: 16),
                            const _ConstraintCatalog(),
                            if (suffix != null) ...[
                              const SizedBox(height: 16),
                              MarkdownWidget(markdown: suffix),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton.icon(
                        icon: const Icon(Icons.privacy_tip_outlined),
                        label: Text(
                          AppLocalizations.of(context)!.viewPrivacyPolicy,
                        ),
                        onPressed: () {
                          final url = Uri.parse(
                            '$_privacyBaseUrl/privacy.${widget.locale}.html',
                          );
                          launchUrl(url, mode: LaunchMode.externalApplication);
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The "## Constraints" section of the help page, rendered as widgets.
///
/// Lists every constraint in teaching order ([constraintCatalogueSlugs]:
/// onboarding phase introducers first, then the rest in registry order),
/// one row per concept. Orientation pairs that share an explanation
/// (row/column variants) are collapsed into a single row. Each row
/// shows the icon (the same previews as the in-editor constraint-type
/// picker), the localised name and the explanation — the very strings
/// the onboarding dialogs use, so the help page and the dialogs stay in
/// sync.
class _ConstraintCatalog extends StatelessWidget {
  const _ConstraintCatalog();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, slug) in constraintCatalogueSlugs.indexed) ...[
          if (i > 0) const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstraintIcon(slug: slug, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _capitalise(constraintNameForSlug(l, slug)),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(constraintExplanationForSlug(l, slug)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

String _capitalise(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
