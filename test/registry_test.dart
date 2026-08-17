import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';

void main() {
  test('collapseMergedRules maps row/column pairs to their display slug', () {
    // The help modal counts distinct constraint concepts, so RC/CC
    // (line count), JR/JC (line majority) and RT/CT (transition) each
    // collapse to a single display slug.
    expect(collapseMergedRules({'RC', 'JR', 'CT'}), {'CC', 'JC', 'RT'});
  });

  test('collapseMergedRules lets unmapped slugs through unchanged', () {
    expect(collapseMergedRules({'FM', 'PA', 'GS', 'EY'}), {
      'FM',
      'PA',
      'GS',
      'EY',
    });
  });

  test('collapseMergedRules dedupes and preserves the display variant', () {
    // A puzzle may combine both orientations (RC + CC); after collapse
    // only the display slug remains.
    expect(collapseMergedRules({'RC', 'CC'}), {'CC'});
    expect(collapseMergedRules({'RC', 'CC', 'FM'}).length, 2);
  });
}
