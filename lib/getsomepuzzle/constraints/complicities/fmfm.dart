import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/complicity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// FM + FM complicity.
///
/// Two `ForbiddenMotif`s with the same shape that differ in exactly
/// **one** cell, where the two values cover the entire domain, can
/// be combined into a stronger forbidden motif: the combined motif
/// has a wildcard at the diverging position. The synthesized motif
/// keeps the same dimensions as the originals — it is *not*
/// equivalent to a smaller motif, because it still requires the full
/// pattern window to fit inside the grid (so it will not fire on
/// rows / columns where the original FMs could not have fired
/// either).
///
/// Example: `FM:2.2.1` + `FM:1.2.1` → synthesized `FM:0.2.1`. The
/// 3-cell vertical pattern `(?, 2, 1)` is forbidden anywhere a
/// 3-cell vertical window fits, which on a 3-tall grid means rows
/// 0–2; on a 5-tall grid, rows 0–2 to 2–4.
///
/// The synthesized FMs are **not** added to the puzzle's constraint
/// list (they would clutter the player view). Instead the complicity
/// runs them at apply time and attributes the resulting moves to
/// itself, so the eventual hint UI can label them as
/// "deduced by combining two forbidden motifs".
///
/// Synthesis is iterated to a fixed point (a synthesized FM can in
/// turn combine with another existing FM). The number of synthesized
/// motifs is capped at [_maxSynth] to guard against blow-up.
class FMFMComplicity extends Complicity {
  static const int _maxSynth = 50;

  /// Nodes synthesized for the current puzzle, populated by `isPresent`
  /// and reused by `apply`. Each node carries the synthesized FM and
  /// the set of *original* FMs whose combination produced it.
  List<_SynthNode> _synthesized = const [];

  @override
  String serialize() => "FMFMComplicity";

  @override
  (String, String) get slugs => ('FM', 'FM');

  @override
  bool isPresent(Puzzle puzzle) {
    final fms = puzzle.constraints.whereType<ForbiddenMotif>().toList();
    if (fms.length < 2) return false;
    _synthesized = _synthesizeAll(fms, puzzle.domain);
    return _synthesized.isNotEmpty;
  }

  @override
  Move? apply(Puzzle puzzle) {
    for (final node in _synthesized) {
      final move = node.fm.apply(puzzle);
      if (move == null) continue;
      // Re-attribute the move to the complicity itself; the
      // synthesized FM is internal and must not surface in hints.
      // Tier 4 — the player has to recognise the shared structure
      // of two FMs and combine them mentally.
      return switch (move) {
        SetValue(:final idx, :final value) => SetValue(
          idx,
          value,
          this,
          complexity: 4,
          contributors: node.origins,
        ),
        RemoveOption(:final idx, :final option) => RemoveOption(
          idx,
          option,
          this,
          complexity: 4,
          contributors: node.origins,
        ),
        Impossible() => Impossible(this, contributors: node.origins),
      };
    }
    return null;
  }

  /// Iteratively combine pairs of FMs that differ in exactly one
  /// position whose two values cover the domain. Stops at a fixed
  /// point or when [_maxSynth] synthesized FMs have been produced.
  static List<_SynthNode> _synthesizeAll(
    List<ForbiddenMotif> fms,
    List<CellValue> domain,
  ) {
    final result = <_SynthNode>[];
    final pool = <_SynthNode>[
      for (final f in fms) _SynthNode(f, [f]),
    ];
    final seen = <String>{for (final f in fms) f.serialize()};

    bool changed = true;
    while (changed && result.length < _maxSynth) {
      changed = false;
      for (int i = 0; i < pool.length; i++) {
        for (int j = i + 1; j < pool.length; j++) {
          final synth = _trySynthesize(pool[i], pool[j], domain);
          if (synth == null) continue;
          if (!seen.add(synth.fm.serialize())) continue;
          pool.add(synth);
          result.add(synth);
          changed = true;
          if (result.length >= _maxSynth) return result;
        }
      }
    }
    return result;
  }

  /// Returns the synthesized FM (with its merged origins) if [a] and
  /// [b] differ in exactly one cell whose values cover the [domain],
  /// else null.
  static _SynthNode? _trySynthesize(
    _SynthNode a,
    _SynthNode b,
    List<CellValue> domain,
  ) {
    final f1 = a.fm;
    final f2 = b.fm;
    if (f1.motif.length != f2.motif.length) return null;
    if (f1.motif[0].length != f2.motif[0].length) return null;

    int? diffR;
    int? diffC;
    CellValue? v1, v2;
    for (int r = 0; r < f1.motif.length; r++) {
      for (int c = 0; c < f1.motif[0].length; c++) {
        if (f1.motif[r][c] == f2.motif[r][c]) continue;
        if (diffR != null) return null; // more than one diff
        diffR = r;
        diffC = c;
        v1 = f1.motif[r][c];
        v2 = f2.motif[r][c];
      }
    }
    if (diffR == null) return null; // identical
    if (v1 == CellValue.free || v2 == CellValue.free) {
      return null;
    } // one side is already wildcard
    final values = <CellValue>{v1!, v2!};
    if (values.length != domain.length) {
      return null;
    }
    for (final d in domain) {
      if (!values.contains(d)) {
        return null;
      }
    }

    final newMotif = f1.motif.map((row) => List<CellValue>.from(row)).toList();
    newMotif[diffR][diffC!] = CellValue.free;
    final paramStr = newMotif
        .map((row) => row.map(cellValueToString).join(''))
        .join('.');
    // Merge origins from both parents (remove duplicates via LinkedHashSet
    // order-preserving semantics — we use the List uniqueness guarantee
    // since every origin is a distinct object).
    final mergedOrigins = <ForbiddenMotif>[
      ...a.origins,
      ...b.origins.where((o) => !a.origins.contains(o)),
    ];
    return _SynthNode(ForbiddenMotif(paramStr), mergedOrigins);
  }
}

/// A synthesized FM together with the original (puzzle-declared) FMs
/// whose combination chain produced it.
class _SynthNode {
  final ForbiddenMotif fm;
  final List<ForbiddenMotif> origins;

  const _SynthNode(this.fm, this.origins);
}
