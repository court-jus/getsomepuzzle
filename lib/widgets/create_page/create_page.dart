import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/column_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/different_from.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/group_count.dart';
import 'package:getsomepuzzle/widgets/cell.dart';
import 'package:getsomepuzzle/widgets/create_page/dialogs/eyes_dialog.dart';
import 'package:getsomepuzzle/widgets/different_from_painter.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/motif.dart';
import 'package:getsomepuzzle/widgets/quantity.dart';
import 'package:getsomepuzzle/widgets/group_count.dart';
import 'package:getsomepuzzle/widgets/column_count.dart';
import 'package:getsomepuzzle/widgets/create_page/editor_state.dart';
import 'package:getsomepuzzle/widgets/create_page/dialogs/cell_actions_dialog.dart';
import 'package:getsomepuzzle/widgets/create_page/dialogs/column_count_dialog.dart';
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
import 'package:getsomepuzzle/widgets/create_page/dialogs/symmetry_dialog.dart';

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
  bool _editing = false;

  final List<Constraint> _constraints = [];

  bool _letterGroupMode = false;
  String _letterGroupLetter = 'A';
  List<int> _letterGroupIndices = [];

  Timer? _solveDebounce;
  Set<int> _propagationCells = {};
  Set<int> _forceCells = {};
  Map<int, int> _solvedValues = {};
  int? _autoComplexity;

  final Map<int, int> _fixedCells = {};

  String _targetPlaylist = 'custom';

  @override
  void dispose() {
    _solveDebounce?.cancel();
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
    );
  }

  void _scheduleAutoSolve() {
    _solveDebounce?.cancel();
    _solveDebounce = Timer(const Duration(milliseconds: 500), () {
      _autoSolve();
    });
  }

  Future<void> _autoSolve() async {
    if (!mounted) return;
    final puzzle = _buildPuzzle();
    final steps = await compute(_solvePuzzle, puzzle);
    if (!mounted) return;
    final propCells = <int>{};
    final frcCells = <int>{};
    final values = <int, int>{};
    for (final step in steps) {
      values[step.cellIdx] = step.value;
      if (step.method == SolveMethod.propagation) {
        propCells.add(step.cellIdx);
      } else {
        frcCells.add(step.cellIdx);
      }
    }
    setState(() {
      _propagationCells = propCells;
      _forceCells = frcCells;
      _solvedValues = values;
      _autoComplexity = puzzle.computeComplexity();
    });
  }

  static List<SolveStep> _solvePuzzle(Puzzle puzzle) {
    return puzzle.solveExplained(timeoutMs: 10000);
  }

  void _addConstraint(Constraint c) {
    setState(() {
      _constraints.add(c);
    });
    _scheduleAutoSolve();
  }

  void _removeConstraint(Constraint c) {
    setState(() {
      _constraints.remove(c);
    });
    _scheduleAutoSolve();
  }

  Puzzle _buildPuzzle() {
    final p = Puzzle.empty(_width, _height, [1, 2]);
    for (final entry in _fixedCells.entries) {
      p.cells[entry.key].setForSolver(entry.value);
      p.cells[entry.key].readonly = true;
    }
    p.constraints = List.from(_constraints);
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
        _editing = true;
      });
      _scheduleAutoSolve();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invalid puzzle: $e')));
    }
  }

  // --- Cell tap handling ---

  Future<void> _onCellTap(int cellIdx) async {
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

    if (cellConstraints.isEmpty && !isFixed) {
      await _pickAndAddConstraint(cellIdx);
    } else {
      await _openCellActions(cellIdx, cellConstraints, isFixed);
    }
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
        setState(() => _fixedCells.remove(cellIdx));
        _scheduleAutoSolve();
      case CellAction.fixBlack:
        _setFixedCell(cellIdx, 1);
      case CellAction.fixWhite:
        _setFixedCell(cellIdx, 2);
    }
  }

  Future<void> _confirmDeleteTopBar(Constraint constraint) async {
    final confirmed = await showConfirmDeleteDialog(
      context,
      detail: constraint.serialize(),
    );
    if (confirmed) _removeConstraint(constraint);
  }

  Future<void> _pickAndAddConstraint(int cellIdx) async {
    final type = await showConstraintTypePicker(context);
    if (!mounted || type == null) return;
    Constraint? added;
    switch (type) {
      case ConstraintType.forbiddenPattern:
        added = await showForbiddenMotifDialog(context);
      case ConstraintType.parity:
        added = await showParityDialog(
          context,
          cellIdx: cellIdx,
          width: _width,
          height: _height,
        );
      case ConstraintType.groupSize:
        added = await showGroupSizeDialog(
          context,
          cellIdx: cellIdx,
          width: _width,
          height: _height,
        );
      case ConstraintType.letterGroup:
        await _startLetterGroup(cellIdx);
        return;
      case ConstraintType.quantity:
        added = await showQuantityDialog(
          context,
          width: _width,
          height: _height,
        );
      case ConstraintType.columnCount:
        added = await showColumnCountDialog(
          context,
          cellIdx: cellIdx,
          width: _width,
          height: _height,
        );
      case ConstraintType.groupCount:
        added = await showGroupCountDialog(
          context,
          width: _width,
          height: _height,
        );
      case ConstraintType.neighborCount:
        added = await showNeighborCountDialog(
          context,
          cellIdx: cellIdx,
          width: _width,
          height: _height,
        );
      case ConstraintType.shape:
        added = await showShapeDialog(context);
      case ConstraintType.symmetry:
        added = await showSymmetryDialog(context, cellIdx: cellIdx);
      case ConstraintType.differentFrom:
        added = await showDifferentFromDialog(
          context,
          cellIdx: cellIdx,
          width: _width,
          height: _height,
        );
      case ConstraintType.eyes:
        added = await showEyesDialog(context, cellIdx: cellIdx, width: _width, height: _height);
      case ConstraintType.fixBlack:
        _setFixedCell(cellIdx, 1);
        return;
      case ConstraintType.fixWhite:
        _setFixedCell(cellIdx, 2);
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

  void _setFixedCell(int cellIdx, int value) {
    setState(() {
      if (_fixedCells[cellIdx] == value) {
        _fixedCells.remove(cellIdx);
      } else {
        _fixedCells[cellIdx] = value;
      }
    });
    _scheduleAutoSolve();
  }

  // --- Action buttons ---

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
          _letterGroupMode
              ? loc.createLetterGroupMode(_letterGroupLetter)
              : loc.createTitle,
        ),
        actions: [
          if (_letterGroupMode)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: _finishLetterGroup,
                icon: const Icon(Icons.check),
                label: Text(loc.createLetterGroupDone),
              ),
            ),
        ],
      ),
      body: _editing ? _buildEditor(loc) : _buildDimensionsForm(loc),
      bottomNavigationBar: _editing
          ? BottomAppBar(
              height: 40,
              color: Colors.green.shade400,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Text(
                    '${_width}x$_height (${_width * _height})',
                    style: const TextStyle(color: Colors.white),
                  ),
                  Text(
                    '${_constraints.length} ${loc.generateConstraints.toLowerCase()}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  if (_autoComplexity != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const FaIcon(
                          FontAwesomeIcons.brain,
                          size: 12,
                          color: Colors.white,
                        ),
                        Text(
                          ' $_autoComplexity',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
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
          _buildSliderRow(loc.generateWidth, _width, 3, 10, (v) {
            setState(() => _width = v);
          }),
          const SizedBox(height: 8),
          _buildSliderRow(loc.generateHeight, _height, 3, 10, (v) {
            setState(() => _height = v);
          }),
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
                    oppositeTotal: (_width * _height) - constraint.value,
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
                ),
          ],
        );
      },
    );
  }

  Widget _buildColumnCountRow() {
    final ccConstraints = _constraints.whereType<ColumnCountConstraint>();
    if (ccConstraints.isEmpty) return const SizedBox.shrink();

    final ccByColumn = <int, ColumnCountConstraint>{};
    for (final c in ccConstraints) {
      ccByColumn[c.columnIdx] = c;
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
                if (ccByColumn.containsKey(col))
                  GestureDetector(
                    onTap: () => _confirmDeleteTopBar(ccByColumn[col]!),
                    child: ColumnCountWidget(
                      constraint: ccByColumn[col]!,
                      cellSize: cellSize,
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
    final dfConstraints = _constraints
        .whereType<DifferentFromConstraint>()
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellSize = min(
          (constraints.maxWidth - 2) / _width,
          (MediaQuery.sizeOf(context).height * 0.5) / _height,
        );

        return Stack(
          children: [
            Table(
              border: TableBorder.all(),
              defaultColumnWidth: FixedColumnWidth(cellSize),
              children: [
                for (var row = 0; row < _height; row++)
                  TableRow(
                    children: [
                      for (var col = 0; col < _width; col++)
                        _buildEditorCell(
                          row * _width + col,
                          cellSize,
                          cellConstraintsMap,
                        ),
                    ],
                  ),
              ],
            ),
            if (dfConstraints.isNotEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: DifferentFromPainter(
                      constraints: dfConstraints,
                      cellSize: cellSize,
                      gridWidth: _width,
                      defaultColor: Colors.blueGrey,
                      highlightColor: Colors.green,
                    ),
                  ),
                ),
              ),
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
    final fixedValue = _fixedCells[cellIdx];
    final isFixed = fixedValue != null;

    final cellValue = isFixed ? fixedValue : 0;

    Color? borderColor;
    double? borderWidth;
    if (isLetterGroupSelected) {
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
