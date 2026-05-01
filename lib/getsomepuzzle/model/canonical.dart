/// Identity-only key for matching a puzzle across format/algorithm
/// evolutions. The full line representation
/// (`v2_<domain>_<wxh>_<prefill>_<constraints>_<solution>_<complexity>[_p:...]`)
/// embeds derived fields — solution cache, complexity score, optional
/// play-state — that change over time without changing what the puzzle
/// actually *is*. Stats and dedup logic must compare puzzles by their
/// structural identity, not by their full serialization.
///
/// The canonical key drops:
///   - the version prefix (`v2_`/`v3_`/...) — formats evolve
///   - the cached solution and complexity (trailing segments)
///   - any trailing `_p:<playstate>` field
///
/// And normalizes the constraints field by:
///   - removing exact-string duplicates (first occurrence wins)
///   - sorting them lexicographically (their order has no semantic meaning)
///
/// Robust to both the legacy v2 line and the bare canonical form
/// (no version prefix, no solution/complexity tail) — that way old
/// stats lines and any line previously canonicalized both produce the
/// same key.
///
/// Pure-string: no `Puzzle` parsing, safe to call on every line at load.
String canonicalPuzzleKey(String line) {
  final parts = line.trim().split('_');
  // Skip a leading version tag (`v2`/`v3`/...) if present. The 4 fields
  // we care about (domain, wxh, prefill, constraints) come right after.
  final start = parts.isNotEmpty && _isVersionTag(parts.first) ? 1 : 0;
  if (parts.length < start + 4) return line.trim();
  final domain = parts[start];
  final dimensions = parts[start + 1];
  final prefill = parts[start + 2];
  final constraints = dedupAndSortConstraints(parts[start + 3]);
  return '${domain}_${dimensions}_${prefill}_$constraints';
}

/// Sort and dedup the constraints inside a v2 line, leaving every other
/// field — version prefix, domain, dimensions, prefill, solution,
/// complexity, optional `p:<playstate>` — verbatim. The output is still
/// a parseable v2 line; only the constraints section is canonicalized.
///
/// Intended for storage paths that must keep the v2 grammar
/// (`PuzzleData.getStat`, `bin/dedup_stats.dart`) so downstream tools
/// like `bin/analyze_stats.dart` that read positional fields keep
/// working. The runtime match key is `canonicalPuzzleKey`, not this.
String normalizeV2Line(String line) {
  final parts = line.trim().split('_');
  if (parts.length < 5) return line.trim();
  parts[4] = dedupAndSortConstraints(parts[4]);
  return parts.join('_');
}

/// Drop exact-duplicate constraints from a `;`-separated constraints
/// field (slug + params must match exactly). First occurrence wins,
/// then survivors are sorted lexicographically. Constraint order has
/// no semantic meaning, so two puzzles with the same constraint set in
/// different orders share an identity.
String dedupAndSortConstraints(String field) {
  final seen = <String>{};
  final kept = <String>[];
  for (final c in field.split(';')) {
    if (seen.add(c)) kept.add(c);
  }
  kept.sort();
  return kept.join(';');
}

bool _isVersionTag(String s) {
  if (s.length < 2 || s[0] != 'v') return false;
  return int.tryParse(s.substring(1)) != null;
}
