import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';

void main() {
  test('defaultDomain stays in sync with fullDomain (first two entries)', () {
    // Dart const expressions can't index a const list, so we can't write
    // `const defaultDomain = [fullDomain[0], fullDomain[1]]`. The constants
    // are spelled out as literals in `cell.dart`; this test makes the
    // intended relationship machine-checkable.
    expect(defaultDomain, fullDomain.sublist(0, 2));
  });

  test('fullDomain is the canonical colour order', () {
    expect(fullDomain, [CellValue.black, CellValue.white, CellValue.purple]);
  });
}
