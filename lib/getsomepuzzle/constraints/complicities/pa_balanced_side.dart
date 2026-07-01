import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/complicity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/letter_group.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/parity.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// PA + (FM | LT) complicity: a `ParityConstraint` fixes the
/// composition of one of its sides (`side.length / domain.length` of
/// each colour). For each such side we enumerate every balanced
/// colouring of the free cells, drop the ones that would violate any
/// `ForbiddenMotif` or `LetterGroup`, and either force the cells whose
/// value is identical across every survivor or prune a colour that no
/// survivor uses.
///
/// This generalises the original PA + FM complicity to also cover
/// PA + LT:
///
/// - **PA + FM (2-cell mixed FM)** — the surviving configuration on
///   an aligned PA side is the unique monotone one, so the force
///   fires on every empty cell.
/// - **PA + FM (3+ cell FM, multiple FMs)** — partial filtering;
///   each FM participates in the filter simultaneously.
/// - **PA + LT** — when two or more cells of a single LT lie on the
///   same PA side, configurations that assign different colours to
///   LT-linked cells are dropped (`LetterGroup.verify` already
///   detects this on partial states). Off-side LT cells with an
///   existing colour anchor the LT colour across the side.
/// - **Mixed FM and LT** — both filters run on every candidate;
///   complementary cuts often combine to leave a single survivor.
///
/// Domain-agnostic: the balanced-composition argument holds for any
/// domain (`targetCount = side.length / domain.length` of each
/// colour), so the enumeration is multinomial rather than binary. On a
/// 2-colour domain it reduces exactly to the original `C(n, n/2)`
/// binary set, so 2-colour behaviour is unchanged.
///
/// Side length is capped by [_maxSideLen]: 10 on a 2-colour domain
/// (`C(10, 5) = 252` configs) but only 6 on a 3+ colour domain, where
/// the multinomial blows up faster (`multinomial(6; 2,2,2) = 90`,
/// `multinomial(9; 3,3,3) = 1680`).
class PABalancedSideComplicity extends Complicity {
  /// Largest side this complicity will enumerate, given the domain
  /// size. The multinomial cost grows much faster with more colours,
  /// so the cap tightens from 10 (binary) to 6 (3+ colours).
  static int _maxSideLen(int domainSize) => domainSize >= 3 ? 6 : 10;

  /// Slug of the constraint that explains this particular deduction
  /// alongside `PA`. Set when [apply] returns a move whose dropped
  /// configurations were all rejected by the same single constraint
  /// type (FM, LT, …). Falls back to `'*'` (any) when rejections come
  /// from multiple types — or when none rejected anything (rare).
  final String _secondSlug;

  PABalancedSideComplicity([this._secondSlug = '*']);

  @override
  String serialize() => "PABalancedSideComplicity";

  @override
  (String, String) get slugs => ('PA', _secondSlug);

  @override
  bool isPresent(Puzzle puzzle) {
    final pas = puzzle.constraints.whereType<ParityConstraint>();
    if (pas.isEmpty) return false;
    final hasFm = puzzle.constraints.whereType<ForbiddenMotif>().isNotEmpty;
    final hasLt = puzzle.constraints.whereType<LetterGroup>().isNotEmpty;
    return hasFm || hasLt;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final fms = puzzle.constraints.whereType<ForbiddenMotif>().toList();
    final lts = puzzle.constraints.whereType<LetterGroup>().toList();
    if (fms.isEmpty && lts.isEmpty) return null;

    for (final pa in puzzle.constraints.whereType<ParityConstraint>()) {
      for (final side in _sideCellIndices(pa, puzzle)) {
        final move = _solveSide(side, puzzle, pa, fms, lts);
        if (move != null) return move;
      }
    }
    return null;
  }

  /// Run the enumeration on a single PA side and return either an
  /// `isImpossible` move (no surviving config), a force move (all
  /// survivors agree on a free cell), a `removeOption` move (a colour
  /// no survivor uses on a free cell), or null.
  Move? _solveSide(
    List<int> side,
    Puzzle puzzle,
    ParityConstraint pa,
    List<ForbiddenMotif> fms,
    List<LetterGroup> lts,
  ) {
    final domain = puzzle.domain;
    if (side.isEmpty || side.length % domain.length != 0) return null;
    if (side.length > _maxSideLen(domain.length)) return null;

    final current = side.map((idx) => puzzle.cellValues[idx]).toList();
    final targetCount = side.length ~/ domain.length;

    // Per-colour shortfall on this side. `need[c]` cells of colour `c`
    // still have to be placed among the free positions.
    final need = <CellValue, int>{};
    for (final color in domain) {
      final fixed = current.where((v) => v == color).length;
      if (fixed > targetCount) {
        // Existing colouring already fails the balanced composition;
        // ParityConstraint will report it. Nothing to add here.
        return null;
      }
      need[color] = targetCount - fixed;
    }

    final freePositions = <int>[];
    for (int i = 0; i < side.length; i++) {
      if (current[i] == CellValue.free) freePositions.add(i);
    }
    if (freePositions.isEmpty) return null;

    final survivors = <List<CellValue>>[];
    // Track which constraint instances rejected at least one config.
    // Used to tag the returned move so the hint UI can render
    // "PA + FM", "PA + LT" or "PA + other" rather than always "PA + *".
    final rejectingConstraints = <CanApply>{};

    _enumerateMultinomial(
      freePositions.length,
      domain,
      [for (final c in domain) need[c]!],
      (assignment) {
        final config = List<CellValue>.from(current);
        for (int i = 0; i < freePositions.length; i++) {
          config[freePositions[i]] = assignment[i];
        }
        final clone = puzzle.clone();
        for (int i = 0; i < side.length; i++) {
          if (current[i] == CellValue.free) {
            clone.cells[side[i]].setForSolver(config[i]);
          }
        }
        for (final fm in fms) {
          if (!fm.verify(clone)) {
            rejectingConstraints.add(fm);
            return;
          }
        }
        for (final lt in lts) {
          if (!lt.verify(clone)) {
            rejectingConstraints.add(lt);
            return;
          }
        }
        survivors.add(config);
      },
    );

    if (survivors.isEmpty) {
      return _tagContributors(Impossible(this), rejectingConstraints, pa);
    }
    // Partial determination on each free cell:
    //  * every survivor agrees on its value → force it;
    //  * otherwise, any colour no survivor uses (but still in the
    //    cell's options) is impossible there → prune it.
    // On a 2-colour domain a non-unanimous cell already covers both
    // colours, so the removeOption branch never fires and this reduces
    // to "force the first uniquely-determined empty cell" as before.
    for (final freePos in freePositions) {
      final used = {for (final s in survivors) s[freePos]};
      final cell = puzzle.cells[side[freePos]];
      // Combination deduction (PA × FMs/LTs): two rules in mind at
      // once. Tier 3 weight per docs/dev/complexity.md.
      if (used.length == 1) {
        // Every survivor agrees on this cell's colour. Force it — unless that
        // colour has been pruned from the cell's options (3+-colour domain),
        // in which case no allowed colour satisfies the balanced composition.
        if (cell.options.contains(used.first)) {
          return _tagContributors(
            SetValue(side[freePos], used.first, this, complexity: 3),
            rejectingConstraints,
            pa,
          );
        }
        return _tagContributors(Impossible(this), rejectingConstraints, pa);
      }
      for (final color in domain) {
        if (!used.contains(color) && cell.options.contains(color)) {
          return _tagContributors(
            RemoveOption(side[freePos], color, this, complexity: 3),
            rejectingConstraints,
            pa,
          );
        }
      }
    }
    return null;
  }

  /// Wrap [move] so its `contributors` lists the [pa] constraint and
  /// every specific constraint instance in [rejectingConstraints]. Also
  /// retag `givenBy` to a `PABalancedSideComplicity` with the unique
  /// rejector slug when all rejectors share the same slug, so the hint
  /// UI can render "PA + FM" or "PA + LT" instead of "PA + other".
  Move _tagContributors(
    Move move,
    Set<CanApply> rejectingConstraints,
    ParityConstraint pa,
  ) {
    final involved = <CanApply>[pa, ...rejectingConstraints];
    final withContribs = switch (move) {
      SetValue(:final idx, :final value, :final complexity) => SetValue(
        idx,
        value,
        this,
        complexity: complexity,
        contributors: involved,
      ),
      RemoveOption(
        :final idx,
        :final option,
        :final complexity,
        :final isForce,
        :final forceDepth,
      ) =>
        RemoveOption(
          idx,
          option,
          this,
          complexity: complexity,
          isForce: isForce,
          forceDepth: forceDepth,
          contributors: involved,
        ),
      Impossible() => Impossible(this, contributors: involved),
    };
    final slugs = rejectingConstraints.map((c) {
      if (c is Constraint) return c.slug;
      return c.serialize();
    }).toSet();
    if (slugs.length != 1) return withContribs;
    return withContribs.retag(PABalancedSideComplicity(slugs.first));
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

  /// Enumerate every assignment of [n] free positions to colours from
  /// [colors] such that colour `colors[i]` is used exactly `need[i]`
  /// times, passing each (a list of length [n], position → colour) to
  /// the callback. On a 2-colour domain with `need = [k, n - k]` this
  /// produces exactly the `C(n, k)` distinct binary configurations the
  /// old combination enumerator did.
  static void _enumerateMultinomial(
    int n,
    List<CellValue> colors,
    List<int> need,
    void Function(List<CellValue>) callback,
  ) {
    final assignment = List<CellValue>.filled(n, colors.first);
    final remaining = List<int>.from(need);
    void recur(int pos) {
      if (pos == n) {
        callback(List<CellValue>.from(assignment));
        return;
      }
      for (int ci = 0; ci < colors.length; ci++) {
        if (remaining[ci] == 0) continue;
        remaining[ci]--;
        assignment[pos] = colors[ci];
        recur(pos + 1);
        remaining[ci]++;
      }
    }

    recur(0);
  }
}
