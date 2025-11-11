import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_md/flutter_md.dart';
import 'package:getsomepuzzle/getsomepuzzle/constants.dart';

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
      appBar: AppBar(title: Text('Help')),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints viewportConstraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: viewportConstraints.maxHeight,
              ),
              child: Container(
                margin: EdgeInsets.all(8),
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
