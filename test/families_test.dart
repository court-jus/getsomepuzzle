import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/families.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';

void main() {
  group('constraint family taxonomy', () {
    test(
      'every registry slug has a family (guard against new constraints)',
      () {
        // If a new constraint is added to the registry without a family entry,
        // this fails — forcing the taxonomy to stay in sync with the registry.
        for (final slug in constraintSlugs) {
          expect(
            kConstraintFamily.containsKey(slug),
            isTrue,
            reason: 'slug $slug has no family in kConstraintFamily',
          );
        }
      },
    );

    test('the map only references declared families', () {
      // No typos / stray family names: every value is one of the five.
      for (final family in kConstraintFamily.values) {
        expect(kConstraintFamilies.contains(family), isTrue, reason: family);
      }
    });

    test('familiesOf deduplicates and ignores unknown slugs', () {
      // Two path slugs + one bogus token → just the single distinct family.
      expect(familiesOf(['LT', 'CH', 'ZZ']), ['path']);
    });
  });

  group('compositionOf', () {
    test('ranks families by constraint-instance count, descending', () {
      // 3 LT (path), 2 PA (line-centric), 1 FM (local) → dominance order.
      final comp = compositionOf(['LT', 'LT', 'LT', 'PA', 'PA', 'FM']);
      expect(comp, ['path', 'line-centric', 'local']);
    });

    test('pads with the empty family below three real families', () {
      // One real family → first slot real, the rest padded.
      expect(compositionOf(['PA', 'RC']), [
        'line-centric',
        kEmptyFamily,
        kEmptyFamily,
      ]);
      // Two real families → one trailing empty.
      expect(compositionOf(['LT', 'FM', 'FM']), [
        'local',
        'path',
        kEmptyFamily,
      ]);
    });

    test('breaks count ties by fixed family order, deterministically', () {
      // local and path tie at one instance each; line-centric (PA) leads.
      // Tie resolved by kConstraintFamilies index: local before path.
      expect(compositionOf(['PA', 'PA', 'FM', 'LT']), [
        'line-centric',
        'local',
        'path',
      ]);
    });

    test('always returns three slots, even for a single constraint', () {
      expect(compositionOf(['QA']), ['global', kEmptyFamily, kEmptyFamily]);
    });
  });

  group('allCompositions', () {
    test('enumerates 85 triples for the full 5-family universe', () {
      // P(5,3)=60 (three real) + P(5,2)=20 (two real + empty) + 5 (one real +
      // two empties) = 85.
      expect(allCompositions(kConstraintFamilies).length, 85);
    });

    test('every triple starts with a real family and empties only trail', () {
      for (final t in allCompositions(kConstraintFamilies)) {
        expect(t.length, 3);
        expect(t.first, isNot(kEmptyFamily));
        // Once an empty appears, all following slots are empty.
        var seenEmpty = false;
        for (final f in t) {
          if (f == kEmptyFamily) seenEmpty = true;
          if (seenEmpty) expect(f, kEmptyFamily);
        }
      }
    });
  });
}
