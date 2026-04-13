import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/database.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/utils/share_stub.dart'
    if (dart.library.html) 'package:getsomepuzzle/utils/share_html.dart'
    if (dart.library.io) 'package:getsomepuzzle/utils/share_io.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key, required this.database});

  final Database database;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  List<String> stats = [];

  @override
  void initState() {
    super.initState();
    stats = widget.database.getStats();
  }

  Future<void> setData() async {
    final content = stats.join("\n");
    final filename = "stats.txt";
    shareData(content, filename);
  }

  @override
  Widget build(BuildContext context) {
    final shareText = kIsWeb
        ? AppLocalizations.of(context)!.btnShareStats
        : (Platform.isWindows
              ? AppLocalizations.of(context)!.open
              : AppLocalizations.of(context)!.btnShareStats);
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.stats)),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints viewportConstraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: viewportConstraints.maxHeight,
              ),
              child: Column(
                children: [
                  TextButton.icon(
                    onPressed: setData,
                    label: Text(shareText),
                    icon: Icon(Icons.copy),
                  ),
                  Container(
                    margin: const EdgeInsets.all(8),
                    child: Text(
                      stats.join("\n"),
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        fontFamily: "monospace",
                        fontFamilyFallback: ["Courier", "Courier New"],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
