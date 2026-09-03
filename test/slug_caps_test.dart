import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/implication.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/majority.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/symmetry.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/generator.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constants.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

Puzzle pz(int width, int height) => Puzzle.empty(width, height, defaultDomain);
ForbiddenMotif fm(String motif) => ForbiddenMotif(motif);
ImplicationConstraint im(String params) => ImplicationConstraint(params);
MajorityConstraint mj(String corners) => MajorityConstraint('$corners.1');
SymmetryConstraint sy(String params) => SymmetryConstraint(params);

/// Count of `slug` tokens in the v2 line's constraints field (index 4).
int _slugCount(String line, String slug) {
  final parts = line.split('_');
  if (parts.length < 5) return 0;
  var n = 0;
  for (final c in parts[4].split(';')) {
    if (c.startsWith('$slug:')) n++;
  }
  return n;
}

List<String> _generateLines(Set<String> slugs) {
  final lines = <String>[];
  for (var i = 0; i < 15; i++) {
    final r = PuzzleGenerator.generateOne(
      GeneratorConfig(width: 6, height: 6, allowedSlugs: slugs),
    );
    if (r != null) lines.add(r.line);
  }
  return lines;
}

void main() {
  group('maxSlugOccurrences formula', () {
    test('constant-driven caps', () {
      expect(maxSlugOccurrences('FM', 3, 10), 4);
      expect(maxSlugOccurrences('IM', 4, 5), 4); // floor: avg 4.5 -> 4
      expect(maxSlugOccurrences('IM', 6, 6), 6);
      expect(maxSlugOccurrences('PA', 5, 5), isNull); // uncapped slug
    });
  });

  group('FM cap', () {
    test('cap-th placement accepted, next refused', () {
      final p = pz(5, 5);
      final cap = maxSlugOccurrences('FM', 5, 5)!;
      expect(cap, kMaxFmPerPuzzle);
      for (final m in [
        '11',
        '12',
        '21',
        '22',
        '1.1',
        '1.2',
        '2.1',
        '2.2',
      ].take(cap)) {
        p.addConstraint(fm(m));
      }
      expect(p.constraints.length, cap);
      expect(fm('1.1').canBeAddedTo(p), isFalse);
    });

    test('cap - 1 existing still accepts', () {
      final p = pz(5, 5);
      final cap = maxSlugOccurrences('FM', 5, 5)!;
      for (final m in ['11', '12', '21'].take(cap - 1)) {
        p.addConstraint(fm(m));
      }
      expect(fm('22').canBeAddedTo(p), isTrue);
    });

    test('empty puzzle accepts', () {
      expect(fm('11').canBeAddedTo(pz(5, 5)), isTrue);
    });
  });

  group('IM cap', () {
    test('cap-th placement accepted, next refused', () {
      final imCap = maxImPerPuzzle(4, 5);
      expect(imCap, 4);
      final p = pz(4, 5);
      for (var i = 0; i < imCap * 2; i += 2) {
        p.addConstraint(im('$i.${i + 1}.1'));
      }
      expect(p.constraints.length, imCap);
      expect(im('16.17.1').canBeAddedTo(p), isFalse);
    });

    test('cap - 1 existing still accepts', () {
      final imCap = maxImPerPuzzle(4, 5);
      final p = pz(4, 5);
      for (var i = 0; i < (imCap - 1) * 2; i += 2) {
        p.addConstraint(im('$i.${i + 1}.1'));
      }
      final next = (imCap - 1) * 2;
      expect(im('$next.${next + 1}.1').canBeAddedTo(p), isTrue);
    });
  });

  group('uncapped slug', () {
    test('20 symmetries + one more accepted', () {
      final p = pz(5, 5);
      for (var i = 0; i < 20; i++) {
        p.addConstraint(sy('$i.1'));
      }
      expect(p.constraints.length, 20);
      expect(sy('20.1').canBeAddedTo(p), isTrue);
    });
  });

  group('conflict still refused', () {
    test('overlapping MJ borders refused, non-conflicting accepted', () {
      final p = pz(5, 5);
      p.addConstraint(mj('0.0.1.1'));
      expect(mj('0.1.1.2').canBeAddedTo(p), isFalse);
      expect(mj('1.1.2.2').canBeAddedTo(p), isTrue);
    });
  });

  group('generator end-to-end', () {
    test('emitted lines respect FM/IM caps', () {
      var lines = _generateLines(const {'FM', 'IM', 'PA'});
      if (lines.isEmpty) {
        lines = _generateLines(const {'FM', 'IM', 'PA', 'DF', 'NC'});
      }
      expect(
        lines,
        isNotEmpty,
        reason: 'no puzzle generated under either config',
      );
      for (final line in lines) {
        expect(_slugCount(line, 'FM') <= kMaxFmPerPuzzle, isTrue, reason: line);
        expect(
          _slugCount(line, 'IM') <= maxImPerPuzzle(6, 6),
          isTrue,
          reason: line,
        );
      }
    });
  });
}
