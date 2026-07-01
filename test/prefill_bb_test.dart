import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/bounding_box.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/prefill/bb.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/groups.dart';

/// Bounding box `(height, width)` of a group of cell indices.
(int, int) _extentHW(List<int> group, int gridWidth) {
  int minR = group.first ~/ gridWidth, maxR = minR;
  int minC = group.first % gridWidth, maxC = minC;
  for (final i in group) {
    final r = i ~/ gridWidth, c = i % gridWidth;
    if (r < minR) minR = r;
    if (r > maxR) maxR = r;
    if (c < minC) minC = c;
    if (c > maxC) maxC = c;
  }
  return (maxR - minR + 1, maxC - minC + 1);
}

void main() {
  // The whole point of preFillBB: a BB constraint only survives the generator's
  // `verify(solved)` candidate filter when *every* group of its colour shares
  // one extent. These tests assert that the pre-fill delivers that invariant by
  // construction, so a random seed can never produce an unsatisfiable BB grid.
  group('preFillBB by-construction invariant', () {
    test('every attached BB constraint is satisfied and every colour group has '
        'the declared W×H extent', () {
      // Sweep seeds and grid sizes over both domains. A failure here means a
      // grown island either missed its extent or merged/split into a wrong
      // group — exactly what the candidate filter would silently reject.
      for (final domain in [defaultDomain, fullDomain]) {
        for (final (w, h) in [(6, 5), (8, 8), (5, 7)]) {
          for (int seed = 0; seed < 25; seed++) {
            final solved = preFillBB(w, h, domain, Random(seed));

            // Background fill leaves no free cell → verify uses the exact
            // (complete) extent check, not the reachability relaxation.
            expect(
              solved.complete,
              isTrue,
              reason: 'grid $w×$h domain$domain seed$seed left free cells',
            );

            final bbs = solved.constraints
                .whereType<BoundingBoxConstraint>()
                .toList();
            expect(
              bbs,
              isNotEmpty,
              reason: 'no BB constraint attached ($w×$h seed$seed)',
            );

            for (final bb in bbs) {
              expect(
                bb.verify(solved),
                isTrue,
                reason: 'BB ${bb.serialize()} not satisfied on $w×$h seed$seed',
              );
              // A planted box must sit strictly inside the grid — never
              // spanning a full dimension (matches generateAllParameters).
              expect(
                bb.width < solved.width && bb.height < solved.height,
                isTrue,
                reason:
                    'BB ${bb.serialize()} spans a full grid dimension on '
                    '$w×$h seed$seed',
              );
              final groups = getColorGroups(solved, bb.color);
              expect(
                groups,
                isNotEmpty,
                reason: 'BB ${bb.serialize()} has no group on seed$seed',
              );
              for (final g in groups) {
                final (gh, gw) = _extentHW(g, solved.width);
                expect(
                  (gh, gw),
                  (bb.height, bb.width),
                  reason:
                      'group of ${bb.serialize()} has extent $gh×$gw on '
                      '$w×$h seed$seed',
                );
              }
            }
          }
        }
      }
    });
  });

  group('second BB colour gating', () {
    test('a 2-colour domain never draws a second BB colour', () {
      // On domain 2 the only non-BB colour is the background; a second BB
      // colour would leave no background, so the pre-fill must never draw one.
      for (int seed = 0; seed < 50; seed++) {
        final solved = preFillBB(7, 6, defaultDomain, Random(seed));
        final bbs = solved.constraints.whereType<BoundingBoxConstraint>();
        expect(
          bbs.length,
          1,
          reason: 'domain-2 seed$seed produced ${bbs.length} BB constraints',
        );
      }
    });
  });

  group('findAdditionalBoxPositions separation', () {
    test(
      'returned shapes have the exact W×H extent and never touch an existing '
      'same-colour island',
      () {
        // A 3×3 black ring pinned top-left; the rest of a 7×5 grid is free.
        // Any further black 3×3 island must keep its own extent and stay
        // orthogonally apart from the ring (else the two groups would merge,
        // breaking BB). Boxes may still overlap — only cells must separate.
        const gw = 7, gh = 5, boxW = 3, boxH = 3;
        final initialBlack = <int>{
          0, 1, 2, // row 0, cols 0-2
          7, 9, // row 1, cols 0 and 2 (hollow centre)
          14, 15, 16, // row 2, cols 0-2
        };

        var foundAny = false;
        for (int seed = 0; seed < 40; seed++) {
          final p = Puzzle.empty(gw, gh, defaultDomain);
          for (final i in initialBlack) {
            p.cells[i].setForSolver(CellValue.black);
          }

          final shapes = findAdditionalBoxPositions(
            p,
            CellValue.black,
            boxW,
            boxH,
            Random(seed),
          );

          for (final shape in shapes) {
            foundAny = true;
            // Extent is exactly the declared box.
            final (eh, ew) = _extentHW(shape.toList(), gw);
            expect(
              (eh, ew),
              (boxH, boxW),
              reason: 'shape extent $eh×$ew ≠ $boxH×$boxW (seed$seed)',
            );
            // No shape cell is orthogonally adjacent to the existing island.
            for (final cell in shape) {
              expect(
                initialBlack.contains(cell),
                isFalse,
                reason: 'shape reused an existing black cell (seed$seed)',
              );
              final r = cell ~/ gw, c = cell % gw;
              final nbrs = <int>[
                if (c > 0) cell - 1,
                if (c < gw - 1) cell + 1,
                if (r > 0) cell - gw,
                if (r < gh - 1) cell + gw,
              ];
              for (final n in nbrs) {
                expect(
                  initialBlack.contains(n),
                  isFalse,
                  reason:
                      'shape cell $cell is adjacent to the existing island '
                      '(seed$seed) — groups would merge',
                );
              }
            }
          }
        }
        expect(
          foundAny,
          isTrue,
          reason: 'no additional 3×3 black box found over 40 seeds',
        );
      },
    );
  });
}
