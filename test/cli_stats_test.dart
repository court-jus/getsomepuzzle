import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/play_model.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/stats.dart';

import '../bin/aggregate_player_stats.dart' as aggregator;

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
      final entry = StatEntry.parse(
        'unfinished 0s 0f v2_12_3x3_000_FM:12_0:0_0 - ___',
      );
      expect(entry, isNotNull);
      expect(entry!.finished, isNull);
    });

    test('parses the optional hints field when present', () {
      // Hints were added as a trailing `Nh` token after pleasure. Current
      // format has 16 space-separated fields with hints at position 15.
      final entry = StatEntry.parse(
        '2025-01-01T10:00:00 60s 2f v2_12_3x3_000000000_FM:12_0:0_0 - _L_ -  - 2025-01-01T10:00:00 -  - 2 - 3h',
      );
      expect(entry, isNotNull);
      expect(entry!.hints, 3);
    });

    test('defaults hints to 0 for older lines without the field', () {
      // Lines written before the hints tracking must still parse cleanly.
      final entry = StatEntry.parse(
        '2025-01-01T10:00:00 60s 2f v2_12_3x3_000000000_FM:12_0:0_0 - _L_ -  - 2025-01-01T10:00:00 -  - 2',
      );
      expect(entry, isNotNull);
      expect(entry!.hints, 0);
    });

    test('parses cell-edit analytics (cellEdits/firstClickMs/longestGapMs)', () {
      // The three trailing fields capture in-play hesitation; their suffixes
      // are `e`, `fc`, `lg`. Older lines without them parse with all three
      // defaulting to 0 (covered by the test above).
      final entry = StatEntry.parse(
        '2025-01-01T10:00:00 60s 2f v2_12_3x3_000000000_FM:12_0:0_0 - ___ -  -  -  -  - 0h - 27e - 4500fc - 18000lg',
      );
      expect(entry, isNotNull);
      expect(entry!.cellEdits, 27);
      expect(entry.firstClickMs, 4500);
      expect(entry.longestGapMs, 18000);
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
      expect(sortPuzzlesByDifficulty(stats), [
        'puzzle_easy',
        'puzzle_medium',
        'puzzle_hard',
      ]);
    });
  });

  group('parsePuzzleLineFields', () {
    test('reads cplx, cells and nCons from their positional fields', () {
      final fields = parsePuzzleLineFields(
        'v2_12_3x3_000000000_FM:12_1:111111111_5',
      );
      expect(fields, isNotNull);
      expect(fields!.cplx, 5);
      expect(fields.cells, 9);
      expect(fields.nCons, 1);
    });

    test('ignores trailing play-state / scenario fields after cplx', () {
      // Regression: `cplx` used to be read from the *last* field, which the
      // `_p:<state>` / `_scenario:<name>` tails silently broke (the play was
      // dropped entirely).
      for (final tail in ['_p:111111111', '_scenario:sh']) {
        final fields = parsePuzzleLineFields(
          'v2_12_3x3_000000000_FM:12_1:111111111_5$tail',
        );
        expect(fields?.cplx, 5, reason: 'tail=$tail');
        expect(fields?.cells, 9, reason: 'tail=$tail');
      }
    });

    test('returns null for lines without usable dimensions', () {
      expect(parsePuzzleLineFields('garbage'), isNull);
    });
  });

  group('aggregate_player_stats re-emit', () {
    test('preserves unknown tokens and refreshes the derived lvl', () {
      // The aggregator rewrites field [3] and strips only `*lvl`. Everything
      // else must survive verbatim — that is what keeps the `Ncol` readiness
      // tag (and any future suffix-tagged field) alive through the offline
      // pipeline.
      const raw =
          '2026-05-01T10:00:00 120s 2f '
          'v2_12_4x4_0000000000000000_FM:1_0:0_5'
          ' - ___ -  -  -  -  - 0h - 0e - 0fc - 0lg - 3col - 999lvl';
      final entry = StatEntry.parse(raw)!;
      expect(entry.collectionIndex, 3);

      final out = aggregator.reemitStatLine(raw, entry.puzzleLine, entry);
      expect(out, contains('3col'));
      expect(out, contains('${120 + 30 * 2}lvl'));
      expect(out, isNot(contains('999lvl')));
      // Round-trips back through the app parser with the tag intact.
      expect(StatEntry.parse(out)!.collectionIndex, 3);
    });
  });
}
