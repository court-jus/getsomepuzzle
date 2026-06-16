import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/letter_group.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/prefill/path.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/groups.dart';

/// Tests for the path-based pre-fill backbone construction. We test the
/// *construction* (`buildPathBackbone`) directly — it is O(cells), deterministic
/// per seed, and
/// runs no DPLL — so the structural invariants are checked on `owner`/`colors`
/// without the expensive background completion. The completion itself is
/// `findOneSolutionByDpll` (covered by `backtrack_test`); end-to-end behaviour
/// is left to the generator runs.
void main() {
  // Backbone letter names live in a namespace disjoint from
  // `LetterGroup.generateAllParameters` (A.. upward, skipping 'I'). They run
  // Z, Y, X, … downward, also skipping 'I', so greedy-added LT candidates never
  // merge into a constructed region via `Puzzle.addConstraint`'s same-letter
  // aggregation.
  test('pathLetterNames: descend from Z, skip I, stay disjoint from A..', () {
    expect(pathLetterNames(1), ['Z']);
    expect(pathLetterNames(4), ['Z', 'Y', 'X', 'W']);
    // 'I' (charCode 73) must never appear, even for long runs that reach it.
    expect(pathLetterNames(20), isNot(contains('I')));
    expect(pathLetterNames(20).toSet(), hasLength(20)); // all distinct

    // For a concrete grid, the two namespaces must not intersect. An 8×8 grid
    // gives maxLetters = 64~/5 = 12 → greedy uses A..L (minus I).
    final maxLetters = max(1, (8 * 8) ~/ 5);
    final greedy = {
      for (int l = 0; l < maxLetters; l++)
        if (l != 8) String.fromCharCode(65 + l),
    };
    expect(pathLetterNames(4).toSet().intersection(greedy), isEmpty);
  });

  // The LT-forbidden merge the residual-graph moat exists to prevent: two cells
  // owned by *different* letters that are adjacent must have *different*
  // colours. (Same colour adjacent ⇒ the two letters would join one component.)
  test(
    'construction: adjacent cells of different letters differ in colour',
    () {
      for (int seed = 0; seed < 15; seed++) {
        final b = buildPathBackbone(6, 6, fullDomain, Random(seed));
        if (b == null) continue;
        for (int i = 0; i < b.owner.length; i++) {
          final oi = b.owner[i];
          if (oi == null) continue;
          for (final n in b.solved.getNeighbors(i)) {
            final on = b.owner[n];
            if (on != null && on != oi) {
              expect(
                b.colors[oi] == b.colors[on],
                isFalse,
                reason: 'seed $seed: $oi and $on adjacent yet same colour',
              );
            }
          }
        }
      }
    },
  );

  // Each letter's region is one monochrome connected component: all its cells
  // share the letter's colour, its anchors are among them, and a flood
  // restricted to the letter's cells reaches every one of them.
  test('construction: each region is monochrome and connected', () {
    for (int seed = 0; seed < 15; seed++) {
      final b = buildPathBackbone(6, 6, fullDomain, Random(seed));
      if (b == null) continue;
      for (final entry in b.anchors.entries) {
        final letter = entry.key;
        final cells = [
          for (int i = 0; i < b.owner.length; i++)
            if (b.owner[i] == letter) i,
        ];
        // Monochrome: every owned cell carries the letter's colour.
        for (final c in cells) {
          expect(b.solved.cellValues[c], b.colors[letter]);
        }
        // Anchors are part of the region.
        expect(cells, containsAll(entry.value));
        // Connected: a flood confined to this letter's cells reaches them all.
        final reached = floodFill(b.solved, [
          cells.first,
        ], (i) => b.owner[i] == letter);
        expect(reached, hasLength(cells.length), reason: 'seed $seed $letter');
      }
    }
  });

  // Domain 3 must own every colour (floor of |domain| letters), so the solution
  // genuinely uses all three and survives `autoShrinkDomain`.
  test('construction: domain 3 covers all three colours', () {
    for (int seed = 0; seed < 15; seed++) {
      final b = buildPathBackbone(6, 6, fullDomain, Random(seed));
      if (b == null) continue;
      expect(b.colors.values.toSet(), containsAll(fullDomain));
    }
  });

  // `removeUselessRules(preserveSlugs: {'LT'})` must keep the LT backbone even
  // when redundant for the solver, while the default still prunes it — this is
  // what guarantees a high lt-share survives finalisation.
  test('removeUselessRules preserves LT only when asked', () {
    // A fully-revealed 3×1 strip is trivially unique, so any constraint is
    // redundant. LT 'Z' spans cells 0 and 2, joined through the black cell 1.
    Puzzle build() {
      final p = Puzzle.empty(3, 1, defaultDomain);
      for (int i = 0; i < 3; i++) {
        p.cells[i].setForSolver(CellValue.black);
        p.cells[i].readonly = true;
      }
      p.addConstraint(LetterGroup('Z.0.2'));
      return p;
    }

    final pruned = build();
    pruned.removeUselessRules();
    expect(pruned.constraints.whereType<LetterGroup>(), isEmpty);

    final kept = build();
    kept.removeUselessRules(preserveSlugs: {'LT'});
    expect(kept.constraints.whereType<LetterGroup>(), isNotEmpty);
  });
}
