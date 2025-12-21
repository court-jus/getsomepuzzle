import 'dart:convert';
import 'dart:io';

import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> shareData(String content, String filename) async {
  final xFile = XFile.fromData(utf8.encode(content), mimeType: "text/plain");
  if (Platform.isWindows) {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = p.join(documentsDirectory.path, "getsomepuzzle");
    await Directory(path).create(recursive: true);
    final filePath = p.join(path, "stats.txt");
    await OpenFile.open(filePath, type: "text/plain");
  } else {
    final params = ShareParams(files: [xFile], fileNameOverrides: [filename]);
    SharePlus.instance.share(params);
  }
}
