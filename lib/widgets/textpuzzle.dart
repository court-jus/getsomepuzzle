import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constants.dart';

class TextpuzzleWidget extends StatefulWidget {
  const TextpuzzleWidget({
    super.key,
    required this.textName,
    required this.locale,
  });
  final String locale;
  final String textName;

  @override
  State<TextpuzzleWidget> createState() => _TextpuzzleWidgetState();
}

class _TextpuzzleWidgetState extends State<TextpuzzleWidget> {
  Markdown content = Markdown.empty();

  @override
  void initState() {
    loadText();
    super.initState();
  }

  @override
  void didUpdateWidget(TextpuzzleWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.textName != widget.textName) {
      loadText();
    }
  }

  Future<void> loadText() async {
    final markdown = await rootBundle.loadString(
      'assets/TX/${widget.locale}/${widget.textName}.md',
    );
    setState(() {
      content = Markdown.fromString(markdown);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 500),
        child: Container(
          padding: const EdgeInsets.all(8),
          child: MarkdownTheme(
            data: mdTheme,
            child: MarkdownWidget(markdown: content),
          ),
        ),
      ),
    );
  }
}

/*
*/
