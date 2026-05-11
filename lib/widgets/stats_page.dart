import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/utils/share_outcome.dart';
import 'package:getsomepuzzle/utils/share_stub.dart'
    if (dart.library.html) 'package:getsomepuzzle/utils/share_html.dart'
    if (dart.library.io) 'package:getsomepuzzle/utils/share_io.dart';

enum _StatsScope { current, all }

class StatsPage extends StatefulWidget {
  const StatsPage({super.key, required this.database});

  final Database database;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  _StatsScope scope = _StatsScope.all;
  List<String> stats = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => loading = true);
    final next = scope == _StatsScope.current
        ? widget.database.getStats()
        : await widget.database.getAllStats();
    if (!mounted) return;
    setState(() {
      stats = next;
      loading = false;
    });
  }

  Future<void> setData() async {
    final content = stats.join("\n");
    final outcome = await shareData(content);
    if (!mounted) return;
    if (outcome == ShareOutcome.clipboard) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.statsCopiedToClipboard),
        ),
      );
    }
  }

  Future<void> _importData() async {
    // withData=true so the same code path works on every platform: on web
    // file_picker only populates `bytes`, on native it populates both.
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    String? content;
    if (picked.bytes != null) {
      content = utf8.decode(picked.bytes!, allowMalformed: true);
    } else if (picked.path != null) {
      content = await File(picked.path!).readAsString();
    }
    if (content == null) return;
    final added = await widget.database.importStats(content);
    if (!mounted) return;
    final loc = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added == 0
              ? loc.statsImportNothingValid
              : loc.statsImportSuccess(added),
        ),
      ),
    );
    if (added > 0) {
      await _loadStats();
    }
  }

  void _onScopeChanged(_StatsScope next) {
    if (next == scope) return;
    scope = next;
    _loadStats();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktopFile = !kIsWeb && (Platform.isWindows || Platform.isLinux);
    final shareText = isDesktopFile
        ? AppLocalizations.of(context)!.open
        : AppLocalizations.of(context)!.btnShareStats;
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
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SegmentedButton<_StatsScope>(
                      segments: [
                        ButtonSegment(
                          value: _StatsScope.current,
                          label: Text(
                            AppLocalizations.of(context)!.statsScopeCurrent,
                          ),
                        ),
                        ButtonSegment(
                          value: _StatsScope.all,
                          label: Text(
                            AppLocalizations.of(context)!.statsScopeAll,
                          ),
                        ),
                      ],
                      selected: {scope},
                      onSelectionChanged: (s) => _onScopeChanged(s.first),
                    ),
                  ),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: loading || stats.isEmpty ? null : setData,
                        label: Text(shareText),
                        icon: const Icon(Icons.copy),
                      ),
                      TextButton.icon(
                        onPressed: loading ? null : _importData,
                        label: Text(
                          AppLocalizations.of(context)!.btnImportStats,
                        ),
                        icon: const Icon(Icons.file_upload),
                      ),
                    ],
                  ),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    )
                  else
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
