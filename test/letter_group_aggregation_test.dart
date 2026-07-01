import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/letter_group.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

void main() {
  group('LetterGroup aggregation through addConstraint', () {
    test(
      'two LT pairs sharing the same letter merge into one constraint at parse',
      () {
        // Pre-aggregation each LT was independent: LT:D.0.4 only required
        // cells {0, 4} to be in the same connected component, LT:D.10.19
        // required {10, 19} separately. The bug from collection3.txt:137
        // was that two such pairs could be jointly accepted by the
        // generator while the deserialised puzzle (which aggregated them)
        // demanded all four cells in a single component. We now aggregate
        // on every add — including parse — so the test can simply observe
        // the post-construction shape.
        final p = Puzzle('v2_12_3x3_000000000_LT:A.0.1;LT:A.7.8_0:0_0');
        final letters = p.constraints.whereType<LetterGroup>().toList();
        expect(letters, hasLength(1));
        expect(letters.first.letter, 'A');
        expect(letters.first.indices.toSet(), {0, 1, 7, 8});
      },
    );

    test('addConstraint merges a second LT pair into the existing one', () {
      // Same invariant, but exercised through the public API — the
      // generator and create-page paths both reach the puzzle this way.
      final p = Puzzle('v2_12_3x3_000000000_FM:11_0:0_0');
      p.addConstraint(LetterGroup('A.0.1'));
      p.addConstraint(LetterGroup('A.7.8'));
      final letters = p.constraints.whereType<LetterGroup>().toList();
      expect(letters, hasLength(1));
      expect(letters.first.indices.toSet(), {0, 1, 7, 8});
    });

    test('LT pairs with different letters stay separate', () {
      final p = Puzzle('v2_12_3x3_000000000_FM:11_0:0_0');
      p.addConstraint(LetterGroup('A.0.1'));
      p.addConstraint(LetterGroup('B.7.8'));
      final letters = p.constraints.whereType<LetterGroup>().toList();
      expect(letters, hasLength(2));
      expect(letters.map((g) => g.letter).toSet(), {'A', 'B'});
    });

    test(
      'collection3.txt:137 buggy puzzle: cached solution violates aggregated LT:D',
      () {
        // Exact regression: the published cachedSolution puts the four
        // D-anchors (0, 4, 10, 19) into two disjoint connected components
        // of value 2. Once aggregated, LT:D demands a single component,
        // so check() must report exactly the LT:D failure when we replay
        // the cachedSolution onto the puzzle.
        final p = Puzzle(
          'v2_12_4x7_0000200000000000000000000000_'
          'GC:1.4;LT:D.0.4;EY:15.1.0;NC:27.1.2;SY:4.2;GS:0.2;DF:13.right;'
          'FM:121;PA:17.right;LT:D.10.19;EY:24.1.4;GS:17.5;SY:24.4;'
          'NC:6.2.3;DF:6.right;FM:11.22'
          '_1:2122211211222122221212212111_36',
        );
        // Single aggregated LetterGroup with all four anchors.
        final lt = p.constraints.whereType<LetterGroup>().single;
        expect(lt.letter, 'D');
        expect(lt.indices.toSet(), {0, 4, 10, 19});

        // Replay cachedSolution onto the puzzle.
        final sol = p.cachedSolution!;
        for (int i = 0; i < sol.length; i++) {
          p.setValue(i, sol[i]);
        }
        expect(p.complete, isTrue);
        final errors = p.check(saveResult: false);
        expect(errors, hasLength(1));
        expect(errors.single.serialize(), startsWith('LT:D.'));
      },
    );
  });

  test('complicity cache is recomputed after addConstraint mutates the set', () {
    // The lazy complicity cache must be invalidated whenever the
    // constraint set changes; otherwise mid-build code that read
    // `complicities` once would freeze the result against an outdated
    // snapshot. Concretely: a puzzle with only FM has no complicity,
    // adding PA opens up PABalancedSideComplicity.
    final p = Puzzle('v2_12_3x3_000000000_FM:2.1_0:0_0');
    expect(p.complicities, isEmpty);
    p.addConstraint(
      // PA:8.top forms the canonical PABalancedSideComplicity pair with FM:2.1.
      // Built by createConstraint via the registry.
      _buildConstraint('PA', '8.top'),
    );
    expect(p.complicities, isNotEmpty);
  });
}

dynamic _buildConstraint(String slug, String params) {
  // Local re-export to keep the test independent of the registry import
  // path; the registry is exercised through Puzzle's own constructor.
  // Using a fresh Puzzle whose serialisation includes the slug/params
  // we need is the most robust way to obtain the typed instance.
  final p = Puzzle('v2_12_3x3_000000000_$slug:${params}_0:0_0');
  return p.constraints.last;
}
