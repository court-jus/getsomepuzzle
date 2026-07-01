// Minimal CSV line parser shared by the bin/ tools that read
// `puzzle_vectors.csv` and the stats CSVs. Handles double-quoted fields with
// embedded quotes (`""`) and commas; a quote only opens a field when it is the
// first character of that field. Trailing fields (including a trailing empty
// one) are preserved. This is intentionally tiny — the project's CSVs are
// produced by `vectorize_puzzles.dart` and never contain newlines in fields.

List<String> parseCsvLine(String line) {
  final out = <String>[];
  final buf = StringBuffer();
  bool inQuotes = false;
  for (int i = 0; i < line.length; i++) {
    final ch = line[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        buf.write(ch);
      }
    } else {
      if (ch == ',') {
        out.add(buf.toString());
        buf.clear();
      } else if (ch == '"' && buf.isEmpty) {
        inQuotes = true;
      } else {
        buf.write(ch);
      }
    }
  }
  out.add(buf.toString());
  return out;
}
