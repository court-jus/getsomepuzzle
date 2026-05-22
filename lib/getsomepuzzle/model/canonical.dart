import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

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
/// **Rotation invariance:** the screen-orientation auto-rotation feature
/// can swap a puzzle for its 90° clockwise rotation at render time. To
/// keep the same stats entry across both orientations the key must be
/// the same for L and `L.rotated()`. Two keys aren't enough — when L's
/// 180° rotation happens to be lex-smaller, comparing only `{L, rot(L)}`
/// vs `{rot(L), rot²(L)}` from the other side picks different mins.
/// We enumerate the full orbit of 4 rotations and return the lex-smallest
/// identity key — which is then invariant under any rotation.
///
/// Robust to both the legacy v2 line and the bare canonical form
/// (no version prefix, no solution/complexity tail) — that way old
/// stats lines and any line previously canonicalized both produce the
/// same key.
String canonicalPuzzleKey(String line) {
  final base = _identityKey(line);
  if (base == null) return line.trim();
  final orbitMin = _orbitMinIdentityKey(line);
  return orbitMin ?? base;
}

/// Compute the bare identity key for a v2 line: `domain_dim_prefill_constraints`,
/// with constraints deduped and sorted. Returns `null` if the line is
/// malformed enough that the four required fields can't be extracted.
String? _identityKey(String line) {
  final parts = line.trim().split('_');
  // Skip a leading version tag (`v2`/`v3`/...) if present. The 4 fields
  // we care about (domain, wxh, prefill, constraints) come right after.
  final start = parts.isNotEmpty && _isVersionTag(parts.first) ? 1 : 0;
  if (parts.length < start + 4) return null;
  final domain = parts[start];
  final dimensions = parts[start + 1];
  final prefill = parts[start + 2];
  final constraints = dedupAndSortConstraints(parts[start + 3]);
  return '${domain}_${dimensions}_${prefill}_$constraints';
}

/// Compute the lex-smallest identity key across the puzzle's full
/// rotation orbit (4 rotations). Goes through `Puzzle(...).rotated()`,
/// which is more expensive than `_identityKey` but only runs at
/// canonicalization time (stats writes and puzzle open) — never inside
/// the solver hot path. Returns `null` if the line can't be parsed.
String? _orbitMinIdentityKey(String line) {
  try {
    String? best = _identityKey(line);
    if (best == null) return null;
    var p = Puzzle(line);
    for (int i = 0; i < 3; i++) {
      p = p.rotated();
      final k = _identityKey(p.lineRepresentation);
      if (k != null && k.compareTo(best!) < 0) best = k;
    }
    return best;
  } catch (_) {
    return null;
  }
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
///
/// Also drops every `TX:*` entry: the legacy `HelpText` constraint was
/// pedagogical metadata (tutorial markdown reference) that doesn't
/// affect the puzzle's identity, and is removed from the codebase. We
/// keep this filter here so old stats lines with `TX:` still match the
/// migrated TX-stripped puzzle lines, and so any leftover `TX:` in a
/// re-imported playlist canonicalizes the same way.
String dedupAndSortConstraints(String field) {
  final seen = <String>{};
  final kept = <String>[];
  for (final c in field.split(';')) {
    if (c.startsWith('TX:') || c == 'TX') continue;
    if (seen.add(c)) kept.add(c);
  }
  kept.sort();
  return kept.join(';');
}

bool _isVersionTag(String s) {
  if (s.length < 2 || s[0] != 'v') return false;
  return int.tryParse(s.substring(1)) != null;
}

/// Accept the three representations a user can paste and return a v2
/// line that `Puzzle`/`PuzzleData` constructors can parse:
///   - share URL `https://.../?puzzle=v2_...` → query param value
///   - bare canonical `<domain>_<wxh>_<prefill>_<constraints>` (no
///     version prefix, no solution/cplx tail — what `canonicalPuzzleKey`
///     and the `Puzzle loaded` log emit) → prefixed with `v2_`
///   - full v2 line `v2_...` (or any `vN_...` version tag) → returned
///     verbatim
///
/// Returns `null` if the input is empty or doesn't structurally look
/// like any of the three formats. Callers can use that to silently
/// ignore partial input (e.g. a TextField onChanged that fires on every
/// keystroke).
String? normalizeToV2Line(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  // 1. URL form: extract the `puzzle` query parameter and recurse so
  //    the extracted value goes through the canonical/v2 detection too.
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    try {
      final fromUrl = Uri.parse(trimmed).queryParameters['puzzle'];
      if (fromUrl != null && fromUrl.isNotEmpty) {
        return normalizeToV2Line(fromUrl);
      }
    } catch (_) {}
    return null;
  }

  final parts = trimmed.split('_');
  // 2. Already-versioned line — let the existing parser handle it.
  if (parts.isNotEmpty && _isVersionTag(parts.first)) return trimmed;

  // 3. Bare canonical: need at least domain, wxh, prefill, constraints.
  if (parts.length < 4) return null;
  final dim = parts[1];
  if (!RegExp(r'^\d+x\d+$').hasMatch(dim)) return null;
  // Domain and prefill must be all digits.
  if (!RegExp(r'^\d+$').hasMatch(parts[0])) return null;
  if (!RegExp(r'^\d+$').hasMatch(parts[2])) return null;
  // Constraint field must contain at least one `slug:params` token.
  if (!parts[3].contains(':')) return null;
  return 'v2_$trimmed';
}
