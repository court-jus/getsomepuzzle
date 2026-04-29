import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/main.dart';

void main() {
  // Use a recognisable shape so failures are easy to read at a glance.
  const sampleLine = 'v2_12_3x3_100000000_FM:11_0:0_0';

  group('parseSharedPuzzleLine', () {
    test('returns null when no args and no web URI', () {
      // Cold-start with no shared puzzle context — must yield null so the
      // caller falls back to the playlist instead of trying to open
      // garbage.
      expect(parseSharedPuzzleLine([]), isNull);
    });

    test('extracts puzzle from a web URI ?puzzle= query', () {
      // The web build's launch URL carries the line as a query param;
      // %-decoding is handled by Uri so the input here is the
      // already-encoded form a browser would receive.
      final uri = Uri.parse('https://example.com/?puzzle=$sampleLine');
      expect(parseSharedPuzzleLine([], webUri: uri), sampleLine);
    });

    test('extracts puzzle from a CLI URL argument', () {
      // Custom-scheme or HTTPS URL pasted as the first CLI arg on desktop
      // — same shape as what an OS deep-link handler would forward.
      final url =
          'https://court-jus.github.io/getsomepuzzle/?puzzle=$sampleLine';
      expect(parseSharedPuzzleLine([url]), sampleLine);
    });

    test('accepts a raw v2_ line as the first CLI argument', () {
      // Power-user path: `getsomepuzzle v2_12_3x3_..._0` — the line is
      // recognised by its `v2_` prefix without needing URL wrapping.
      expect(parseSharedPuzzleLine([sampleLine]), sampleLine);
    });

    test('webUri takes precedence over CLI when both are present', () {
      // Conventional priority on mixed launches (rare but possible on web
      // platforms that also surface argv): the URL the user actually
      // clicked wins.
      final web = Uri.parse('https://example.com/?puzzle=$sampleLine');
      final other = 'v2_12_2x2_0000_FM:11_0:0_0';
      expect(parseSharedPuzzleLine([other], webUri: web), sampleLine);
    });

    test('returns null when the candidate is not a v2_ line', () {
      // Defensive: an arbitrary URL or string that doesn't carry our
      // format must not be mistaken for a puzzle. Keeps malicious or
      // accidental launches from feeding garbage into the parser.
      expect(parseSharedPuzzleLine(['random text']), isNull);
      final bogus = Uri.parse('https://example.com/?puzzle=hello');
      expect(parseSharedPuzzleLine([], webUri: bogus), isNull);
    });

    test('ignores extra CLI args beyond the first', () {
      // Any further argv slots are ignored — Flutter desktop occasionally
      // appends framework args, and we shouldn't mistake them for a
      // second puzzle.
      expect(parseSharedPuzzleLine([sampleLine, '--debug']), sampleLine);
    });
  });
}
