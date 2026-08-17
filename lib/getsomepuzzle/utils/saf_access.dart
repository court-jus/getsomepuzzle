import 'dart:io' show Directory, File, FileMode, Platform;

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

/// Platform-aware file I/O that transparently uses Android's SAF
/// [DocumentsContract] API for `content://` URIs (returned by
/// [FilePicker.getDirectoryPath] on Android 11+) and falls back to
/// [dart:io] for regular filesystem paths (iOS, desktop, Android pre-11).
///
/// Without this bridge, [Directory] and [File] throw or silently
/// return empty results when passed a SAF content URI, which is what
/// makes the user-chosen stats-sync directory invisible on modern Android.
///
/// Exceptions are logged at warning level and then rethrown — callers
/// should catch what they can handle (e.g. [Database] sets
/// [Database.statsDirectoryError] on failure so the UI can react).
class SafAccess {
  SafAccess._();

  static const _channel = MethodChannel('getsomepuzzle/saf');
  static final _log = Logger('SafAccess');

  static bool _isContentUri(String path) => path.startsWith('content://');

  /// File names (basenames only) inside [dirPath] whose name starts
  /// with [prefix].
  static Future<List<String>> listFileNames(
    String dirPath,
    String prefix,
  ) async {
    try {
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
    } on Exception catch (e) {
      _log.warning('listFileNames($dirPath, $prefix) failed: $e');
      rethrow;
    }
  }

  /// Read the full text content of [fileName] inside [dirPath].
  static Future<String> readFile(String dirPath, String fileName) async {
    try {
      if (Platform.isAndroid && _isContentUri(dirPath)) {
        final result = await _channel.invokeMethod<String>('readFile', {
          'uri': dirPath,
          'fileName': fileName,
        });
        return result ?? '';
      }
      return await File(p.join(dirPath, fileName)).readAsString();
    } on Exception catch (e) {
      _log.warning('readFile($dirPath, $fileName) failed: $e');
      rethrow;
    }
  }

  /// Write [content] to [fileName] inside [dirPath], creating the
  /// directory if needed (regular paths only — SAF directories are
  /// created by the picker).
  static Future<void> writeFile(
    String dirPath,
    String fileName,
    String content,
  ) async {
    try {
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
    } on Exception catch (e) {
      _log.warning('writeFile($dirPath, $fileName) failed: $e');
      rethrow;
    }
  }

  /// Open a SAF directory picker. Returns a `content://` tree URI with
  /// persistable read/write permissions, or null if the user cancelled.
  static Future<String?> pickDirectory() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('pickDirectory');
    } on Exception catch (e) {
      _log.warning('pickDirectory failed: $e');
      return null;
    }
  }

  /// Convert a `content://` tree URI to a human-readable path for display.
  /// Falls back to the raw URI when conversion fails or the path is not a
  /// content URI.
  static Future<String> displayPath(String path) async {
    if (Platform.isAndroid && _isContentUri(path)) {
      try {
        final result = await _channel.invokeMethod<String>(
          'getDisplayPath',
          path,
        );
        return result ?? path;
      } on Exception catch (e) {
        _log.warning('displayPath($path) failed: $e');
        return path;
      }
    }
    return path;
  }

  /// Delete every file inside [dirPath] whose name starts with [prefix].
  static Future<void> deleteFiles(String dirPath, String prefix) async {
    try {
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
    } on Exception catch (e) {
      _log.warning('deleteFiles($dirPath, $prefix) failed: $e');
      rethrow;
    }
  }
}
