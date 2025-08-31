import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_md/flutter_md.dart';

class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  Markdown helpEn = Markdown.empty();
  Markdown helpFr = Markdown.empty();
  String locale = "en";

  @override
  void initState() {
    super.initState();
    loadTexts();
  }

  Future<void> loadTexts() async {
    final textEn = await rootBundle.loadString('assets/help.en.md');
    final textFr = await rootBundle.loadString('assets/help.fr.md');
    final markdownEn = Markdown.fromString(textEn);
    final markdownFr = Markdown.fromString(textFr);
    setState(() {
      helpEn = markdownEn;
      helpFr = markdownFr;
    });
  }

  void handleButtonClick() {
    setState(() {
      locale = (locale == "en") ? "fr" : "en";
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
              constraints: BoxConstraints(minHeight: viewportConstraints.maxHeight),
              child: Container(
                margin: EdgeInsets.all(8),
                child: Column(
                  children: [
                    TextButton.icon(
                      onPressed: handleButtonClick,
                      label: Text("Change language"),
                      icon: Icon(Icons.language),
                    ),
                    MarkdownTheme(
                      data: MarkdownThemeData(
                        textStyle: TextStyle(
                          fontSize: 16.0,
                          color: Colors.black87,
                        ),
                        h1Style: TextStyle(
                          fontSize: 24.0,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                        h2Style: TextStyle(
                          fontSize: 22.0,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey,
                        ),
                        quoteStyle: TextStyle(
                          fontSize: 14.0,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey[600],
                        ),
                      ),
                      child: MarkdownWidget(
                        markdown: (locale == "en" ? helpEn : helpFr),
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
