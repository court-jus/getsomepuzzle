import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/bounding_box.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/chain.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/column_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/letter_group.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/implication.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/group_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/majority.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/row_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/transition_row.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/transition_column.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/widgets/cell.dart';
import 'package:getsomepuzzle/widgets/constraints/bounding_box.dart';
import 'package:getsomepuzzle/widgets/constraints/chain.dart';
import 'package:getsomepuzzle/widgets/create_page/dialogs/eyes_dialog.dart';
import 'package:getsomepuzzle/widgets/puzzle_grid_stack.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/constraints/motif.dart';
import 'package:getsomepuzzle/widgets/constraints/quantity.dart';
import 'package:getsomepuzzle/widgets/constraints/group_count.dart';
import 'package:getsomepuzzle/widgets/constraints/column_count.dart';
import 'package:getsomepuzzle/widgets/create_page/editor_state.dart';
import 'package:getsomepuzzle/widgets/create_page/dialogs/bounding_box_dialog.dart';
import 'package:getsomepuzzle/widgets/create_page/dialogs/cell_actions_dialog.dart';
import 'package:getsomepuzzle/widgets/create_page/dialogs/chain_dialog.dart';
import 'package:getsomepuzzle/widgets/create_page/dialogs/column_count_dialog.dart';
import 'package:getsomepuzzle/widgets/create_page/dialogs/column_majority_dialog.dart';
import 'package:getsomepuzzle/widgets/create_page/dialogs/confirm_delete_dialog.dart';
import 'package:getsomepuzzle/widgets/create_page/dialogs/constraint_type_picker.dart';
import 'package:getsomepuzzle/widgets/create_page/dialogs/different_from_dialog.dart';
import 'package:getsomepuzzle/widgets/create_page/dialogs/group_count_dialog.dart';
import 'package:getsomepuzzle/widgets/create_page/dialogs/group_size_dialog.dart';
import 'package:getsomepuzzle/widgets/create_page/dialogs/neighbor_count_dialog.dart';
import 'package:getsomepuzzle/widgets/create_page/dialogs/letter_group_dialog.dart';
import 'package:getsomepuzzle/widgets/create_page/dialogs/motif_dialog.dart';
import 'package:getsomepuzzle/widgets/create_page/dialogs/parity_dialog.dart';
import 'package:getsomepuzzle/widgets/create_page/dialogs/playlist_name_dialog.dart';
import 'package:getsomepuzzle/widgets/create_page/dialogs/quantity_dialog.dart';
import 'package:getsomepuzzle/widgets/create_page/dialogs/row_count_dialog.dart';
import 'package:getsomepuzzle/widgets/create_page/dialogs/row_majority_dialog.dart';
import 'package:getsomepuzzle/widgets/create_page/dialogs/symmetry_dialog.dart';
import 'package:getsomepuzzle/widgets/create_page/dialogs/transition_dialog.dart';
import 'package:getsomepuzzle/widgets/constraints/row_count.dart';
import 'package:getsomepuzzle/widgets/constraints/transition.dart';
import 'package:getsomepuzzle/widgets/create_page/dialogs/solver_report.dart';
import 'package:getsomepuzzle/widgets/create_page/dialogs/solver_report_dialog.dart';
import 'package:getsomepuzzle/widgets/create_page/shared/color_dot_picker.dart';

export 'package:getsomepuzzle/widgets/create_page/editor_state.dart';

class CreatePage extends StatefulWidget {
  final Database database;
  final ValueChanged<PuzzleData>? onPuzzleSelected;
  final VoidCallback? onTestStarted;

  /// Saved state from a previous editing session (survives navigation).
  static EditorState? savedState;

  const CreatePage({
    super.key,
    required this.database,
    this.onPuzzleSelected,
    this.onTestStarted,
  });

  @override
  State<CreatePage> createState() => _CreatePageState();
}

class _CreatePageState extends State<CreatePage> {
  int _width = 4;
  int _height = 4;
  List<CellValue> _domain = defaultDomain;
  bool _editing = false;

  final List<Constraint> _constraints = [];

  bool _implicationMode = false;
  CellValue _implicationColor = CellValue.black;
  int? _implicationSourceIdx;

  bool _letterGroupMode = false;
  String _letterGroupLetter = 'A';
  List<int> _letterGroupIndices = [];

  bool _majorityZoneMode = false;
  CellValue _majorityZoneColor = CellValue.black;
  int? _majorityZoneFirstIdx;

  Set<int> _propagationCells = {};
  Set<int> _forceCells = {};
  Map<int, CellValue> _solvedValues = {};

  final Map<int, CellValue> _fixedCells = {};

  String _targetPlaylist = 'custom';

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final saved = CreatePage.savedState;
    if (saved != null) {
      _width = saved.width;
      _height = saved.height;
      _constraints.addAll(saved.constraints);
      _fixedCells.addAll(saved.fixedCells);
      _domain = saved.domain;
      _editing = true;
      CreatePage.savedState = null;
    }
  }

  void _saveState() {
    CreatePage.savedState = EditorState(
      _width,
      _height,
      List.from(_constraints),
      Map.from(_fixedCells),
      List.from(_domain),
    );
  }

  /// Clears the solver feedback (coloured borders, corner hints and the
  /// orange culprit highlight). Must be called inside a `setState`.
  void _clearSolveFeedback() {
    _propagationCells.clear();
    _forceCells.clear();
    _solvedValues.clear();
    for (final c in _constraints) {
      c.isValid = true;
    }
  }

  Future<void> _validatePuzzle() async {
    final puzzle = _buildPuzzle();
    debugPrint('[editor] ${puzzle.lineExport(compute: false)}');
    final report = await showSolverReportDialog(
      context,
      solverFuture: compute(_solvePuzzle, puzzle),
    );
    if (!mounted || report == null) return;
    setState(() {
      _propagationCells = report.propagationCells;
      _forceCells = report.forceCells;
      _solvedValues = report.cornerValues;
      if (report.impossibleBy != null) {
        for (final c in _constraints) {
          if (c.serialize() == report.impossibleBy) {
            c.isValid = false;
            break;
          }
        }
      }
    });
  }

  /// Builds a [SolverReport] for [puzzle] on top of the shared
  /// [Puzzle.solveTrace] loop: per-cell results (borders, corner hints)
  /// are derived by replaying the trace on a clone. The per-cell sets
  /// are populated even when the solve is incomplete or contradictory,
  /// so the author still sees what the solver managed to deduce.
  static SolverReport _solvePuzzle(Puzzle puzzle) {
    final trace = puzzle.solveTrace(timeoutMs: 10000);
    final steps = trace.steps;

    // Replay the trace on a clone to record, per cell, when its value
    // first became known and which value it took (a RemoveOption on the
    // 2-colour domain resolves to the surviving colour).
    final replay = puzzle.clone();
    final firstDeducedAt = <int, int>{};
    final cornerValues = <int, CellValue>{};
    for (int i = 0; i < steps.length; i++) {
      final step = steps[i];
      if (step.value != null) {
        replay.setValue(step.cellIdx, step.value!);
      } else if (step.removeOption != null) {
        replay.removeOption(step.cellIdx, step.removeOption!);
      }

      if (replay.cells[step.cellIdx].value != CellValue.free) {
        firstDeducedAt.putIfAbsent(step.cellIdx, () => i);
        cornerValues.putIfAbsent(
          step.cellIdx,
          () => replay.cells[step.cellIdx].value,
        );
      }
    }

    final firstForceIdx = steps.indexWhere(
      (s) => s.method == SolveMethod.force,
    );
    final propCells = <int>{};
    final frcCells = <int>{};
    for (final MapEntry(:key, :value) in firstDeducedAt.entries) {
      final isBruteForce = firstForceIdx != -1 && value >= firstForceIdx;
      (isBruteForce ? frcCells : propCells).add(key);
    }

    return SolverReport(
      steps: steps,
      impossibleBy: trace.impossibleBy,
      solved: trace.impossibleBy == null && !trace.aborted && replay.complete,
      propagationCells: propCells,
      forceCells: frcCells,
      cornerValues: cornerValues,
      deducedCount: firstDeducedAt.length,
      bruteForceCount: frcCells.length,
      totalFreeCells: puzzle.cells.where((c) => !c.readonly).length,
    );
  }

  void _addConstraint(Constraint c) {
    setState(() {
      _constraints.add(c);
      _clearSolveFeedback();
    });
  }

  void _removeConstraint(Constraint c) {
    setState(() {
      _constraints.remove(c);
      _clearSolveFeedback();
    });
  }

  Puzzle _buildPuzzle() {
    final p = Puzzle.empty(_width, _height, _domain);
    for (final entry in _fixedCells.entries) {
      p.cells[entry.key].setForSolver(entry.value);
      p.cells[entry.key].readonly = true;
    }
    p.replaceConstraints(_constraints);
    return p;
  }

  void _startEditing() {
    setState(() => _editing = true);
  }

  void _loadFromRepresentation(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    try {
      final puzzle = Puzzle(trimmed);
      setState(() {
        _width = puzzle.width;
        _height = puzzle.height;
        _constraints.clear();
        _constraints.addAll(puzzle.constraints);
        _fixedCells.clear();
        for (int i = 0; i < puzzle.cells.length; i++) {
          if (puzzle.cells[i].readonly) {
            _fixedCells[i] = puzzle.cells[i].value;
          }
        }
        _domain = puzzle.domain;
        _editing = true;
        _clearSolveFeedback();
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invalid puzzle: $e')));
    }
  }

  // --- Cell tap handling ---

  Future<void> _onCellTap(int cellIdx) async {
    if (_implicationMode) {
      if (_implicationSourceIdx == null) {
        setState(() {
          _implicationSourceIdx = cellIdx;
        });
      } else {
        _addConstraint(
          ImplicationConstraint(
            '$_implicationSourceIdx.$cellIdx'
            '.${cellValueToString(_implicationColor)}',
          ),
        );
        setState(() {
          _implicationMode = false;
          _implicationSourceIdx = null;
        });
      }
      return;
    }

    if (_majorityZoneMode) {
      _finishMajorityZone(cellIdx);
      return;
    }

    if (_letterGroupMode) {
      setState(() {
        if (_letterGroupIndices.contains(cellIdx)) {
          _letterGroupIndices.remove(cellIdx);
        } else {
          _letterGroupIndices.add(cellIdx);
        }
      });
      return;
    }

    final cellConstraints = _constraints
        .whereType<CellsCentricConstraint>()
        .where((c) => c.indices.contains(cellIdx))
        .toList();
    final isFixed = _fixedCells.containsKey(cellIdx);

    final mjZones = _constraints
        .whereType<MajorityConstraint>()
        .where((mj) => _cellInMjZone(cellIdx, mj))
        .toList();

    if (mjZones.isNotEmpty) {
      final toRemove = await _showMjDeletePicker(mjZones);
      if (toRemove != null) {
        _removeConstraint(toRemove);
        return;
      }
    }

    if (cellConstraints.isEmpty && !isFixed) {
      await _pickAndAddConstraint(cellIdx);
    } else {
      await _openCellActions(cellIdx, cellConstraints, isFixed);
    }
  }

  bool _cellInMjZone(int idx, MajorityConstraint mj) {
    final r = idx ~/ _width;
    final c = idx % _width;
    return r >= mj.r0 && r <= mj.r1 && c >= mj.c0 && c <= mj.c1;
  }

  Future<MajorityConstraint?> _showMjDeletePicker(
    List<MajorityConstraint> zones,
  ) {
    final loc = AppLocalizations.of(context)!;
    return showDialog<MajorityConstraint>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${loc.createDeleteConstraint} MJ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final z in zones)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: Text(z.serialize()),
                onTap: () => Navigator.pop(ctx, z),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _openCellActions(
    int cellIdx,
    List<CellsCentricConstraint> cellConstraints,
    bool isFixed,
  ) async {
    final action = await showCellActionsDialog(
      context,
      hasConstraints: cellConstraints.isNotEmpty,
      isFixed: isFixed,
      domain: _domain,
    );
    if (!mounted || action == null) return;
    switch (action) {
      case CellAction.addNew:
        await _pickAndAddConstraint(cellIdx);
      case CellAction.deleteConstraint:
        final toRemove = await showDeleteConstraintPicker(
          context,
          constraints: cellConstraints.cast<Constraint>(),
        );
        if (toRemove != null) _removeConstraint(toRemove);
      case CellAction.removeFixed:
        setState(() {
          _fixedCells.remove(cellIdx);
          _clearSolveFeedback();
        });
      case CellAction.fixBlack:
        _setFixedCell(cellIdx, CellValue.black);
      case CellAction.fixWhite:
        _setFixedCell(cellIdx, CellValue.white);
      case CellAction.fixPurple:
        _setFixedCell(cellIdx, CellValue.purple);
    }
  }

  Future<void> _confirmDeleteTopBar(Constraint constraint) async {
    final confirmed = await showConfirmDeleteDialog(
      context,
      detail: constraint.serialize(),
    );
    if (confirmed) _removeConstraint(constraint);
  }

  Set<String> _disabledSlugsForCell(int cellIdx) {
    final disabled = <String>{};
    final ridx = cellIdx ~/ _width;
    final cidx = cellIdx % _width;
    final domainLen = _domain.length;

    // PA: disabled when no side has a length that is a positive multiple of
    // domainLen.  Four independent checks cover the two axes; the composite
    // "horizontal" / "vertical" sides are only valid when both halves are.
    bool hasValidSide(int size) => size > 0 && size % domainLen == 0;
    final left = cidx;
    final right = _width - 1 - cidx;
    final top = ridx;
    final bottom = _height - 1 - ridx;
    if (!hasValidSide(left) &&
        !hasValidSide(right) &&
        !hasValidSide(top) &&
        !hasValidSide(bottom)) {
      disabled.add('PA');
    }

    // DF: disabled for the bottom-right corner (no right or down neighbour).
    if (cidx == _width - 1 && ridx == _height - 1) {
      disabled.add('DF');
    }

    return disabled;
  }

  Future<void> _pickAndAddConstraint(int cellIdx) async {
    final slug = await showConstraintTypePicker(
      context,
      domain: _domain,
      disabledSlugs: _disabledSlugsForCell(cellIdx),
    );
    if (!mounted || slug == null) return;
    Constraint? added;
    switch (slug) {
      case 'FM':
        added = await showForbiddenMotifDialog(context, domain: _domain);
      case 'PA':
        added = await showParityDialog(
          context,
          cellIdx: cellIdx,
          width: _width,
          height: _height,
          domain: _domain,
        );
      case 'GS':
        added = await showGroupSizeDialog(
          context,
          cellIdx: cellIdx,
          width: _width,
          height: _height,
          domain: _domain,
        );
      case 'LT':
        await _startLetterGroup(cellIdx);
        return;
      case 'MJ':
        await _startMajorityZone(cellIdx);
        return;
      case 'QA':
        added = await showQuantityDialog(
          context,
          width: _width,
          height: _height,
          domain: _domain,
        );
      case 'CC':
        added = await showColumnCountDialog(
          context,
          cellIdx: cellIdx,
          width: _width,
          height: _height,
          domain: _domain,
        );
      case 'JC':
        added = await showColumnMajorityDialog(
          context,
          cellIdx: cellIdx,
          width: _width,
          height: _height,
          domain: _domain,
        );
      case 'RC':
        added = await showRowCountDialog(
          context,
          cellIdx: cellIdx,
          width: _width,
          height: _height,
          domain: _domain,
        );
      case 'JR':
        added = await showRowMajorityDialog(
          context,
          cellIdx: cellIdx,
          width: _width,
          height: _height,
          domain: _domain,
        );
      case 'RT':
        added = await showRowTransitionDialog(
          context,
          cellIdx: cellIdx,
          width: _width,
          height: _height,
        );
      case 'CT':
        added = await showColumnTransitionDialog(
          context,
          cellIdx: cellIdx,
          width: _width,
          height: _height,
        );
      case 'GC':
        added = await showGroupCountDialog(
          context,
          width: _width,
          height: _height,
          domain: _domain,
        );
      case 'NC':
        added = await showNeighborCountDialog(
          context,
          cellIdx: cellIdx,
          width: _width,
          height: _height,
          domain: _domain,
        );
      case 'SH':
        added = await showShapeDialog(context, domain: _domain);
      case 'SY':
        added = await showSymmetryDialog(context, cellIdx: cellIdx);
      case 'DF':
        added = await showDifferentFromDialog(
          context,
          cellIdx: cellIdx,
          width: _width,
          height: _height,
        );
      case 'EY':
        added = await showEyesDialog(
          context,
          cellIdx: cellIdx,
          width: _width,
          height: _height,
          domain: _domain,
        );
      case 'IM':
        final loc2 = AppLocalizations.of(context)!;
        CellValue imColor = _domain.first;
        final color = await showDialog<CellValue>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDialogState) => AlertDialog(
              title: Text(loc2.constraintImplication),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${loc2.createChooseValue}:'),
                  const SizedBox(height: 8),
                  ColorDotPicker(
                    domain: _domain,
                    selected: imColor,
                    onChanged: (v) => setDialogState(() => imColor = v),
                    dotSize: 28,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, imColor),
                  child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
                ),
              ],
            ),
          ),
        );
        if (color == null) return;
        if (!mounted) return;
        setState(() {
          _implicationMode = true;
          _implicationColor = color;
          _implicationSourceIdx = null;
        });
        return;
      case 'CH':
        added = await showChainDialog(context, domain: _domain);
      case 'BB':
        added = await showBoundingBoxDialog(
          context,
          width: _width,
          height: _height,
          domain: _domain,
        );
      case 'fixBlack':
        _setFixedCell(cellIdx, CellValue.black);
        return;
      case 'fixWhite':
        _setFixedCell(cellIdx, CellValue.white);
        return;
      case 'fixPurple':
        _setFixedCell(cellIdx, CellValue.purple);
        return;
    }
    if (added != null) _addConstraint(added);
  }

  Future<void> _startLetterGroup(int cellIdx) async {
    final usedLetters = _constraints
        .whereType<LetterGroup>()
        .map((c) => c.letter)
        .toSet();
    final letter = await showLetterGroupDialog(
      context,
      usedLetters: usedLetters,
    );
    if (letter == null) return;
    if (!mounted) return;
    setState(() {
      _letterGroupMode = true;
      _letterGroupLetter = letter;
      _letterGroupIndices = [cellIdx];
    });
  }

  void _finishLetterGroup() {
    if (_letterGroupIndices.length >= 2) {
      final indices = _letterGroupIndices.join('.');
      _addConstraint(LetterGroup('$_letterGroupLetter.$indices'));
    }
    setState(() {
      _letterGroupMode = false;
      _letterGroupIndices = [];
    });
  }

  Future<void> _startMajorityZone(int cellIdx) async {
    final loc = AppLocalizations.of(context)!;
    CellValue selected = _domain.first;
    final color = await showDialog<CellValue>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(loc.createChooseType),
          content: ColorDotPicker(
            domain: _domain,
            selected: selected,
            onChanged: (v) => setDialogState(() => selected = v),
            dotSize: 36,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, selected),
              child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
            ),
          ],
        ),
      ),
    );
    if (color == null) return;
    if (!mounted) return;
    setState(() {
      _majorityZoneMode = true;
      _majorityZoneColor = color;
      _majorityZoneFirstIdx = cellIdx;
    });
  }

  void _finishMajorityZone(int cellIdx) {
    final loc = AppLocalizations.of(context)!;
    final first = _majorityZoneFirstIdx!;
    final r0 = first ~/ _width;
    final c0 = first % _width;
    final r1 = cellIdx ~/ _width;
    final c1 = cellIdx % _width;
    final rMin = min(r0, r1);
    final rMax = max(r0, r1);
    final cMin = min(c0, c1);
    final cMax = max(c0, c1);
    final area = (rMax - rMin + 1) * (cMax - cMin + 1);
    if (area < 3) {
      setState(() {
        _majorityZoneMode = false;
        _majorityZoneFirstIdx = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.createZoneTooSmall)));
      });
      return;
    }
    _addConstraint(
      MajorityConstraint(
        '$rMin.$cMin.$rMax.$cMax.${cellValueToString(_majorityZoneColor)}',
      ),
    );
    setState(() {
      _majorityZoneMode = false;
      _majorityZoneFirstIdx = null;
    });
  }

  void _setFixedCell(int cellIdx, CellValue value) {
    setState(() {
      if (_fixedCells[cellIdx] == value) {
        _fixedCells.remove(cellIdx);
      } else {
        _fixedCells[cellIdx] = value;
      }
      _clearSolveFeedback();
    });
  }

  // --- Action buttons ---

  void _newPuzzle() {
    setState(() {
      _width = 4;
      _height = 4;
      _domain = defaultDomain;
      _constraints.clear();
      _fixedCells.clear();
      _solvedValues.clear();
      _propagationCells.clear();
      _forceCells.clear();
      _implicationMode = false;
      _implicationSourceIdx = null;
      _editing = false;
    });
  }

  void _testPuzzle() {
    if (widget.onPuzzleSelected == null) return;
    _saveState();
    final puzzle = _buildPuzzle();
    final line = puzzle.lineExport(compute: false);
    final puzzleData = PuzzleData(line);
    Navigator.pop(context);
    widget.onPuzzleSelected!(puzzleData);
    widget.onTestStarted?.call();
  }

  void _savePuzzle() async {
    final loc = AppLocalizations.of(context)!;
    final puzzle = _buildPuzzle();
    final line = puzzle.lineExport();
    await widget.database.addToPlaylist(_targetPlaylist, line);
    await widget.database.loadPuzzlesFile(_targetPlaylist);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(loc.createSaved)));
  }

  Future<void> _createNewPlaylistForSave() async {
    final name = await showPlaylistNameDialog(context);
    if (!mounted || name == null) return;
    await widget.database.createUserPlaylist(name);
    if (!mounted) return;
    setState(() {
      _targetPlaylist = 'user_${Database.slugify(name)}';
    });
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _majorityZoneMode
              ? loc.createSecondCorner
              : (_letterGroupMode
                    ? loc.createLetterGroupMode(_letterGroupLetter)
                    : (_implicationMode
                          ? loc.constraintImplication
                          : loc.createTitle)),
        ),
        actions: [
          if (_majorityZoneMode)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _majorityZoneMode = false;
                _majorityZoneFirstIdx = null;
              }),
            ),
          if (_implicationMode)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _implicationMode = false;
                _implicationSourceIdx = null;
              }),
            ),
          if (_letterGroupMode)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: _finishLetterGroup,
                icon: const Icon(Icons.check),
                label: Text(loc.createLetterGroupDone),
              ),
            ),
          if (_editing)
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: loc.createNewPuzzle,
              onPressed: _newPuzzle,
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _editing ? _buildEditor(loc) : _buildDimensionsForm(loc),
      ),
      bottomNavigationBar: _editing
          ? BottomAppBar(
              height: 40,
              color: Colors.green.shade400,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Text(
                    '${_width}x$_height (${_width * _height}) · d${_domain.length}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  Text(
                    '${_constraints.length} ${loc.generateConstraints.toLowerCase()}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  TextButton.icon(
                    onPressed: _validatePuzzle,
                    icon: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 16,
                    ),
                    label: Text(
                      loc.createValidate,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  Widget _buildDimensionsForm(AppLocalizations loc) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSliderRow(loc.generateWidth, _width, 3, 20, (v) {
            setState(() => _width = v);
          }),
          const SizedBox(height: 8),
          _buildSliderRow(loc.generateHeight, _height, 3, 15, (v) {
            setState(() => _height = v);
          }),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(width: 120, child: Text(loc.createDomainLabel)),
              ColorDotPicker(
                domain: fullDomain,
                selected: _domain.last,
                onChanged: (v) {
                  final idx = fullDomain.indexOf(v);
                  setState(() => _domain = fullDomain.sublist(0, idx + 1));
                },
                dotSize: 28,
              ),
            ],
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _startEditing,
            icon: const Icon(Icons.edit),
            label: Text(loc.createStart),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyan,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          TextField(
            decoration: InputDecoration(
              hintText: loc.createPasteHint,
              border: const OutlineInputBorder(),
              suffixIcon: const Icon(Icons.content_paste),
            ),
            onSubmitted: _loadFromRepresentation,
          ),
        ],
      ),
    );
  }

  Widget _buildSliderRow(
    String label,
    int value,
    int min,
    int max,
    ValueChanged<int> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(width: 120, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            label: '$value',
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(width: 40, child: Text('$value', textAlign: TextAlign.right)),
      ],
    );
  }

  Widget _buildEditor(AppLocalizations loc) {
    final cellConstraintsMap = <int, List<Constraint>>{};
    for (var c in _constraints.whereType<CellsCentricConstraint>()) {
      for (var idx in c.indices) {
        cellConstraintsMap.putIfAbsent(idx, () => []);
        cellConstraintsMap[idx]!.add(c);
      }
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildTopBar(),
            const SizedBox(height: 10),
            _buildColumnCountRow(),
            const SizedBox(height: 10),
            _buildGrid(cellConstraintsMap),
            const SizedBox(height: 16),
            if (_constraints.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  loc.createNoConstraints,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            if (_constraints.isNotEmpty) ...[
              Row(
                children: [
                  SizedBox(width: 100, child: Text(loc.targetPlaylist)),
                  Expanded(
                    child: DropdownButton<String>(
                      value: _targetPlaylist,
                      isExpanded: true,
                      items: [
                        for (final (key, label)
                            in widget.database.getWritablePlaylistOptions(
                              loc.collectionMyPuzzles,
                            ))
                          DropdownMenuItem(value: key, child: Text(label)),
                        DropdownMenuItem(
                          value: '__new__',
                          child: Text(
                            loc.newPlaylist,
                            style: const TextStyle(fontStyle: FontStyle.italic),
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == '__new__') {
                          _createNewPlaylistForSave();
                        } else if (v != null) {
                          setState(() => _targetPlaylist = v);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _testPuzzle,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(loc.createTest),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _savePuzzle,
                      icon: const Icon(Icons.save),
                      label: Text(loc.createSave),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyan,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final topBarSize = max(60.0, constraints.maxWidth / 8);
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: 2,
          runSpacing: 2,
          children: [
            for (var constraint in _constraints)
              if (constraint is Motif)
                GestureDetector(
                  onTap: () => _confirmDeleteTopBar(constraint),
                  child: MotifWidget(
                    constraint: constraint,
                    cellSize: topBarSize,
                  ),
                )
              else if (constraint is QuantityConstraint)
                GestureDetector(
                  onTap: () => _confirmDeleteTopBar(constraint),
                  child: QuantityWidget(
                    constraint: constraint,
                    actualCount: 0,
                    oppositeActual: 0,
                    oppositeTotal: (_width * _height) - constraint.count,
                    cellSize: topBarSize,
                  ),
                )
              else if (constraint is GroupCountConstraint)
                GestureDetector(
                  onTap: () => _confirmDeleteTopBar(constraint),
                  child: GroupCountWidget(
                    constraint: constraint,
                    actualGroupCount: 0,
                    cellSize: topBarSize,
                  ),
                )
              else if (constraint is BoundingBoxConstraint)
                GestureDetector(
                  onTap: () => _confirmDeleteTopBar(constraint),
                  child: BoundingBoxWidget(
                    constraint: constraint,
                    cellSize: topBarSize,
                  ),
                )
              else if (constraint is ChainConstraint)
                GestureDetector(
                  onTap: () => _confirmDeleteTopBar(constraint),
                  child: ChainWidget(
                    constraint: constraint,
                    cellSize: topBarSize,
                  ),
                ),
          ],
        );
      },
    );
  }

  Widget _buildColumnCountRow() {
    final ccConstraints = _constraints.whereType<ColumnCountConstraint>();
    final ctConstraints = _constraints.whereType<ColumnTransitionConstraint>();
    if (ccConstraints.isEmpty && ctConstraints.isEmpty) {
      return const SizedBox.shrink();
    }

    final ccByColumn = <int, ColumnCountConstraint>{};
    for (final c in ccConstraints) {
      ccByColumn[c.columnIdx] = c;
    }
    final ctByCol = <int, ColumnTransitionConstraint>{};
    for (final c in ctConstraints) {
      ctByCol[c.columnIdx] = c;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellSize = min(
          (constraints.maxWidth - 2) / _width,
          (MediaQuery.sizeOf(context).height * 0.5) / _height,
        );
        return SizedBox(
          width: cellSize * _width,
          child: Row(
            children: [
              for (int col = 0; col < _width; col++)
                if (ccByColumn.containsKey(col) || ctByCol.containsKey(col))
                  SizedBox(
                    width: cellSize,
                    child: Column(
                      children: [
                        if (ctByCol.containsKey(col))
                          GestureDetector(
                            onTap: () => _confirmDeleteTopBar(ctByCol[col]!),
                            child: TransitionWidget(
                              constraint: ctByCol[col]!,
                              cellSize: cellSize,
                              axis: Axis.vertical,
                            ),
                          ),
                        if (ccByColumn.containsKey(col))
                          GestureDetector(
                            onTap: () => _confirmDeleteTopBar(ccByColumn[col]!),
                            child: ColumnCountWidget(
                              constraint: ccByColumn[col]!,
                              cellSize: cellSize,
                            ),
                          ),
                      ],
                    ),
                  )
                else
                  SizedBox(width: cellSize),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGrid(Map<int, List<Constraint>> cellConstraintsMap) {
    final rcConstraints = _constraints.whereType<RowCountConstraint>();
    final rcByRow = <int, RowCountConstraint>{};
    for (final c in rcConstraints) {
      rcByRow[c.rowIdx] = c;
    }
    final rtConstraints = _constraints.whereType<RowTransitionConstraint>();
    final rtByRow = <int, RowTransitionConstraint>{};
    for (final c in rtConstraints) {
      rtByRow[c.rowIdx] = c;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellSize = min(
          (constraints.maxWidth - 2) / _width,
          (MediaQuery.sizeOf(context).height * 0.5) / _height,
        );

        final grid = PuzzleGridStack(
          puzzle: _buildPuzzle(),
          cellSize: cellSize,
          dfDefaultColor: Colors.blueGrey,
          dfHighlightColor: Colors.green,
          cellBuilder: (idx) =>
              _buildEditorCell(idx, cellSize, cellConstraintsMap),
        );

        if (rcByRow.isEmpty && rtByRow.isEmpty) return grid;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              children: [
                for (int row = 0; row < _height; row++)
                  if (rcByRow.containsKey(row) || rtByRow.containsKey(row))
                    Column(
                      children: [
                        if (rcByRow.containsKey(row))
                          GestureDetector(
                            onTap: () => _confirmDeleteTopBar(rcByRow[row]!),
                            child: RowCountWidget(
                              constraint: rcByRow[row]!,
                              cellSize: cellSize,
                            ),
                          ),
                        if (rtByRow.containsKey(row))
                          GestureDetector(
                            onTap: () => _confirmDeleteTopBar(rtByRow[row]!),
                            child: TransitionWidget(
                              constraint: rtByRow[row]!,
                              cellSize: cellSize,
                              axis: Axis.horizontal,
                            ),
                          ),
                      ],
                    )
                  else
                    SizedBox(width: cellSize * 0.7, height: cellSize),
              ],
            ),
            const SizedBox(width: 4),
            grid,
          ],
        );
      },
    );
  }

  Widget _buildEditorCell(
    int cellIdx,
    double cellSize,
    Map<int, List<Constraint>> cellConstraintsMap,
  ) {
    final constraints = cellConstraintsMap[cellIdx];
    final isLetterGroupSelected =
        _letterGroupMode && _letterGroupIndices.contains(cellIdx);
    final isImplicationSource =
        _implicationMode && _implicationSourceIdx == cellIdx;
    final isMjZoneFirst = _majorityZoneMode && _majorityZoneFirstIdx == cellIdx;
    final fixedValue = _fixedCells[cellIdx];
    final isFixed = fixedValue != null;

    final cellValue = isFixed ? fixedValue : CellValue.free;

    Color? borderColor;
    double? borderWidth;
    if (isMjZoneFirst) {
      borderColor = Colors.amber;
      borderWidth = 3;
    } else if (isLetterGroupSelected) {
      borderColor = Colors.amber;
      borderWidth = 3;
    } else if (isImplicationSource) {
      borderColor = Colors.amber;
      borderWidth = 3;
    } else if (_propagationCells.contains(cellIdx)) {
      borderColor = Colors.green;
      borderWidth = 3;
    } else if (_forceCells.contains(cellIdx)) {
      borderColor = Colors.orange;
      borderWidth = 3;
    }

    final cornerValue = (!isFixed && _solvedValues.containsKey(cellIdx))
        ? _solvedValues[cellIdx]
        : null;

    return CellWidget(
      value: cellValue,
      idx: cellIdx,
      readonly: isFixed,
      isHighlighted: isLetterGroupSelected,
      cellSize: cellSize,
      onTap: () => _onCellTap(cellIdx),
      onSecondaryTap: () {},
      onDrag: (_) {},
      onDragEnd: () {},
      constraints: constraints,
      borderColor: borderColor,
      borderWidth: borderWidth,
      cornerIndicatorValue: cornerValue,
    );
  }
}
