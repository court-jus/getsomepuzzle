import 'dart:io' show Directory, File, FileMode, Platform;

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Platform-aware file I/O that transparently uses Android's SAF
/// [DocumentsContract] API for `content://` URIs (returned by
/// [FilePicker.getDirectoryPath] on Android 11+) and falls back to
/// [dart:io] for regular filesystem paths (iOS, desktop, Android pre-11).
///
/// Without this bridge, [Directory] and [File] throw or silently
/// return empty results when passed a SAF content URI, which is what
/// makes the user-chosen stats-sync directory invisible on modern Android.
class SafAccess {
  SafAccess._();

  static const _channel = MethodChannel('getsomepuzzle/saf');

  static bool _isContentUri(String path) => path.startsWith('content://');

  /// File names (basenames only) inside [dirPath] whose name starts
  /// with [prefix].
  static Future<List<String>> listFileNames(
    String dirPath,
    String prefix,
  ) async {
    if (Platform.isAndroid && _isContentUri(dirPath)) {
      final result = await _channel.invokeListMethod<String>('listFiles', {
        'uri': dirPath,
        'prefix': prefix,
      });
      return result ?? [];
    }
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .map((f) => p.basename(f.path))
        .where((name) => name.startsWith(prefix))
        .toList();
  }

  /// Read the full text content of [fileName] inside [dirPath].
  static Future<String> readFile(String dirPath, String fileName) async {
    if (Platform.isAndroid && _isContentUri(dirPath)) {
      final result = await _channel.invokeMethod<String>('readFile', {
        'uri': dirPath,
        'fileName': fileName,
      });
      return result ?? '';
    }
    return File(p.join(dirPath, fileName)).readAsString();
  }

  /// Write [content] to [fileName] inside [dirPath], creating the
  /// directory if needed (regular paths only — SAF directories are
  /// created by the picker).
  static Future<void> writeFile(
    String dirPath,
    String fileName,
    String content,
  ) async {
    if (Platform.isAndroid && _isContentUri(dirPath)) {
      await _channel.invokeMethod<void>('writeFile', {
        'uri': dirPath,
        'fileName': fileName,
        'content': content,
      });
      return;
    }
    final dir = Directory(dirPath);
    await dir.create(recursive: true);
    File(
      p.join(dirPath, fileName),
    ).writeAsStringSync(content, mode: FileMode.writeOnly, flush: true);
  }

  /// Delete every file inside [dirPath] whose name starts with [prefix].
  static Future<void> deleteFiles(String dirPath, String prefix) async {
    if (Platform.isAndroid && _isContentUri(dirPath)) {
      await _channel.invokeMethod<void>('deleteFiles', {
        'uri': dirPath,
        'prefix': prefix,
      });
      return;
    }
    final dir = Directory(dirPath);
    if (!await dir.exists()) return;
    for (final entry in dir.listSync()) {
      if (entry is File && p.basename(entry.path).startsWith(prefix)) {
        entry.deleteSync();
      }
    }
  }
}
