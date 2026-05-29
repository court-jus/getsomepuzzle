/// Constraint families: a taxonomy that groups the 17 player-facing
/// constraint slugs by *deduction strategy*, orthogonal to the class
/// hierarchy in `constraints/`. Pure Dart, no imports — importable by both
/// the generator (`equilibrium.dart`) and the CLI tools in `bin/`.
///
/// The taxonomy feeds the equilibrium "composition" axis (the ordered top-3
/// families of a puzzle, see [compositionOf]) and the matching `query_corpus`
/// axis. See `docs/dev/constraint_families.md`.
library;

/// Slug → family. Must stay total over every slug in
/// `constraintRegistry` (a guard test enforces this).
const Map<String, String> kConstraintFamily = {
  // line-centric: reasons about a whole row/column line (counts, transitions,
  // parity over a line segment).
  'RC': 'line-centric',
  'RT': 'line-centric',
  'CC': 'line-centric',
  'CT': 'line-centric',
  'PA': 'line-centric',
  // local: forbidden motifs / adjacency / immediate-neighbourhood counting.
  'FM': 'local',
  'DF': 'local',
  'NC': 'local',
  'EY': 'local',
  // path / connectivity.
  'LT': 'path',
  'CH': 'path',
  // group-topology: properties of connected components (size, count, shape),
  // plus symmetry and rectangular-zone majority.
  'GS': 'group-topology',
  'GC': 'group-topology',
  'SH': 'group-topology',
  'SY': 'group-topology',
  'MJ': 'group-topology',
  // global: whole-grid quantity.
  'QA': 'global',
};

/// Fixed family order. Drives the deterministic tie-break in [compositionOf]
/// and the display order in dashboards/tables.
const List<String> kConstraintFamilies = [
  'line-centric',
  'local',
  'path',
  'group-topology',
  'global',
];

/// Virtual "empty" family used to pad a puzzle's composition up to three
/// slots when it spans fewer than three real families. Always sorts last.
const String kEmptyFamily = 'none';

/// Family of [slug], or `null` if unknown (malformed token, deprecated slug).
String? familyOf(String slug) => kConstraintFamily[slug];

/// Distinct families spanned by [slugs] (deduplicated). Order follows
/// [kConstraintFamilies].
List<String> familiesOf(Iterable<String> slugs) {
  final present = <String>{};
  for (final s in slugs) {
    final f = familyOf(s);
    if (f != null) present.add(f);
  }
  return kConstraintFamilies.where(present.contains).toList();
}

/// The puzzle's three principal families, ordered by dominance.
///
/// [slugInstances] is the list of constraint slugs **with repeats** — one
/// entry per constraint instance (not deduplicated), so a puzzle with three
/// LT constraints weighs `path` three times. Families are ranked by instance
/// count (desc), ties broken by [kConstraintFamilies] order, then the top
/// three are kept and padded with [kEmptyFamily] when fewer than three real
/// families are present. Always returns a length-3 list.
List<String> compositionOf(Iterable<String> slugInstances) {
  final counts = <String, int>{};
  for (final s in slugInstances) {
    final f = familyOf(s);
    if (f == null) continue;
    counts[f] = (counts[f] ?? 0) + 1;
  }
  final ranked = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      if (byCount != 0) return byCount;
      return kConstraintFamilies
          .indexOf(a)
          .compareTo(kConstraintFamilies.indexOf(b));
    });
  return [
    for (int i = 0; i < 3; i++) i < ranked.length ? ranked[i] : kEmptyFamily,
  ];
}

/// All valid ordered composition triples over [families] (the real families
/// in play) plus the empty padding. A real family always outranks [kEmptyFamily],
/// so empties only occupy trailing slots and the first slot is always real.
/// For `m` real families the count is `P(m,3) + P(m,2) + m` (85 when m = 5).
List<List<String>> allCompositions(List<String> families) {
  final real = kConstraintFamilies.where(families.contains).toList();
  final out = <List<String>>[];
  // 1 real + two empties.
  for (final a in real) {
    out.add([a, kEmptyFamily, kEmptyFamily]);
  }
  // 2 real (ordered) + one empty.
  for (final a in real) {
    for (final b in real) {
      if (b == a) continue;
      out.add([a, b, kEmptyFamily]);
    }
  }
  // 3 real (ordered).
  for (final a in real) {
    for (final b in real) {
      if (b == a) continue;
      for (final c in real) {
        if (c == a || c == b) continue;
        out.add([a, b, c]);
      }
    }
  }
  return out;
}
