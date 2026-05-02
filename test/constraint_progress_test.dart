import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constraint_progress.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ConstraintProgress.noteSeen', () {
    test('records the date when the slug is unseen', () {
      // First-time encounter: store the date as-is. This is the path
      // taken when the player opens a fresh puzzle whose constraint
      // they have never met before.
      final p = ConstraintProgress();
      final t = DateTime(2026, 4, 1);
      expect(p.noteSeen('FM', t), isTrue);
      expect(p.firstSeen['FM'], t);
      expect(p.isFirstTimeFor('FM'), isFalse);
    });

    test('keeps the earliest date when called with a later one', () {
      // Stats are not guaranteed chronological at load. If we receive a
      // later date after an earlier one, the earlier one must win — this
      // preserves the genuine "first encounter" semantic.
      final p = ConstraintProgress();
      final earlier = DateTime(2026, 1, 15);
      final later = DateTime(2026, 4, 1);
      p.noteSeen('GS', earlier);
      expect(p.noteSeen('GS', later), isFalse);
      expect(p.firstSeen['GS'], earlier);
    });

    test('updates when called with a date earlier than the stored one', () {
      // Reverse case: a more-recent stat was loaded first, then an older
      // one comes in. The older one must replace the stored value.
      final p = ConstraintProgress();
      final later = DateTime(2026, 4, 1);
      final earlier = DateTime(2026, 1, 15);
      p.noteSeen('PA', later);
      expect(p.noteSeen('PA', earlier), isTrue);
      expect(p.firstSeen['PA'], earlier);
    });
  });

  group('ConstraintProgress.clear', () {
    test('forgets every recorded encounter', () {
      // Used by the "rejouer l'onboarding" button. The map must be empty
      // after clear so isFirstTimeFor reports true again.
      final p = ConstraintProgress();
      p.noteSeen('FM', DateTime(2026, 1, 1));
      p.noteSeen('NC', DateTime(2026, 2, 1));
      p.clear();
      expect(p.firstSeen, isEmpty);
      expect(p.isFirstTimeFor('FM'), isTrue);
    });
  });

  group('ConstraintProgress persistence', () {
    setUp(() {
      // Each test runs against a fresh in-memory prefs instance so
      // saves don't leak between cases.
      SharedPreferences.setMockInitialValues({});
    });

    test('save then load round-trips the map verbatim', () {
      // Round-trip check: dates serialize as ISO strings and parse back
      // identical (millisecond precision is preserved by ISO-8601).
      final p = ConstraintProgress();
      final dt = DateTime.utc(2026, 5, 2, 14, 30, 45, 678);
      p.noteSeen('FM', dt);
      p.noteSeen('GS', DateTime.utc(2026, 1, 1));
      return p.save().then((_) {
        final loaded = ConstraintProgress();
        return loaded.load().then((_) {
          expect(loaded.firstSeen['FM'], dt);
          expect(loaded.firstSeen['GS'], DateTime.utc(2026, 1, 1));
          expect(loaded.firstSeen.length, 2);
        });
      });
    });

    test('load returns empty when no payload exists', () async {
      // First launch on a fresh device: prefs is empty, load must not
      // throw and must leave the map empty.
      final p = ConstraintProgress();
      await p.load();
      expect(p.firstSeen, isEmpty);
    });

    test('load survives a malformed JSON payload', () async {
      // Forward-compat: if a future version writes a different format
      // or the prefs file is corrupted, we recover by starting fresh
      // rather than crashing on every subsequent launch.
      SharedPreferences.setMockInitialValues({
        'constraintFirstSeen': 'not json{',
      });
      final p = ConstraintProgress();
      await p.load();
      expect(p.firstSeen, isEmpty);
    });

    test('load skips entries with non-string values', () async {
      // Defensive: any individual entry that doesn't decode as a string
      // (or doesn't parse as ISO date) is dropped, while valid entries
      // are kept.
      SharedPreferences.setMockInitialValues({
        'constraintFirstSeen': '{"FM":"2026-01-01","BAD":42,"GS":"not-a-date"}',
      });
      final p = ConstraintProgress();
      await p.load();
      expect(p.firstSeen.keys, ['FM']);
      // DateTime.parse on a date-only string yields a local-time
      // DateTime (no Z); the test compares against the same form.
      expect(p.firstSeen['FM'], DateTime.parse('2026-01-01'));
    });
  });

  group('Database.loadStats reconstruction', () {
    // End-to-end check that Database.loadStats populates the optional
    // `progress` from finished, non-skipped stat entries — the path taken
    // on app startup to backfill firstSeen from legacy plays.

    String stat(String puzzleLine, String finishedIso) {
      // Synthesize the on-disk stat-line format (see PuzzleData.getStat).
      // SLD = "___" (no skip/like/dislike); empty extras after the dashes.
      return '$finishedIso 30s 0f $puzzleLine - ___ -  -  -  - 0h - 0e - 0fc - 0lg';
    }

    test('records every slug from finished, non-skipped plays', () {
      // A finished play of a 2-rule puzzle records both slugs at the
      // play's finished date.
      final progress = ConstraintProgress();
      final db = Database(playerLevel: 50, progress: progress);
      db.loadStats([
        stat(
          'v2_12_3x3_000020000_FM:11;GS:4.1_1:212121212_6',
          '2026-03-15T10:00:00',
        ),
      ]);
      expect(progress.firstSeen.keys, unorderedEquals(['FM', 'GS']));
      expect(progress.firstSeen['FM'], DateTime.parse('2026-03-15T10:00:00'));
      expect(progress.firstSeen['GS'], DateTime.parse('2026-03-15T10:00:00'));
    });

    test('keeps the earliest date across multiple plays of the same slug', () {
      // Stats are not chronologically ordered when read from disk. We
      // process the recent one first, then the older one — the older
      // date must overwrite the recent one (genuine "first" seen).
      final progress = ConstraintProgress();
      final db = Database(playerLevel: 50, progress: progress);
      db.loadStats([
        stat(
          'v2_12_3x3_000020000_FM:11;GS:4.1_1:212121212_6',
          '2026-03-15T10:00:00',
        ),
        stat('v2_12_3x3_000020000_FM:11_1:212121212_6', '2026-01-02T08:00:00'),
      ]);
      expect(progress.firstSeen['FM'], DateTime.parse('2026-01-02T08:00:00'));
      expect(progress.firstSeen['GS'], DateTime.parse('2026-03-15T10:00:00'));
    });

    test('skipped plays do not contribute to firstSeen', () {
      // The player gave up — they probably didn't engage with the
      // constraint. We only count plays where finished != null AND
      // skipped == null.
      final progress = ConstraintProgress();
      final db = Database(playerLevel: 50, progress: progress);
      // SLD field uses "S" in slot 0 to mark a skipped play; extras
      // also carry the skipped timestamp.
      const skippedLine =
          '2026-03-15T10:00:00 0s 0f v2_12_3x3_000020000_FM:11_1:212121212_6 - S__ - 2026-03-15T10:01:00 -  -  -  - 0h - 0e - 0fc - 0lg';
      db.loadStats([skippedLine]);
      expect(progress.firstSeen, isEmpty);
    });

    test('no-progress mode is harmless (database without tracker)', () {
      // CLI tools and unit tests that don't need the onboarding flow
      // can omit `progress` entirely. loadStats must not throw.
      final db = Database(playerLevel: 50);
      db.loadStats([
        stat('v2_12_3x3_000020000_FM:11_1:212121212_6', '2026-03-15T10:00:00'),
      ]);
      // Nothing to assert — the test is that we didn't crash.
    });
  });

  group('ConstraintProgress.slugsFromLine', () {
    test('extracts slugs from a typical v2 line', () {
      // Standard v2 line with three constraints: FM, GS and a TX legacy
      // entry that must be ignored.
      const line = 'v2_12_3x3_100000000_FM:1.2;GS:7.1;TX:textN_1:121121121_5';
      final slugs = ConstraintProgress.slugsFromLine(line);
      expect(slugs, {'FM', 'GS'});
    });

    test('handles a line with no version prefix', () {
      // The canonical key drops the v2_ prefix; the helper must still
      // extract slugs from that bare-canonical form so we can feed it
      // canonicalised lines too.
      const line = '12_3x3_100000000_FM:11;NC:7.1.0_solution';
      final slugs = ConstraintProgress.slugsFromLine(line);
      expect(slugs, {'FM', 'NC'});
    });

    test('returns empty for a malformed line', () {
      // Too few fields: nothing to parse, no exception.
      expect(ConstraintProgress.slugsFromLine('garbage'), isEmpty);
    });
  });
}
