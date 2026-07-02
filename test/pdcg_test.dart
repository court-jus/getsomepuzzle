import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/equilibrium.dart';

void main() {
  group('PDCG equilibrium integration', () {
    // Same base line as the detectPuzzleProfile group in
    // equilibrium_test.dart: 3x3 with 7 strict fields, scenario appended.
    const base = 'v2_12_3x3_100000000_FM:11_1:122122122_0';

    test('scenario:pdcg marqueur court-circuits profile detection', () {
      // The pdcg bucket in kTargetProfile can only fill if emitted lines
      // are identified by their marqueur; without the court-circuit the
      // base line would fall through to emergent detection (FM → local)
      // and the equilibrium would re-target pdcg forever.
      expect(
        detectPuzzleProfile('${base}_scenario:pdcg'),
        ProfileCategory.pdcg,
      );
    });

    test('generationBucket keeps pdcg in its own bucket', () {
      // Emergent categories collapse into `classic` for generation
      // accounting; pdcg is a real pre-fill mode and must be counted
      // against its own 2 % target, not against classic.
      expect(generationBucket(ProfileCategory.pdcg), ProfileCategory.pdcg);
    });
  });
}
