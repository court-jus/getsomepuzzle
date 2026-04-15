import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/parity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/different_from.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/symmetry.dart';
import 'package:getsomepuzzle/widgets/cell.dart';
import 'package:getsomepuzzle/widgets/different_from_painter.dart';
import 'package:getsomepuzzle/getsomepuzzle/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/motif.dart';
import 'package:getsomepuzzle/widgets/quantity.dart';

const _bgColors = {
  0: Color.fromARGB(255, 185, 86, 202),
  1: Colors.black,
  2: Colors.white,
};

class EditorState {
  final int width;
  final int height;
  final List<Constraint> constraints;
  final Map<int, int> fixedCells;
  EditorState(this.width, this.height, this.constraints, this.fixedCells);
}

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
  // Step 1: dimensions
  int _width = 4;
  int _height = 4;
  bool _editing = false;

  // Step 2: editor
  final List<Constraint> _constraints = [];

  // Letter group multi-select mode
  bool _letterGroupMode = false;
  String _letterGroupLetter = 'A';
  List<int> _letterGroupIndices = [];

  // Auto-solve debounce and solvability categories
  Timer? _solveDebounce;
  Set<int> _propagationCells = {};
  Set<int> _forceCells = {};
  Map<int, int> _solvedValues = {};
  int? _autoComplexity;

  final Map<int, int> _fixedCells = {};

  // Target playlist for saving
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

  void _onCellTap(int cellIdx) {
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

    // Check if cell has constraints or is fixed
    final cellConstraints = _constraints
        .whereType<CellsCentricConstraint>()
        .where((c) => c.indices.contains(cellIdx))
        .toList();
    final isFixed = _fixedCells.containsKey(cellIdx);

    if (cellConstraints.isEmpty && !isFixed) {
      _showConstraintTypePicker(cellIdx);
    } else {
      _showCellWithConstraintsMenu(cellIdx, cellConstraints);
    }
  }

  void _showCellWithConstraintsMenu(
    int cellIdx,
    List<CellsCentricConstraint> cellConstraints,
  ) {
    final loc = AppLocalizations.of(context)!;
    final isFixed = _fixedCells.containsKey(cellIdx);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(loc.createAddNew),
              onTap: () {
                Navigator.pop(ctx);
                _showConstraintTypePicker(cellIdx);
              },
            ),
            if (cellConstraints.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete),
                title: Text(loc.createDeleteConstraint),
                onTap: () {
                  Navigator.pop(ctx);
                  _showDeleteConstraintPicker(
                    cellConstraints.cast<Constraint>(),
                  );
                },
              ),
            if (isFixed)
              ListTile(
                leading: const Icon(Icons.lock_open),
                title: Text(loc.createRemoveFixed),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _fixedCells.remove(cellIdx));
                  _scheduleAutoSolve();
                },
              ),
            if (isFixed)
              ListTile(
                leading: const Icon(Icons.circle, color: Colors.black),
                title: Text(loc.createFixBlack),
                onTap: () {
                  Navigator.pop(ctx);
                  _setFixedCell(cellIdx, 1);
                },
              ),
            if (isFixed)
              ListTile(
                leading: const Icon(Icons.circle, color: Colors.white),
                title: Text(loc.createFixWhite),
                onTap: () {
                  Navigator.pop(ctx);
                  _setFixedCell(cellIdx, 2);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConstraintPicker(List<Constraint> constraintsToShow) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (var c in constraintsToShow)
              ListTile(
                title: Text(c.serialize()),
                trailing: const Icon(Icons.delete, color: Colors.red),
                onTap: () {
                  Navigator.pop(ctx);
                  _removeConstraint(c);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _onTopBarConstraintTap(Constraint constraint) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.createConfirmDelete),
        content: Text(constraint.serialize()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _removeConstraint(constraint);
            },
            child: Text(
              MaterialLocalizations.of(ctx).deleteButtonTooltip,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  // --- Constraint type picker ---

  void _showConstraintTypePicker(int cellIdx) {
    final loc = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                loc.createChooseType,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: Text(loc.constraintForbiddenPattern),
              onTap: () {
                Navigator.pop(ctx);
                _showForbiddenMotifDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: Text(loc.constraintParity),
              onTap: () {
                Navigator.pop(ctx);
                _showParityDialog(cellIdx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_work),
              title: Text(loc.constraintGroupSize),
              onTap: () {
                Navigator.pop(ctx);
                _showGroupSizeDialog(cellIdx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: Text(loc.constraintLetterGroup),
              onTap: () {
                Navigator.pop(ctx);
                _showLetterGroupStart(cellIdx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.tag),
              title: Text(loc.constraintQuantity),
              onTap: () {
                Navigator.pop(ctx);
                _showQuantityDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.flip),
              title: Text(loc.constraintSymmetry),
              onTap: () {
                Navigator.pop(ctx);
                _showSymmetryDialog(cellIdx);
              },
            ),
            ListTile(
              leading: const Text('≠', style: TextStyle(fontSize: 24)),
              title: Text(loc.constraintDifferentFrom),
              onTap: () {
                Navigator.pop(ctx);
                _showDifferentFromDialog(cellIdx);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.circle, color: Colors.black),
              title: Text(loc.createFixBlack),
              onTap: () {
                Navigator.pop(ctx);
                _setFixedCell(cellIdx, 1);
              },
            ),
            ListTile(
              leading: const Icon(Icons.circle, color: Colors.white),
              title: Text(loc.createFixWhite),
              onTap: () {
                Navigator.pop(ctx);
                _setFixedCell(cellIdx, 2);
              },
            ),
          ],
        ),
      ),
    );
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

  // --- Forbidden Motif dialog ---

  void _showForbiddenMotifDialog() {
    int motifWidth = 2;
    int motifHeight = 2;
    List<List<int>> grid = List.generate(3, (_) => List.filled(3, 0));

    showDialog(
      context: context,
      builder: (ctx) {
        final loc = AppLocalizations.of(context)!;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(loc.constraintForbiddenPattern),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text('${loc.createMotifWidth}: '),
                      DropdownButton<int>(
                        value: motifWidth,
                        items: [1, 2, 3]
                            .map(
                              (v) =>
                                  DropdownMenuItem(value: v, child: Text('$v')),
                            )
                            .toList(),
                        onChanged: (v) {
                          setDialogState(() => motifWidth = v!);
                        },
                      ),
                      const SizedBox(width: 16),
                      Text('${loc.createMotifHeight}: '),
                      DropdownButton<int>(
                        value: motifHeight,
                        items: [1, 2, 3]
                            .map(
                              (v) =>
                                  DropdownMenuItem(value: v, child: Text('$v')),
                            )
                            .toList(),
                        onChanged: (v) {
                          setDialogState(() => motifHeight = v!);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Table(
                    defaultColumnWidth: const FixedColumnWidth(50),
                    children: [
                      for (var row = 0; row < motifHeight; row++)
                        TableRow(
                          children: [
                            for (var col = 0; col < motifWidth; col++)
                              GestureDetector(
                                onTap: () {
                                  setDialogState(() {
                                    grid[row][col] = (grid[row][col] + 1) % 3;
                                  });
                                },
                                child: Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: _bgColors[grid[row][col]],
                                    border: Border.all(color: Colors.blueGrey),
                                  ),
                                ),
                              ),
                            // Fill remaining columns with empty SizedBox
                            for (var col = motifWidth; col < 3; col++)
                              const SizedBox(width: 50, height: 50),
                          ],
                        ),
                      // Fill remaining rows
                      for (var row = motifHeight; row < 3; row++)
                        TableRow(
                          children: List.generate(
                            3,
                            (_) => const SizedBox(width: 50, height: 50),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
                ),
                TextButton(
                  onPressed: () {
                    // Build motif string from grid
                    final motifRows = <String>[];
                    bool hasNonZero = false;
                    for (var row = 0; row < motifHeight; row++) {
                      final rowStr = grid[row]
                          .sublist(0, motifWidth)
                          .map((v) => v.toString())
                          .join('');
                      motifRows.add(rowStr);
                      if (rowStr.contains(RegExp('[12]'))) hasNonZero = true;
                    }
                    if (!hasNonZero) return;
                    final motifStr = motifRows.join('.');
                    Navigator.pop(ctx);
                    _addConstraint(ForbiddenMotif(motifStr));
                  },
                  child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- Parity dialog ---

  void _showParityDialog(int cellIdx) {
    final loc = AppLocalizations.of(context)!;
    final ridx = cellIdx ~/ _width;
    final cidx = cellIdx % _width;
    final leftSize = cidx;
    final rightSize = _width - 1 - cidx;
    final topSize = ridx;
    final bottomSize = _height - 1 - ridx;

    final validSides = <String>[];
    if (leftSize % 2 == 0 && leftSize > 0) validSides.add('left');
    if (rightSize % 2 == 0 && rightSize > 0) validSides.add('right');
    if (leftSize % 2 == 0 &&
        rightSize % 2 == 0 &&
        rightSize > 0 &&
        leftSize > 0) {
      validSides.add('horizontal');
    }
    if (topSize % 2 == 0 && topSize > 0) validSides.add('top');
    if (bottomSize % 2 == 0 && bottomSize > 0) validSides.add('bottom');
    if (topSize % 2 == 0 &&
        bottomSize % 2 == 0 &&
        bottomSize > 0 &&
        topSize > 0) {
      validSides.add('vertical');
    }

    if (validSides.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid parity side for this cell')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                loc.createChooseSide,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (var side in validSides)
              ListTile(
                title: Text(side),
                onTap: () {
                  Navigator.pop(ctx);
                  _addConstraint(ParityConstraint('$cellIdx.$side'));
                },
              ),
          ],
        ),
      ),
    );
  }

  // --- Group Size dialog ---

  void _showGroupSizeDialog(int cellIdx) {
    final loc = AppLocalizations.of(context)!;
    final maxSize = min(15, (_width * _height) ~/ 2);
    int size = 2;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(loc.createChooseSize),
          content: Row(
            children: [
              Expanded(
                child: Slider(
                  value: size.toDouble(),
                  min: 1,
                  max: maxSize.toDouble(),
                  divisions: maxSize - 1,
                  label: '$size',
                  onChanged: (v) => setDialogState(() => size = v.round()),
                ),
              ),
              SizedBox(width: 40, child: Text('$size')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _addConstraint(GroupSize('$cellIdx.$size'));
              },
              child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
            ),
          ],
        ),
      ),
    );
  }

  // --- Symmetry dialog ---

  void _showSymmetryDialog(int cellIdx) {
    final loc = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                loc.createChooseAxis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (var axis = 1; axis <= 5; axis++)
              ListTile(
                leading: Text(
                  axisRepresentation[axis] ?? '',
                  style: const TextStyle(fontSize: 24),
                ),
                title: Text('Axis $axis'),
                onTap: () {
                  Navigator.pop(ctx);
                  _addConstraint(SymmetryConstraint('$cellIdx.$axis'));
                },
              ),
          ],
        ),
      ),
    );
  }

  // --- Different From dialog ---

  void _showDifferentFromDialog(int cellIdx) {
    final cidx = cellIdx % _width;
    final ridx = cellIdx ~/ _width;
    final validDirs = <String>[];
    if (cidx < _width - 1) validDirs.add('right');
    if (ridx < _height - 1) validDirs.add('down');

    if (validDirs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid direction for this cell')),
      );
      return;
    }

    if (validDirs.length == 1) {
      _addConstraint(DifferentFromConstraint('$cellIdx.${validDirs.first}'));
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final dir in validDirs)
              ListTile(
                title: Text(dir == 'right' ? '→' : '↓'),
                onTap: () {
                  Navigator.pop(ctx);
                  _addConstraint(DifferentFromConstraint('$cellIdx.$dir'));
                },
              ),
          ],
        ),
      ),
    );
  }

  // --- Letter Group ---

  void _showLetterGroupStart(int cellIdx) {
    final loc = AppLocalizations.of(context)!;
    // Find next unused letter
    final usedLetters = _constraints
        .whereType<LetterGroup>()
        .map((c) => c.letter)
        .toSet();
    String nextLetter = 'A';
    while (usedLetters.contains(nextLetter)) {
      nextLetter = String.fromCharCode(nextLetter.codeUnitAt(0) + 1);
    }

    showDialog(
      context: context,
      builder: (ctx) {
        String letter = nextLetter;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(loc.createChooseLetter),
            content: DropdownButton<String>(
              value: letter,
              items: List.generate(
                26,
                (i) => String.fromCharCode('A'.codeUnitAt(0) + i),
              ).map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
              onChanged: (v) => setDialogState(() => letter = v!),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _letterGroupMode = true;
                    _letterGroupLetter = letter;
                    _letterGroupIndices = [cellIdx];
                  });
                },
                child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
              ),
            ],
          ),
        );
      },
    );
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

  // --- Quantity dialog ---

  void _showQuantityDialog() {
    final loc = AppLocalizations.of(context)!;
    int value = 1;
    int count = (_width * _height) ~/ 2;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(loc.constraintQuantity),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text('${loc.createChooseValue}: '),
                  DropdownButton<int>(
                    value: value,
                    items: [1, 2]
                        .map(
                          (v) => DropdownMenuItem(value: v, child: Text('$v')),
                        )
                        .toList(),
                    onChanged: (v) => setDialogState(() => value = v!),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('${loc.createChooseCount}: '),
                  Expanded(
                    child: Slider(
                      value: count.toDouble(),
                      min: 1,
                      max: (_width * _height - 1).toDouble(),
                      divisions: _width * _height - 2,
                      label: '$count',
                      onChanged: (v) => setDialogState(() => count = v.round()),
                    ),
                  ),
                  Text('$count'),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _addConstraint(QuantityConstraint('$value.$count'));
              },
              child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
            ),
          ],
        ),
      ),
    );
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

  void _createNewPlaylistForSave() {
    final loc = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.createPlaylist),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: loc.playlistName),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              await widget.database.createUserPlaylist(name);
              setState(() {
                _targetPlaylist = 'user_${Database.slugify(name)}';
              });
            },
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );
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
    // Compute cell constraints map for display
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
            // Top bar: ForbiddenMotif + QuantityConstraint
            _buildTopBar(),

            const SizedBox(height: 10),

            // Grid
            _buildGrid(cellConstraintsMap),

            const SizedBox(height: 16),

            // Hint text when no constraints
            if (_constraints.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  loc.createNoConstraints,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),

            // Target playlist + Action buttons
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
                  onTap: () => _onTopBarConstraintTap(constraint),
                  child: MotifWidget(
                    constraint: constraint,
                    cellSize: topBarSize,
                  ),
                )
              else if (constraint is QuantityConstraint)
                GestureDetector(
                  onTap: () => _onTopBarConstraintTap(constraint),
                  child: QuantityWidget(
                    constraint: constraint,
                    actualCount: 0,
                    cellSize: topBarSize,
                  ),
                ),
          ],
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

    // Cell value: fixed cells show their color, others are empty (0)
    final cellValue = isFixed ? fixedValue : 0;

    // Determine border based on solvability
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

    // Corner triangle for auto-solved value
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
