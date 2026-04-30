import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/complicity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/parity.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// PA + FM complicity (generalised): a `ParityConstraint` fixes the
/// composition of one of its sides (n/2 of each colour). For each
/// such side we enumerate every balanced colouring of the free cells,
/// drop the ones that would violate any `ForbiddenMotif`, and force
/// the cells whose value is identical across every survivor.
///
/// This generalises the original 2-cell-FM monotonicity argument:
///
/// - 2-cell mixed FM (`FM:12`, `FM:21`, `FM:1.2`, `FM:2.1`) — the
///   surviving configuration on an aligned PA side is the unique
///   monotone one, so the force fires on every empty cell.
/// - 3+ cell FM (`FM:1.2.2`, `FM:11.21.11`, …) — partial filtering;
///   the force fires only on cells that take the same value in every
///   surviving configuration. Useful in chained reasoning: another
///   constraint colouring one cell often collapses the survivor set
///   to a single configuration.
/// - Multiple FMs of any sizes — they all participate in the filter
///   simultaneously, so the complicity captures combinations that no
///   single FM alone would catch.
///
/// Domain restriction: the parity-as-colour-counter argument only
/// holds when the domain is exactly `{1, 2}`.
///
/// Side length is capped at [_maxSideLen] = 10 (so up to 10×10 grids
/// are handled in full). `C(10, 5) = 252` configurations is the
/// practical upper bound on enumeration cost per side.
class PAFMComplicity extends Complicity {
  static const int _maxSideLen = 10;

  @override
  String serialize() => "PAFMComplicity";

  @override
  bool isPresent(Puzzle puzzle) {
    if (!_domainIsOneTwo(puzzle)) return false;
    final pas = puzzle.constraints.whereType<ParityConstraint>();
    if (pas.isEmpty) return false;
    return puzzle.constraints.whereType<ForbiddenMotif>().isNotEmpty;
  }

  @override
  Move? apply(Puzzle puzzle) {
    if (!_domainIsOneTwo(puzzle)) return null;
    final fms = puzzle.constraints.whereType<ForbiddenMotif>().toList();
    if (fms.isEmpty) return null;

    for (final pa in puzzle.constraints.whereType<ParityConstraint>()) {
      for (final side in _sideCellIndices(pa, puzzle)) {
        final move = _solveSide(side, puzzle, fms);
        if (move != null) return move;
      }
    }
    return null;
  }

  /// Run the enumeration on a single PA side and return either an
  /// `isImpossible` move (no surviving config), a force move (all
  /// survivors agree on at least one free cell), or null.
  Move? _solveSide(List<int> side, Puzzle puzzle, List<ForbiddenMotif> fms) {
    if (side.isEmpty || side.length.isOdd) return null;
    if (side.length > _maxSideLen) return null;

    final current = side.map((idx) => puzzle.cellValues[idx]).toList();
    final fixed1 = current.where((v) => v == 1).length;
    final fixed2 = current.where((v) => v == 2).length;
    final half = side.length ~/ 2;
    if (fixed1 > half || fixed2 > half) {
      // Existing colouring already fails the parity composition;
      // ParityConstraint will report it. Nothing to add here.
      return null;
    }

    final freePositions = <int>[];
    for (int i = 0; i < side.length; i++) {
      if (current[i] == 0) freePositions.add(i);
    }
    if (freePositions.isEmpty) return null;
    final ones = half - fixed1;
    if (ones < 0 || ones > freePositions.length) return null;

    final survivors = <List<int>>[];
    _enumerate(freePositions.length, ones, (selected) {
      final selSet = selected.toSet();
      final config = List<int>.from(current);
      for (int i = 0; i < freePositions.length; i++) {
        config[freePositions[i]] = selSet.contains(i) ? 1 : 2;
      }
      final clone = puzzle.clone();
      for (int i = 0; i < side.length; i++) {
        if (current[i] == 0) {
          clone.cells[side[i]].setForSolver(config[i]);
        }
      }
      for (final fm in fms) {
        if (!fm.verify(clone)) return; // configuration violates an FM
      }
      survivors.add(config);
    });

    if (survivors.isEmpty) {
      return Move(0, 0, this, isImpossible: this);
    }
    // Partial determination: any free cell that takes the same value
    // in every surviving configuration is forced. With a single
    // survivor this collapses to "force every empty cell on the side".
    for (final freePos in freePositions) {
      final v0 = survivors.first[freePos];
      if (survivors.every((s) => s[freePos] == v0)) {
        // Combination deduction (PA × FMs): two rules in mind at once.
        // Tier 3 weight per docs/dev/complexity.md.
        return Move(side[freePos], v0, this, complexity: 3);
      }
    }
    return null;
  }

  /// Cells covered by [pa] for each of its sides, in natural reading
  /// order (left→right for horizontal sides, top→bottom for vertical).
  /// Returns 1 list for `left`/`right`/`top`/`bottom`, 2 for the
  /// `horizontal` and `vertical` variants.
  static List<List<int>> _sideCellIndices(ParityConstraint pa, Puzzle puzzle) {
    final anchor = pa.indices.first;
    final w = puzzle.width;
    final ridx = anchor ~/ w;
    final cidx = anchor % w;
    final List<List<int>> result = [];
    if (pa.side == 'left' || pa.side == 'horizontal') {
      result.add([for (int c = 0; c < cidx; c++) ridx * w + c]);
    }
    if (pa.side == 'right' || pa.side == 'horizontal') {
      result.add([for (int c = cidx + 1; c < w; c++) ridx * w + c]);
    }
    if (pa.side == 'top' || pa.side == 'vertical') {
      result.add([for (int r = 0; r < ridx; r++) r * w + cidx]);
    }
    if (pa.side == 'bottom' || pa.side == 'vertical') {
      result.add([for (int r = ridx + 1; r < puzzle.height; r++) r * w + cidx]);
    }
    return result;
  }

  /// True when [puzzle.domain] is exactly {1, 2}: parity's odd/even
  /// split coincides with colour counting only on that domain.
  static bool _domainIsOneTwo(Puzzle puzzle) {
    final d = puzzle.domain;
    return d.length == 2 && d.contains(1) && d.contains(2);
  }

  /// Enumerate every k-combination of indices in [0..n) and pass each
  /// (as a sorted ascending list) to the callback.
  static void _enumerate(int n, int k, void Function(List<int>) callback) {
    if (k < 0 || k > n) return;
    final selection = <int>[];
    void recur(int start, int rem) {
      if (rem == 0) {
        callback(List<int>.from(selection));
        return;
      }
      for (int i = start; i <= n - rem; i++) {
        selection.add(i);
        recur(i + 1, rem - 1);
        selection.removeLast();
      }
    }

    recur(0, k);
  }
}
