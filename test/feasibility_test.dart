import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/feasibility.dart';

void main() {
  group('attemptScenarioKey', () {
    test('domain 2 keeps the bare scenario, domain 3 appends +d3', () {
      // The bare form is what every pre-domain-axis key used — keeping it
      // for dom-2 is what makes historical blacklist entries stay valid,
      // while the suffix separates the dom-3 population (very different
      // success rates) from dom-2 in the blacklist.
      expect(attemptScenarioKey('classic', 2), 'classic');
      expect(attemptScenarioKey('sh', 2), 'sh');
      expect(attemptScenarioKey('classic', 3), 'classic+d3');
      expect(attemptScenarioKey('sh', 3), 'sh+d3');
    });
  });

  group('readPersistentBlacklist', () {
    // CSV rows follow `_statsColumns` in bin/generate.dart:
    //   0=date 1=commit 2=worker 3=phase 4=target_key 5=width 6=height
    //   7=ntypes_intended 8=preferred_slugs 9=allowed_slugs 10=scenario
    //   11=outcome 12=reason 13=duration_ms 14=level 15=puzzle_line
    //   16=slug_deficits 17=domain (absent on historical rows).
    const header =
        'date,commit,worker,phase,target_key,width,height,ntypes_intended,'
        'preferred_slugs,allowed_slugs,scenario,outcome,reason,duration_ms,'
        'level,puzzle_line,slug_deficits,domain';

    // A failure row for the combo (slug:CH, {CH}, classic, 4x4). The quoted
    // puzzle_line carries an embedded comma on purpose: a naive `,`-split
    // would shift the trailing domain column, so this also pins the
    // quote-aware row parsing.
    String row({String? domain}) =>
        '2026-01-01T00:00:00Z,abc123,0,equilibrium,slug:CH,4,4,1,CH,,classic,'
        'failure,ratioTooHigh,1000,,"v2_12_4x4_x,y",'
        '${domain == null ? '' : ',$domain'}';

    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('feasibility_test'));
    tearDown(() => tmp.deleteSync(recursive: true));

    String writeCsv(List<String> lines) {
      final path = '${tmp.path}/generator_stats.csv';
      File(path).writeAsStringSync(lines.join('\n'));
      return path;
    }

    final comboKey = AttemptKey(
      targetKey: 'slug:CH',
      sortedSlugs: ['CH'],
      scenario: 'classic',
      sizeBucket: bucketForArea(4, 4),
    ).serialized;

    test('historical rows without a domain column aggregate as domain 2', () {
      // Rows written before the domain axis existed have 17 fields and were
      // all dom-2 — they must re-serialize to the exact same unsuffixed key
      // as before, so existing blacklist knowledge carries over unchanged.
      final path = writeCsv([header, row(), row()]);
      final black = readPersistentBlacklist(csvPath: path, minAttempts: 2);
      expect(black, {comboKey});
    });

    test('domain-3 rows never aggregate with the same dom-2 combo', () {
      // One dom-2 and one dom-3 failure on an otherwise identical combo:
      // with minAttempts=2 neither population reaches the threshold on its
      // own — proof the two rows landed in distinct buckets.
      final path = writeCsv([header, row(domain: '2'), row(domain: '3')]);
      expect(readPersistentBlacklist(csvPath: path, minAttempts: 2), isEmpty);
      // At minAttempts=1 both buckets surface, under their distinct keys.
      final black = readPersistentBlacklist(csvPath: path, minAttempts: 1);
      expect(black, {comboKey, comboKey.replaceFirst('classic', 'classic+d3')});
    });
  });
}
