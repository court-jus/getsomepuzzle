import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/stats.dart';

void main() {
  group('StatEntry.parse', () {
    test('parses a valid stat line', () {
      // Format from PuzzleData.getStat():
      // finishedTimestamp durationS failuresF puzzleLine - SLD - skipped - liked - disliked - pleasure
      final entry = StatEntry.parse(
        '2025-01-01T10:00:00 60s 2f v2_12_3x3_000000000_FM:12_0:0_0 - _L_ -  - 2025-01-01T10:00:00 -  - 2',
      );
      expect(entry, isNotNull);
      expect(entry!.finished, '2025-01-01T10:00:00');
      expect(entry.duration, 60);
      expect(entry.failures, 2);
      expect(entry.puzzleLine, 'v2_12_3x3_000000000_FM:12_0:0_0');
    });

    test('returns null for lines with too few fields', () {
      expect(StatEntry.parse(''), isNull);
      expect(StatEntry.parse('only two fields'), isNull);
    });

    test('parses unfinished puzzles', () {
      final entry = StatEntry.parse('unfinished 0s 0f v2_12_3x3_000_FM:12_0:0_0 - ___');
      expect(entry, isNotNull);
      expect(entry!.finished, isNull);
    });
  });

  group('aggregateStats', () {
    test('aggregates multiple plays of the same puzzle', () {
      final stats = aggregateStats([
        '2025-01-01T10:00:00 10s 0f puzzleA - ___',
        '2025-01-01T10:01:00 20s 1f puzzleA - ___',
      ]);
      expect(stats.length, 1);
      expect(stats['puzzleA']!.total, 2);
      expect(stats['puzzleA']!.duration, 30);
      expect(stats['puzzleA']!.failures, 1);
    });

    test('level is avg_duration + 30 * avg_failures', () {
      final stats = aggregateStats([
        '2025-01-01T10:00:00 10s 0f puzzleA - ___',
        '2025-01-01T10:01:00 20s 1f puzzleA - ___',
      ]);
      // avg_duration=15, avg_failures=0.5 → level = 15 + 15 = 30
      expect(stats['puzzleA']!.level, 30);
    });
  });

  group('sortPuzzlesByDifficulty', () {
    test('sorts puzzles by ascending level', () {
      final stats = aggregateStats([
        '2025-01-01T10:00:00 60s 2f puzzle_hard - ___',
        '2025-01-01T10:01:00 5s 0f puzzle_easy - ___',
        '2025-01-01T10:02:00 30s 1f puzzle_medium - ___',
      ]);
      // puzzle_easy: level=5, puzzle_medium: level=60, puzzle_hard: level=120
      expect(sortPuzzlesByDifficulty(stats), ['puzzle_easy', 'puzzle_medium', 'puzzle_hard']);
    });
  });
}
