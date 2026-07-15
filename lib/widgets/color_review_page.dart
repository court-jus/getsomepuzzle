import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/bounding_box.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/chain.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/column_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/different_from.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/eyes_constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/group_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/group_size.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/implication.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/letter_group.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/majority.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/parity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/neighbor_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/row_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/shape.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/symmetry.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/to_flutter.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/transition_row.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/transition_column.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/app_theme.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/constraints/bounding_box.dart';
import 'package:getsomepuzzle/widgets/constraints/chain.dart';
import 'package:getsomepuzzle/widgets/constraints/column_count.dart';
import 'package:getsomepuzzle/widgets/constraints/group_count.dart';
import 'package:getsomepuzzle/widgets/constraints/motif.dart';
import 'package:getsomepuzzle/widgets/constraints/quantity.dart';
import 'package:getsomepuzzle/widgets/constraints/row_count.dart';
import 'package:getsomepuzzle/widgets/constraints/transition.dart';
import 'package:getsomepuzzle/widgets/puzzle.dart';

enum _ConstraintState { normal, grayedOut, invalid, highlighted }

const _kPrevSize = 56.0;

const _stateLabels = {
  _ConstraintState.normal: 'Normal',
  _ConstraintState.grayedOut: 'Grisé',
  _ConstraintState.invalid: 'Invalide',
  _ConstraintState.highlighted: 'Highlighté',
};

const _domainColors = [
  CellValue.free,
  CellValue.black,
  CellValue.white,
  CellValue.purple,
];

String _colorLetter(CellValue v) {
  switch (v) {
    case CellValue.black: return 'B';
    case CellValue.white: return 'W';
    case CellValue.purple: return 'P';
    case CellValue.free: return '-';
  }
}

Color _cellBg(PuzzleColors pc, CellValue v) {
  switch (v) {
    case CellValue.black: return pc.cellBgBlack;
    case CellValue.white: return pc.cellBgWhite;
    case CellValue.purple: return pc.cellBgPurple;
    case CellValue.free: return pc.cellBgUndecided;
  }
}

Color _cellFg(PuzzleColors pc, CellValue v) {
  switch (v) {
    case CellValue.black: return pc.cellFgBlack;
    case CellValue.white: return pc.cellFgWhite;
    case CellValue.purple: return pc.cellFgPurple;
    case CellValue.free: return pc.cellFgUndecided;
  }
}

Color _constraintFg(PuzzleColors pc, Constraint c) {
  final refs = c.referencedColors;
  if (refs.contains(CellValue.black)) return pc.cellFgBlack;
  if (refs.contains(CellValue.white)) return pc.cellFgWhite;
  if (refs.contains(CellValue.purple)) return pc.cellFgPurple;
  return pc.cellFgUndecided;
}

// ---- Section 1 — top-bar / zone constraints ----

Iterable<(String slug, List<Constraint> variants)> _s1Constraints() sync* {
  yield ('BB', [
    for (final c in ['1', '2', '3'])
      BoundingBoxConstraint('$c.3.3'),
  ]);
  yield ('CC', [
    for (final c in ['1', '2', '3'])
      ColumnCountConstraint('0.$c.3'),
  ]);
  yield ('CH', [
    for (final c in ['1', '2', '3'])
      ChainConstraint('$c.top.bottom'),
  ]);
  yield ('CT', [ColumnTransitionConstraint('0.3')]);
  yield ('FM', [ForbiddenMotif('12.30')]);
  yield ('GC', [
    for (final c in ['1', '2', '3'])
      GroupCountConstraint('$c.2'),
  ]);
  yield ('MJ', [
    for (final c in ['1', '2', '3'])
      MajorityConstraint('0.0.1.1.$c'),
  ]);
  yield ('QA', [
    for (final c in ['1', '2', '3'])
      QuantityConstraint('$c.3'),
  ]);
  yield ('RC', [
    for (final c in ['1', '2', '3'])
      RowCountConstraint('0.$c.3'),
  ]);
  yield ('RT', [RowTransitionConstraint('0.3')]);
  yield ('SH', [
    for (final c in ['1', '2', '3'])
      ShapeConstraint('$c$c'),
  ]);
}

// ---- Section 2 — in-cell constraints ----

Iterable<
  (
    String slug,
    bool hasColour,
    List<Constraint> constraints,
  )
> _s2Constraints() sync* {
  yield ('DF', false, [DifferentFromConstraint('0.right')]);
  yield ('EY', true, [
    for (final c in ['1', '2', '3'])
      EyesConstraint('0.$c.2') as Constraint,
  ]);
  yield ('GS', false, [GroupSize('0.3')]);
  yield ('IM', true, [
    for (final c in ['1', '2', '3'])
      ImplicationConstraint('0.1.$c') as Constraint,
  ]);
  yield ('LT', false, [LetterGroup('B.0.0')]);
  yield ('NC', true, [
    for (final c in ['1', '2', '3'])
      NeighborCountConstraint('0.$c.1') as Constraint,
  ]);
  yield ('PA', false, [ParityConstraint('0.left')]);
  yield ('SY', false, [SymmetryConstraint('0.2')]);
}

// ---- mini-puzzle helpers ----

bool _needsMiniPuzzle(String slug) =>
    slug == 'MJ' || slug == 'DF' || slug == 'IM';

(int w, int h) _miniDims(Constraint c) {
  // MJ needs a 2×2 zone; DF and IM fit in 2×1.
  return c is MajorityConstraint ? (2, 2) : (2, 1);
}

Puzzle _miniPuzzle(Constraint c) {
  final (w, h) = _miniDims(c);
  final puzzle = Puzzle.empty(w, h, fullDomain);
  puzzle.addConstraint(c);
  // check() overrides isValid with verify(puzzle) — save and restore so the
  // state toggle keeps control of the display flags.
  final savedValid = c.isValid;
  final savedComplete = c.isComplete;
  final savedHighlighted = c.isHighlighted;
  puzzle.check();
  c.isValid = savedValid;
  c.isComplete = savedComplete;
  c.isHighlighted = savedHighlighted;
  return puzzle;
}

// ---- main page ----

class ColorReviewPage extends StatefulWidget {
  const ColorReviewPage({super.key});

  @override
  State<ColorReviewPage> createState() => _ColorReviewPageState();
}

class _ColorReviewPageState extends State<ColorReviewPage> {
  bool _isDark = false;
  _ConstraintState _state = _ConstraintState.normal;

  late final List<(String slug, List<Constraint> variants)> _s1;
  late final List<(String slug, bool hasColour, List<Constraint> constraints)>
      _s2;
  final List<Constraint> _allConstraints = [];
  Puzzle? _demoPuzzle;

  @override
  void initState() {
    super.initState();
    _demoPuzzle = Puzzle(
      'v2_123_5x4_00010000000000000000_'
      'CC:3.2.1;DF:10.down;EY:14.3.2;EY:5.1.2;'
      'FM:31.01;GS:16.1;GS:9.3;LT:B.13.3;'
      'NC:14.2.1;NC:18.1.2;PA:17.top;QA:3.7;'
      'RC:1.2.2;RC:2.3.3;SY:2.3'
      '_1:13213221131331332122_31',
    )..check();
    _s1 = _s1Constraints().toList();
    _s2 = _s2Constraints().toList();
    for (final (_, variants) in _s1) {
      _allConstraints.addAll(variants);
    }
    for (final (_, _, list) in _s2) {
      _allConstraints.addAll(list);
    }
    _applyState();
  }

  void _applyState() {
    for (final c in _allConstraints) {
      switch (_state) {
        case _ConstraintState.normal:
          c.isValid = true;
          c.isHighlighted = false;
          c.isComplete = false;
        case _ConstraintState.grayedOut:
          c.isValid = true;
          c.isHighlighted = false;
          c.isComplete = true;
        case _ConstraintState.invalid:
          c.isValid = false;
          c.isHighlighted = true;
          c.isComplete = false;
        case _ConstraintState.highlighted:
          c.isValid = true;
          c.isHighlighted = true;
          c.isComplete = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _isDark ? darkTheme : lightTheme,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Review des couleurs'),
          actions: [
            Switch(
              value: _isDark,
              onChanged: (v) => setState(() => _isDark = v),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              _buildStateSelector(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    _sectionHeader('Contraintes avec couleur'),
                    ..._buildS1(),
                    _sectionHeader('Contraintes en cellule'),
                    ..._buildS2(),
                    _sectionHeader('Puzzle de démonstration'),
                    _buildDemoPuzzle(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStateSelector() {
    return Container(
      width: double.infinity,
      color: _isDark ? Colors.grey.shade900 : Colors.grey.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Text('État:  ', style: TextStyle(fontWeight: FontWeight.w600)),
            for (final s in _ConstraintState.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: FilterChip(
                  label: Text(_stateLabels[s]!),
                  selected: _state == s,
                  onSelected: (_) {
                    setState(() {
                      _state = s;
                      _applyState();
                    });
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }

  // ----------------------------------------------------------------
  // Section 1
  // ----------------------------------------------------------------

  List<Widget> _buildS1() {
    final l = AppLocalizations.of(context)!;
    final out = <Widget>[];
    for (final (slug, variants) in _s1) {
      out.add(ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text('$slug — ${_s1Label(slug, l)}'),
      ));
      out.add(Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
        child: _s1Row(slug, variants),
      ));
    }
    return out;
  }

  Widget _s1Row(String slug, List<Constraint> variants) {
    if (_needsMiniPuzzle(slug)) {
      return Wrap(spacing: 8, runSpacing: 4, children: [
        for (final c in variants) _miniPuzzleWidget(c),
      ]);
    }
    return Wrap(spacing: 16, runSpacing: 4, children: [
      for (final c in variants) _s1Tile(slug, c),
    ]);
  }

  Widget _s1Tile(String slug, Constraint c) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_variantLabel(c),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        SizedBox(
          width: _kPrevSize,
          height: _kPrevSize,
          child: _s1Widget(slug, c),
        ),
      ],
    );
  }

  Widget _s1Widget(String slug, Constraint c) {
    switch (slug) {
      case 'BB':
        return BoundingBoxWidget(
            constraint: c as BoundingBoxConstraint, cellSize: _kPrevSize);
      case 'CC':
        return ColumnCountWidget(
            constraint: c as ColumnCountConstraint, cellSize: _kPrevSize);
      case 'CH':
        return ChainWidget(
            constraint: c as ChainConstraint,
            fgcolor: _constraintFg(
                Theme.of(context).extension<PuzzleColors>()!, c),
            cellSize: _kPrevSize);
      case 'CT':
        return TransitionWidget(
            constraint: c as ColumnTransitionConstraint,
            cellSize: _kPrevSize,
            axis: Axis.vertical);
      case 'FM':
        return MotifWidget(
            constraint: c as ForbiddenMotif, cellSize: _kPrevSize);
      case 'GC':
        return GroupCountWidget(
            constraint: c as GroupCountConstraint,
            actualGroupCount: 0,
            cellSize: _kPrevSize);
      case 'MJ':
        return _mjPlaceholder(c as MajorityConstraint);
      case 'QA':
        return QuantityWidget(
            constraint: c as QuantityConstraint,
            actualCount: 0,
            oppositeActual: 0,
            oppositeTotal: 0,
            cellSize: _kPrevSize);
      case 'RC':
        return RowCountWidget(
            constraint: c as RowCountConstraint, cellSize: _kPrevSize);
      case 'RT':
        return TransitionWidget(
            constraint: c as RowTransitionConstraint,
            cellSize: _kPrevSize,
            axis: Axis.horizontal);
      case 'SH':
        return MotifWidget(
            constraint: c as ShapeConstraint, cellSize: _kPrevSize);
      default:
        return const SizedBox.shrink();
    }
  }

  /// Simple colour-dot placeholder — MJ has no standalone widget.
  Widget _mjPlaceholder(MajorityConstraint c) {
    final pc = Theme.of(context).extension<PuzzleColors>()!;
    final dot = c.targetColor == CellValue.black
        ? pc.cellBgBlack
        : c.targetColor == CellValue.white
        ? pc.cellBgWhite
        : pc.cellBgPurple;
    return Container(
      decoration: BoxDecoration(
        color: dot.withValues(alpha: 0.2),
        border: Border.all(color: dot, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Text(cellValueToString(c.targetColor),
            style: TextStyle(
                fontSize: _kPrevSize * 0.4,
                fontWeight: FontWeight.bold,
                color: dot)),
      ),
    );
  }

  // ----------------------------------------------------------------
  // Section 2
  // ----------------------------------------------------------------

  List<Widget> _buildS2() {
    final l = AppLocalizations.of(context)!;
    final out = <Widget>[];
    for (final (slug, hasColour, constraints) in _s2) {
      out.add(ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text('$slug — ${_s2Label(slug, l)}'),
      ));
      out.add(Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
        child: _s2Grid(slug, hasColour, constraints),
      ));
    }
    return out;
  }

  Widget _s2Grid(
      String slug, bool hasColour, List<Constraint> constraints) {
    final pc = Theme.of(context).extension<PuzzleColors>()!;
    final size = _kPrevSize;

    if (_needsMiniPuzzle(slug)) {
      return Wrap(spacing: 8, runSpacing: 4, children: [
        for (final c in constraints) _miniPuzzleWidget(c),
      ]);
    }

    final cells = <Widget>[];
    final labelStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurface,
    );

    if (hasColour) {
      for (final cc in [CellValue.black, CellValue.white, CellValue.purple]) {
        final ci = cc.index - 1;
        final c = constraints[ci];
        for (final bg in _domainColors) {
          cells.add(_cellSlot(pc, size, slug, bg, c, cc, labelStyle));
        }
      }
    } else {
      final c = constraints[0];
      for (final bg in _domainColors) {
        cells.add(_cellSlot(pc, size, slug, bg, c, null, labelStyle));
      }
    }

    return Wrap(spacing: 4, runSpacing: 4, children: cells);
  }

  Widget _cellSlot(
    PuzzleColors pc,
    double size,
    String slug,
    CellValue cellBg,
    Constraint c,
    CellValue? constraintColour,
    TextStyle labelStyle,
  ) {
    final bg = _cellBg(pc, cellBg);
    final fg = _cellFg(pc, cellBg);
    final highlight = pc.highlight;
    final label = constraintColour != null
        ? '${_colorLetter(constraintColour)}/${_colorLetter(cellBg)}'
        : _colorLetter(cellBg);

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: labelStyle),
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: bg),
        child: constraintToFlutter(c, fg, size, highlightColor: highlight),
      ),
    ]);
  }

  // ----------------------------------------------------------------
  // Mini puzzle
  // ----------------------------------------------------------------

  Widget _miniPuzzleWidget(Constraint c) {
    final puzzle = _miniPuzzle(c);
    final cellSize = _kPrevSize.clamp(24.0, 36.0);
    return PuzzleWidget(
      currentPuzzle: puzzle,
      onCellTap: (_) {},
      onCellDrag: (_) {},
      onCellDragEnd: () {},
      cellSize: cellSize,
    );
  }

  // ----------------------------------------------------------------
  // Demo puzzle
  // ----------------------------------------------------------------

  Widget _buildDemoPuzzle() {
    final puzzle = _demoPuzzle;
    if (puzzle == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: LayoutBuilder(builder: (context, constraints) {
        final hasLeftBar = puzzle.constraints
            .any((c) => c is RowCountConstraint || c is RowTransitionConstraint);
        double maxCellW = constraints.maxWidth / puzzle.width;
        if (hasLeftBar) {
          maxCellW = constraints.maxWidth / (puzzle.width + 0.7);
        }
        final cellSize = maxCellW.clamp(20.0, 60.0);
        return Center(
          child: PuzzleWidget(
            currentPuzzle: puzzle,
            onCellTap: (_) {},
            onCellDrag: (_) {},
            onCellDragEnd: () {},
            cellSize: cellSize,
          ),
        );
      }),
    );
  }

  // ----------------------------------------------------------------
  // Labels
  // ----------------------------------------------------------------

  String _variantLabel(Constraint c) {
    if (c is ShapeConstraint) return cellValueToString(c.color);
    if (c is MajorityConstraint) return cellValueToString(c.targetColor);
    final refs = c.referencedColors;
    if (refs.length == 1 && refs.first != CellValue.free) {
      return cellValueToString(refs.first);
    }
    final s = c.serialize();
    return s.contains(':') ? s.split(':').last : s;
  }

  String _s1Label(String slug, AppLocalizations l) {
    switch (slug) {
      case 'FM': return l.constraintForbiddenPattern;
      case 'SH': return l.constraintShape;
      case 'RC': case 'CC': return l.constraintLineCount;
      case 'RT': case 'CT': return l.constraintTransition;
      case 'QA': return l.constraintQuantity;
      case 'GC': return l.constraintGroupCount;
      case 'MJ': return l.constraintMajority;
      case 'BB': return l.constraintBoundingBox;
      case 'CH': return l.constraintChain;
      default: return slug;
    }
  }

  String _s2Label(String slug, AppLocalizations l) {
    switch (slug) {
      case 'NC': return l.constraintNeighborCount;
      case 'EY': return l.constraintEyes;
      case 'GS': return l.constraintGroupSize;
      case 'LT': return l.constraintLetterGroup;
      case 'PA': return l.constraintParity;
      case 'DF': return l.constraintDifferentFrom;
      case 'SY': return l.constraintSymmetry;
      case 'IM': return l.constraintImplication;
      default: return slug;
    }
  }
}
