import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:getsomepuzzle/utils/share_outcome.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

String _two(int v) => v.toString().padLeft(2, '0');

String _datePart(DateTime now) =>
    '${now.year}${_two(now.month)}${_two(now.day)}';

String _dateTimePart(DateTime now) =>
    '${_datePart(now)}${_two(now.hour)}${_two(now.minute)}';

String _buildStatsFilename(String dir) {
  final now = DateTime.now();
  final base = 'stats_${_datePart(now)}.txt';
  if (File(p.join(dir, base)).existsSync()) {
    return 'stats_${_dateTimePart(now)}.txt';
  }
  return base;
}

Future<ShareOutcome> _fallbackToClipboard(String content) async {
  await Clipboard.setData(ClipboardData(text: content));
  return ShareOutcome.clipboard;
}

Future<ShareOutcome> shareData(String content) async {
  if (Platform.isWindows || Platform.isLinux) {
    try {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final dir = p.join(documentsDirectory.path, "getsomepuzzle");
      await Directory(dir).create(recursive: true);
      final filename = _buildStatsFilename(dir);
      final filePath = p.join(dir, filename);
      await File(filePath).writeAsString(content);
      final result = await OpenFile.open(filePath, type: "text/plain");
      if (result.type != ResultType.done) {
        return _fallbackToClipboard(content);
      }
      return ShareOutcome.opened;
    } catch (_) {
      return _fallbackToClipboard(content);
    }
  }

  final filename = 'stats_${_datePart(DateTime.now())}.txt';
  final xFile = XFile.fromData(utf8.encode(content), mimeType: "text/plain");
  final params = ShareParams(files: [xFile], fileNameOverrides: [filename]);
  await SharePlus.instance.share(params);
  return ShareOutcome.opened;
}
