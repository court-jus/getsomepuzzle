import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Lightweight `path_provider` fake: hands out a fresh temp directory for
/// every directory query so each test owns an isolated storage root.
class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform() : _temp = Directory.systemTemp.createTempSync();

  final Directory _temp;

  @override
  Future<String?> getApplicationDocumentsPath() async => _temp.path;

  @override
  Future<String?> getApplicationSupportPath() async => _temp.path;

  @override
  Future<String?> getTemporaryPath() async => _temp.path;

  @override
  Future<String?> getDownloadsPath() async => _temp.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('writeStats preserves cross-collection history', () {
    late _FakePathProviderPlatform fake;
    late String storageDir;
    late File statsFile;

    setUp(() {
      fake = _FakePathProviderPlatform();
      PathProviderPlatform.instance = fake;
      storageDir = p.join(fake._temp.path, 'getsomepuzzle');
      Directory(storageDir).createSync(recursive: true);
      statsFile = File(p.join(storageDir, 'stats.txt'));
    });

    test(
      'switching to a collection with zero played puzzles must not wipe the file',
      () async {
        // Regression for the exact log captured in todo.md: at boot the
        // user loaded `1-easy` and finished one puzzle, switched to
        // `2-player` (no overlap), and the next writeStats — fired by the
        // periodic timer or by next() — overwrote stats.txt with zero
        // bytes because getStats() only sees the current collection's
        // played puzzles.
        const easyEntry =
            '2026-05-11T17:55:49 17s 0f v2_12_3x3_000020020_FM:1.1;GS:0.1;PA:3.right;PA:8.left_1:122221122_8'
            ' - ___ -  -  -  -  - 0h - 0e - 0fc - 0lg';
        statsFile.writeAsStringSync(easyEntry);

        // Build a Database that's sitting on `2-player` with a fresh,
        // unrelated puzzle catalog — none of the loaded puzzles match
        // the 1-easy entry's canonical key.
        final db = Database(playerLevel: 50);
        db.collection = '2-player';
        db.puzzles = [PuzzleData('v2_12_4x4_0000000000000000_FM:1_0:0_0')];
        db.loadStats([easyEntry]); // mirrors what loadPuzzlesFile does

        // None of the 2-player puzzles are played, so getStats() is empty.
        expect(db.getStats(), isEmpty);

        await db.writeStats();

        // The file must still contain the 1-easy entry. Before the fix
        // it would have been clobbered down to 0 bytes.
        final persisted = statsFile.readAsStringSync().trim();
        expect(persisted, isNotEmpty);
        expect(persisted, contains('FM:1.1;GS:0.1;PA:3.right;PA:8.left'));
      },
    );

    test('two plays of the same puzzle on distinct dates are both kept', () async {
      // The full history must survive a replay: an older finished play on
      // disk and a newer in-session play of the same puzzle have different
      // completion stamps, so both rows are persisted (keyed on finished).
      const puzzleLine =
          'v2_12_3x3_000020020_FM:1.1;GS:0.1;PA:3.right;PA:8.left_1:122221122_8';
      const oldEntry =
          '2025-01-01T00:00:00 99s 9f $puzzleLine - ___ -  -  -  -  - 0h - 0e - 0fc - 0lg';
      statsFile.writeAsStringSync(oldEntry);

      final db = Database(playerLevel: 50);
      db.collection = '1-easy';
      final puz = PuzzleData(puzzleLine);
      puz.played = true;
      puz.finished = DateTime(2026, 5, 11, 17, 55, 49);
      puz.duration = 17;
      puz.failures = 0;
      db.puzzles = [puz];

      await db.writeStats();

      final persisted = statsFile.readAsStringSync().trim();
      final lines = persisted
          .split('\n')
          .where((l) => l.contains(puzzleLine))
          .toList();
      // Both the stale 2025 play and the fresh 2026 play are present.
      expect(lines, hasLength(2));
      expect(lines.any((l) => l.contains('99s 9f')), isTrue);
      expect(lines.any((l) => l.contains('17s 0f')), isTrue);
    });

    test('re-emitting the same play does not create a duplicate row', () async {
      // The periodic 60s flush re-emits the in-progress play every tick.
      // Because the dedup key includes the completion stamp, a play with the
      // same `finished` as the on-disk row collapses to a single entry, and
      // the in-session version (fresh timings) wins.
      const puzzleLine =
          'v2_12_3x3_000020020_FM:1.1;GS:0.1;PA:3.right;PA:8.left_1:122221122_8';
      // Same completion second as the session play below, but stale timings.
      const sameStampEntry =
          '2026-05-11T17:55:49 99s 9f $puzzleLine - ___ -  -  -  -  - 0h - 0e - 0fc - 0lg';
      statsFile.writeAsStringSync(sameStampEntry);

      final db = Database(playerLevel: 50);
      db.collection = '1-easy';
      final puz = PuzzleData(puzzleLine);
      puz.played = true;
      puz.finished = DateTime(2026, 5, 11, 17, 55, 49);
      puz.duration = 17;
      puz.failures = 0;
      db.puzzles = [puz];

      await db.writeStats();

      final persisted = statsFile.readAsStringSync().trim();
      final lines = persisted
          .split('\n')
          .where((l) => l.contains(puzzleLine))
          .toList();
      expect(lines, hasLength(1));
      expect(lines.single, contains('17s 0f'));
      expect(lines.single, isNot(contains('99s 9f')));
    });

    test(
      'an unfinished row is dropped once the puzzle has a finished play',
      () async {
        // A skip / abandoned attempt (finished == null) leaves an `unfinished`
        // row. Once the same puzzle is completed, the completion supersedes the
        // attempt and the unfinished row is purged — keeping the file free of
        // noise the analysis pipeline ignores anyway.
        const puzzleLine =
            'v2_12_3x3_000020020_FM:1.1;GS:0.1;PA:3.right;PA:8.left_1:122221122_8';
        const unfinishedEntry =
            'unfinished 0s 0f $puzzleLine - S__ - 2026-05-10T09:00:00 -  -  -  - 0h - 0e - 0fc - 0lg';
        statsFile.writeAsStringSync(unfinishedEntry);

        final db = Database(playerLevel: 50);
        db.collection = '1-easy';
        final puz = PuzzleData(puzzleLine);
        puz.played = true;
        puz.finished = DateTime(2026, 5, 11, 17, 55, 49);
        puz.duration = 17;
        puz.failures = 0;
        db.puzzles = [puz];

        await db.writeStats();

        final persisted = statsFile.readAsStringSync().trim();
        final lines = persisted
            .split('\n')
            .where((l) => l.contains(puzzleLine))
            .toList();
        expect(lines, hasLength(1));
        expect(lines.single, isNot(contains('unfinished')));
        expect(lines.single, contains('17s 0f'));
      },
    );

    test(
      'loadStats surfaces the most recent play, regardless of line order',
      () async {
        // With multiple finished plays of one puzzle in the file, the in-memory
        // PuzzleData must reflect the latest one. The on-disk order is
        // deliberately newest-first to prove the selection is by timestamp, not
        // by parse order.
        const puzzleLine =
            'v2_12_3x3_000020020_FM:1.1;GS:0.1;PA:3.right;PA:8.left_1:122221122_8';
        const recent =
            '2026-05-11T17:55:49 17s 0f $puzzleLine - ___ -  -  -  -  - 0h - 0e - 0fc - 0lg';
        const older =
            '2025-01-01T00:00:00 99s 9f $puzzleLine - ___ -  -  -  -  - 0h - 0e - 0fc - 0lg';

        final db = Database(playerLevel: 50);
        db.collection = '1-easy';
        final puz = PuzzleData(puzzleLine);
        db.puzzles = [puz];
        db.loadStats([recent, older]);

        expect(puz.played, isTrue);
        expect(puz.duration, 17);
        expect(puz.failures, 0);
        expect(puz.finished, DateTime(2026, 5, 11, 17, 55, 49));
      },
    );
  });
}
