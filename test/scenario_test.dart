import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/equilibrium.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

void main() {
  group('Puzzle.userScenario — lazy initialiser covers empty()/clone()', () {
    test('Puzzle.empty().userScenario returns classic (no slugs)', () {
      final p = Puzzle.empty(4, 4, [CellValue.black, CellValue.white]);
      expect(p.userScenario, ProfileCategory.classic);
    });

    test('Puzzle.clone().userScenario matches original', () {
      const line = 'v2_12_4x4_2210000010000000_FM:11_1:1212121212121212_2';
      final original = Puzzle(line);
      final cloned = original.clone();
      expect(cloned.userScenario, original.userScenario);
    });
  });

  group('detectPuzzleProfile — unknown marker', () {
    // A line whose constraint slugs are non-dominant (LT + SY below
    // 0.80 threshold) and whose scenario: tag is an unknown name
    // "martian". Should fall through to emergent detection and resolve
    // to classic since no emergent group reaches threshold.
    const martianLine =
        'v2_12_4x4_1000000000000000_LT:A.0.5;SY:3.axis_'
        '1:1221221221221221_0_scenario:martian';

    test('unknown marker "martian" with non-dominant slugs → classic', () {
      expect(detectPuzzleProfile(martianLine), ProfileCategory.classic);
    });
  });

  group('detectPuzzleProfile — authoritative marqueur court-circuit', () {
    const base = 'v2_12_4x4_1000000000000000_FM:11_1:1221221221221221_0';

    test('scenario:pathBased returns pathBased immediately', () {
      expect(
        detectPuzzleProfile('${base}_scenario:pathBased'),
        ProfileCategory.pathBased,
      );
    });

    test('scenario:syBased returns syBased immediately', () {
      expect(
        detectPuzzleProfile('${base}_scenario:syBased'),
        ProfileCategory.syBased,
      );
    });

    test('scenario:sh returns sh immediately', () {
      expect(detectPuzzleProfile('${base}_scenario:sh'), ProfileCategory.sh);
    });
  });

  group('detectPuzzleProfile — court-circuit OFF for classic / unknown', () {
    // Line whose constraint field contains exactly one slug: NC.
    // detectPuzzleProfile only reads the slug prefix, so the params
    // after the colon need not be valid for instantiation.
    const ncLine = 'v2_12_4x4_1000000000000000_NC:0.1.3_1:1221221221221221_0';

    test(
      'scenario:classic + NC-dominant → minesweeper (court-circuit OFF)',
      () {
        expect(
          detectPuzzleProfile('${ncLine}_scenario:classic'),
          ProfileCategory.minesweeper,
        );
      },
    );
  });

  group('detectPuzzleProfile — emergent groups', () {
    test('NC seul ≥ threshold → minesweeper', () {
      const line = 'v2_12_4x4_0000000000000000_NC:0.1.3_1:2222222222222222_0';
      expect(detectPuzzleProfile(line), ProfileCategory.minesweeper);
    });

    test('NC + EY ≥ threshold → minesweeper', () {
      const line =
          'v2_12_4x4_0000000000000000_NC:0.1.3;EY:3.1.2_'
          '1:2222222222222222_0';
      expect(detectPuzzleProfile(line), ProfileCategory.minesweeper);
    });

    test('parasite still above 0.80 threshold → minesweeper', () {
      // 4 NC slugs + 1 FM = 4/5 = 0.80 ≥ threshold → minesweeper.
      const line =
          'v2_12_4x4_0000000000000000_NC:0.1.3;NC:1.1.3;NC:2.1.3;NC:3.1.3;'
          'FM:11_1:2222222222222222_0';
      expect(detectPuzzleProfile(line), ProfileCategory.minesweeper);
    });

    test('parasites below 0.80 threshold → classic', () {
      // 2 NC + 2 others = 2/4 = 0.50 < threshold → classic.
      const line =
          'v2_12_4x4_0000000000000000_NC:0.1.3;NC:1.1.3;FM:11;PA:0.top_'
          '1:2222222222222222_0';
      expect(detectPuzzleProfile(line), ProfileCategory.classic);
    });

    test('EY pur sans NC → classic', () {
      const line = 'v2_12_4x4_0000000000000000_EY:3.1.2_1:2222222222222222_0';
      expect(detectPuzzleProfile(line), ProfileCategory.classic);
    });

    test('CC ≥ threshold → nonogram', () {
      const line = 'v2_12_4x4_0000000000000000_CC:0.5_1:2222222222222222_0';
      expect(detectPuzzleProfile(line), ProfileCategory.nonogram);
    });

    test('RC + CT + RT mix → nonogram', () {
      const line =
          'v2_12_4x4_0000000000000000_RC:0.3;CT:0.2;RT:1.2_'
          '1:2222222222222222_0';
      expect(detectPuzzleProfile(line), ProfileCategory.nonogram);
    });

    test('DF + FM → local', () {
      const line =
          'v2_12_4x4_0000000000000000_DF:0.5;FM:11_'
          '1:2222222222222222_0';
      expect(detectPuzzleProfile(line), ProfileCategory.local);
    });

    test('GS + GC → group', () {
      const line =
          'v2_12_4x4_0000000000000000_GS:5.2;GC:5.3_'
          '1:2222222222222222_0';
      expect(detectPuzzleProfile(line), ProfileCategory.group);
    });

    test('SH présent non marqué → sh', () {
      // No scenario marker, but SH slug triggers sh.
      const shLine =
          'v2_12_4x4_0000000000000000_SH:3123;LT:A.0.5_'
          '1:2222222222222222_0';
      expect(detectPuzzleProfile(shLine), ProfileCategory.sh);
    });

    test('LT + SY non marqués → classic (no emergent group matches)', () {
      const line =
          'v2_12_4x4_0000000000000000_LT:A.0.5;SY:3.axis_'
          '1:2222222222222222_0';
      expect(detectPuzzleProfile(line), ProfileCategory.classic);
    });
  });

  group('generationBucket', () {
    test('emergent profiles collapse to classic', () {
      expect(
        generationBucket(ProfileCategory.minesweeper),
        ProfileCategory.classic,
      );
      expect(
        generationBucket(ProfileCategory.nonogram),
        ProfileCategory.classic,
      );
      expect(generationBucket(ProfileCategory.local), ProfileCategory.classic);
      expect(generationBucket(ProfileCategory.group), ProfileCategory.classic);
    });

    test('pre-fill profiles pass through unchanged', () {
      expect(
        generationBucket(ProfileCategory.classic),
        ProfileCategory.classic,
      );
      expect(generationBucket(ProfileCategory.sh), ProfileCategory.sh);
      expect(
        generationBucket(ProfileCategory.pathBased),
        ProfileCategory.pathBased,
      );
      expect(
        generationBucket(ProfileCategory.syBased),
        ProfileCategory.syBased,
      );
    });
  });

  group('Puzzle.userScenario', () {
    // Use a line from the equilibrium tests that parses successfully.
    const fmLine = 'v2_12_4x4_2210000010000000_FM:11_1:1212121212121212_2';

    test('FM-dominant puzzle gets local userScenario', () {
      final puzzle = Puzzle(fmLine);
      expect(puzzle.userScenario, ProfileCategory.local);
    });

    test('classic scenario marker with FM-dominant still yields local', () {
      // `scenario:classic` does NOT court-circuit, so emergent detection
      // re-classifies FM-dominant as `local`.
      const line = '${fmLine}_scenario:classic';
      final puzzle = Puzzle(line);
      expect(puzzle.userScenario, ProfileCategory.local);
    });

    test('pathBased scenario overrides emergent', () {
      const line = '${fmLine}_scenario:pathBased';
      final puzzle = Puzzle(line);
      // Court-circuit: pathBased is authoritative.
      expect(puzzle.userScenario, ProfileCategory.pathBased);
    });

    test('syBased scenario overrides emergent', () {
      const line = '${fmLine}_scenario:syBased';
      final puzzle = Puzzle(line);
      expect(puzzle.userScenario, ProfileCategory.syBased);
    });
  });
}
