import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_md/flutter_md.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constants.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
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
  Markdown helpEn = Markdown.empty();
  Markdown helpFr = Markdown.empty();
  Markdown helpEs = Markdown.empty();

  @override
  void initState() {
    super.initState();
    loadTexts();
  }

  Future<void> loadTexts() async {
    final textEn = await rootBundle.loadString('assets/help.en.md');
    final textFr = await rootBundle.loadString('assets/help.fr.md');
    final textEs = await rootBundle.loadString('assets/help.es.md');
    final markdownEn = Markdown.fromString(textEn);
    final markdownFr = Markdown.fromString(textFr);
    final markdownEs = Markdown.fromString(textEs);
    setState(() {
      helpEn = markdownEn;
      helpFr = markdownFr;
      helpEs = markdownEs;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.help)),
      body: LayoutBuilder(
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
                  children: [
                    MarkdownTheme(
                      data: mdTheme,
                      child: MarkdownWidget(
                        markdown: (widget.locale == "fr"
                            ? helpFr
                            : (widget.locale == "es" ? helpEs : helpEn)),
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
    );
  }
}
