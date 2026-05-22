import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/canonical.dart';

void main() {
  group('canonicalPuzzleKey', () {
    test('drops the complexity score so algo evolutions still match', () {
      // Same puzzle, two different complexity scores produced by two
      // versions of computeComplexity(). The whole point of the canonical
      // key is to keep matching the same play across that drift.
      final a = 'v2_12_3x3_100000000_FM:12;PA:0.right_0:0_5';
      final b = 'v2_12_3x3_100000000_FM:12;PA:0.right_0:0_42';
      expect(canonicalPuzzleKey(a), canonicalPuzzleKey(b));
    });

    test('drops the cached solution segment', () {
      // The solution field is a cache populated after the first solve.
      // Two lines for the same puzzle, one with `0:0` (uncomputed) and
      // one with `1:<values>` (computed), must collide.
      final unsolved = 'v2_12_3x3_100000000_FM:12_0:0_0';
      final solved = 'v2_12_3x3_100000000_FM:12_1:122212211_0';
      expect(canonicalPuzzleKey(unsolved), canonicalPuzzleKey(solved));
    });

    test('drops the optional `_p:` play-state suffix', () {
      // lineWithPlayState() appends a `_p:<values>` field carrying the
      // player's in-progress cells. The canonical key must ignore it so
      // a saved-progress line and the bare line refer to the same puzzle.
      final bare = 'v2_12_3x3_100000000_FM:12_0:0_0';
      final withPlay = 'v2_12_3x3_100000000_FM:12_0:0_0_p:120000000';
      expect(canonicalPuzzleKey(bare), canonicalPuzzleKey(withPlay));
    });

    test('is insensitive to constraint order', () {
      // Constraint order has no semantic meaning (every constraint must
      // be satisfied independently). Two generators or two saved versions
      // can list them in different orders — they must canonicalize equally.
      final a = 'v2_12_3x3_100000000_FM:12;PA:0.right;GS:1.2_0:0_0';
      final b = 'v2_12_3x3_100000000_GS:1.2;FM:12;PA:0.right_0:0_0';
      expect(canonicalPuzzleKey(a), canonicalPuzzleKey(b));
    });

    test('collapses exact-duplicate constraints', () {
      // Some legacy lines carry the same constraint twice (e.g. an old
      // generator bug). These must canonicalize to the deduped form so
      // dedup-stats / dedup-puzzles can match them with clean lines.
      final dup = 'v2_12_3x3_100000000_FM:12;FM:12;PA:0.right_0:0_0';
      final clean = 'v2_12_3x3_100000000_FM:12;PA:0.right_0:0_0';
      expect(canonicalPuzzleKey(dup), canonicalPuzzleKey(clean));
    });

    test('ignores the version prefix so future formats keep matching', () {
      // The leading `v2_` is a format tag that may bump to `v3_` if the
      // line grammar evolves. The structural identity of a puzzle is
      // unchanged by such a bump, so the canonical key must agree.
      final v2 = 'v2_12_3x3_100000000_FM:12_0:0_0';
      final v3 = 'v3_12_3x3_100000000_FM:12_0:0_0';
      expect(canonicalPuzzleKey(v2), canonicalPuzzleKey(v3));
    });

    test('different prefill produces different keys', () {
      // Sanity check that the canonicalization is not so aggressive it
      // collapses genuinely distinct puzzles. Prefill is part of identity.
      final a = 'v2_12_3x3_100000000_FM:12_0:0_0';
      final b = 'v2_12_3x3_200000000_FM:12_0:0_0';
      expect(canonicalPuzzleKey(a), isNot(canonicalPuzzleKey(b)));
    });

    test('different constraint set produces different keys', () {
      // Same prefill and dimensions but a different constraint must yield
      // a different key — otherwise the two puzzles would share stats.
      final a = 'v2_12_3x3_100000000_FM:12_0:0_0';
      final b = 'v2_12_3x3_100000000_PA:0.right_0:0_0';
      expect(canonicalPuzzleKey(a), isNot(canonicalPuzzleKey(b)));
    });
  });

  group('dedupAndSortConstraints', () {
    test('removes exact duplicates and sorts the survivors', () {
      // Direct unit on the constraint-field helper: deterministic order
      // is what makes the canonical key stable.
      expect(
        dedupAndSortConstraints('PA:0.right;FM:12;PA:0.right;GS:1.2'),
        'FM:12;GS:1.2;PA:0.right',
      );
    });
  });

  group('normalizeV2Line', () {
    test('sorts and dedupes the constraints field but keeps the v2 grammar', () {
      // The on-disk format must remain v2: prefix, domain, dimensions,
      // prefill, constraints, solution, complexity. Downstream tools
      // (analyze_stats.dart, the Puzzle() constructor, ...) read these
      // fields by position. normalizeV2Line touches only field 4.
      final input =
          'v2_12_3x3_100000000_PA:0.right;FM:12;PA:0.right;FM:12_1:122212211_5';
      final output = normalizeV2Line(input);
      expect(output, 'v2_12_3x3_100000000_FM:12;PA:0.right_1:122212211_5');
    });

    test('preserves trailing play-state field', () {
      // The optional `_p:<values>` suffix tracks an in-progress play.
      // It must survive normalization untouched so progress isn't lost.
      final input = 'v2_12_3x3_100000000_FM:12_0:0_5_p:120000000';
      expect(normalizeV2Line(input), input);
    });

    test('returns the line as-is when it is too short to have constraints', () {
      // Defensive: don't crash on malformed/truncated input.
      expect(normalizeV2Line('v2_12_3x3'), 'v2_12_3x3');
    });
  });

  group('normalizeToV2Line', () {
    test('returns a full v2 line unchanged', () {
      // Already-versioned lines are the dominant input — assets, stats,
      // generator output. The helper must be a no-op for them.
      const line = 'v2_12_3x3_100000000_FM:12_0:0_5';
      expect(normalizeToV2Line(line), line);
    });

    test('prefixes a bare canonical key with v2_', () {
      // `canonicalPuzzleKey` strips the version prefix and the
      // solution/cplx tail. The helper has to put a parseable v2 prefix
      // back so PuzzleData/Puzzle constructors can split fields by index.
      const canonical = '12_3x3_100000000_FM:12;PA:0.right';
      expect(normalizeToV2Line(canonical), 'v2_$canonical');
    });

    test('extracts the puzzle query parameter from a share URL', () {
      // The share button builds URLs like https://app/?puzzle=v2_... so
      // pasting the URL must yield the embedded line.
      const url = 'https://example.com/play/?puzzle=v2_12_3x3_100000000_FM:12';
      expect(normalizeToV2Line(url), 'v2_12_3x3_100000000_FM:12');
    });

    test('extracts a bare canonical key from a share URL', () {
      // The log emits canonical keys, so a user may share a URL whose
      // `puzzle` param is already canonical. Recurse so the canonical
      // branch handles it.
      const url = 'https://example.com/?puzzle=12_3x3_100000000_FM:12';
      expect(normalizeToV2Line(url), 'v2_12_3x3_100000000_FM:12');
    });

    test('returns null on empty input', () {
      // The paste handler fires on every keystroke — an empty buffer
      // must not throw and must not select a puzzle.
      expect(normalizeToV2Line(''), isNull);
      expect(normalizeToV2Line('   '), isNull);
    });

    test('returns null on a URL with no puzzle parameter', () {
      // Defensive: a random pasted URL shouldn't be guessed at.
      expect(
        normalizeToV2Line('https://example.com/somewhere?other=42'),
        isNull,
      );
    });

    test('returns null on garbage input', () {
      // Anything that doesn't structurally look like the three formats
      // is rejected so the caller can stay silent on partial input.
      expect(normalizeToV2Line('xyz'), isNull);
      expect(normalizeToV2Line('foo_bar'), isNull);
      // Looks vaguely like canonical but the dimensions field is wrong.
      expect(normalizeToV2Line('12_three_100000000_FM:12'), isNull);
      // Same but the prefill segment isn't all digits.
      expect(normalizeToV2Line('12_3x3_abcdef_FM:12'), isNull);
      // Constraints field has no slug:params pair.
      expect(normalizeToV2Line('12_3x3_100000000_nothing'), isNull);
    });

    test(
      'round-trip: canonicalPuzzleKey output normalizes back to a parseable line',
      () {
        // The motivating use case: the `Puzzle loaded` log prints
        // `canonicalPuzzleKey(...)`. Pasting that key into the open
        // dialog must produce a line that `PuzzleData` parses without
        // throwing — verified here by checking the round-trip canonical
        // key matches the original.
        const original = 'v2_12_3x3_100000000_FM:12;PA:0.right_0:0_5';
        final key = canonicalPuzzleKey(original);
        final normalized = normalizeToV2Line(key);
        expect(normalized, isNotNull);
        expect(canonicalPuzzleKey(normalized!), key);
      },
    );
  });

  group('canonicalPuzzleKey - dual format robustness', () {
    test('legacy v2 line and its normalized form yield the same key', () {
      // After normalizeV2Line() rewrites the constraints section, the
      // line is still v2 but with sorted-deduped constraints. Both
      // versions of the line must produce the same canonical key — that
      // is the contract that lets the runtime match a freshly-played
      // entry against an old, raw v2 line in the same stats file.
      final raw =
          'v2_12_3x3_100000000_PA:0.right;FM:12;PA:0.right_1:122212211_5';
      final normalized = normalizeV2Line(raw);
      expect(canonicalPuzzleKey(raw), canonicalPuzzleKey(normalized));
    });

    test('canonical-form input is idempotent', () {
      // Applying canonicalPuzzleKey to its own output must be a no-op.
      // Otherwise a stats file containing canonical lines would not
      // match itself after a second pass through the matching code.
      final input = 'v2_12_3x3_100000000_PA:0.right;FM:12;GS:1.2_1:122212211_5';
      final once = canonicalPuzzleKey(input);
      expect(canonicalPuzzleKey(once), once);
    });
  });
}
