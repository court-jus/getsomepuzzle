import 'dart:async';

import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator_worker.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';

class GeneratePage extends StatefulWidget {
  final Database database;
  final void Function(PuzzleData puz)? onPuzzleSelected;

  const GeneratePage({
    super.key,
    required this.database,
    this.onPuzzleSelected,
  });

  @override
  State<GeneratePage> createState() => _GeneratePageState();
}

class _GeneratePageState extends State<GeneratePage> {
  int _width = 4;
  int _height = 4;
  int _count = 5;
  int _maxTimeSeconds = 60;
  final Set<String> _requiredRules = {};
  final Set<String> _excludedRules = {};
  String _targetPlaylist = 'custom';

  bool _isGenerating = false;
  bool _isDone = false;
  int _generated = 0;
  int _constraintsTried = 0;
  int _constraintsTotal = 0;
  double _currentRatio = 1.0;
  Stopwatch? _stopwatch;
  final List<String> _generatedLines = [];

  GeneratorWorker? _worker;
  StreamSubscription<GeneratorMessage>? _subscription;
  Timer? _uiTimer;

  static const List<(String, String)> _ruleOptions = [
    ('FM', 'Forbidden motif'),
    ('PA', 'Parity'),
    ('GS', 'Group size'),
    ('LT', 'Letter'),
    ('QA', 'Quantity'),
    ('SY', 'Symmetry'),
    ('DF', 'Different from'),
  ];

  @override
  void dispose() {
    _worker?.dispose();
    _subscription?.cancel();
    _uiTimer?.cancel();
    super.dispose();
  }

  void _startGeneration() {
    final config = GeneratorConfig(
      width: _width,
      height: _height,
      requiredRules: _requiredRules,
      bannedRules: _excludedRules,
      maxTime: Duration(seconds: _maxTimeSeconds),
      count: _count,
    );

    _worker = GeneratorWorker();
    _stopwatch = Stopwatch()..start();
    setState(() {
      _isGenerating = true;
      _isDone = false;
      _generated = 0;
      _constraintsTried = 0;
      _constraintsTotal = 0;
      _currentRatio = 1.0;
      _generatedLines.clear();
    });

    // Timer for UI refresh of elapsed time
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isGenerating) setState(() {});
    });

    final stream = _worker!.start(config);
    _subscription = stream.listen((message) {
      switch (message) {
        case GeneratorProgressMessage(:final progress):
          setState(() {
            _generated = progress.puzzlesGenerated;
            _constraintsTried = progress.constraintsTried;
            _constraintsTotal = progress.constraintsTotal;
            _currentRatio = progress.currentRatio;
          });
        case GeneratorPuzzleMessage(:final puzzleLine):
          widget.database.addToPlaylist(_targetPlaylist, puzzleLine);
          _generatedLines.add(puzzleLine);
          setState(() {
            _generated++;
          });
        case GeneratorDoneMessage(:final totalGenerated):
          _stopwatch?.stop();
          _uiTimer?.cancel();
          // Reload custom collection so puzzles are available
          if (totalGenerated > 0) {
            widget.database.loadPuzzlesFile(_targetPlaylist);
          }
          setState(() {
            _isGenerating = false;
            _isDone = true;
            _generated = totalGenerated;
          });
      }
    });
  }

  void _createNewPlaylist() {
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

  void _playGenerated() {
    if (_generatedLines.isEmpty || widget.onPuzzleSelected == null) return;
    // Set the database playlist to only the generated puzzles
    final generatedPuzzles = _generatedLines.map((l) => PuzzleData(l)).toList();
    widget.database.playlist = generatedPuzzles.sublist(1);
    Navigator.pop(context);
    widget.onPuzzleSelected!(generatedPuzzles.first);
  }

  void _stopGeneration() {
    _worker?.cancel();
    _stopwatch?.stop();
    _uiTimer?.cancel();
    setState(() {
      _isGenerating = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(loc.generateTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Width
            _buildSliderRow(loc.generateWidth, _width, 3, 10, (v) {
              setState(() => _width = v);
            }),
            const SizedBox(height: 8),
            // Height
            _buildSliderRow(loc.generateHeight, _height, 3, 10, (v) {
              setState(() => _height = v);
            }),
            const SizedBox(height: 16),

            // Required rules
            Text(
              loc.generateRequiredRules,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: _ruleOptions.map((r) {
                final selected = _requiredRules.contains(r.$1);
                final disabled = _excludedRules.contains(r.$1);
                return FilterChip(
                  label: Text(r.$2),
                  selected: selected,
                  onSelected: disabled || _isGenerating
                      ? null
                      : (v) => setState(() {
                          if (v) {
                            _requiredRules.add(r.$1);
                          } else {
                            _requiredRules.remove(r.$1);
                          }
                        }),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),

            // Excluded rules
            Text(
              loc.generateExcludedRules,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: _ruleOptions.map((r) {
                final selected = _excludedRules.contains(r.$1);
                final disabled = _requiredRules.contains(r.$1);
                return FilterChip(
                  label: Text(r.$2),
                  selected: selected,
                  onSelected: disabled || _isGenerating
                      ? null
                      : (v) => setState(() {
                          if (v) {
                            _excludedRules.add(r.$1);
                          } else {
                            _excludedRules.remove(r.$1);
                          }
                        }),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Max time
            _buildSliderRow(loc.generateMaxTime, _maxTimeSeconds, 10, 300, (v) {
              setState(() => _maxTimeSeconds = v);
            }, suffix: 's'),
            const SizedBox(height: 8),

            // Count
            _buildSliderRow(loc.generateCount, _count, 1, 50, (v) {
              setState(() => _count = v);
            }),
            const SizedBox(height: 16),

            // Target playlist
            Row(
              children: [
                SizedBox(width: 120, child: Text(loc.targetPlaylist)),
                Expanded(
                  child: DropdownButton<String>(
                    value: _targetPlaylist,
                    isExpanded: true,
                    items: [
                      for (final (key, label)
                          in widget.database.writablePlaylistOptions)
                        DropdownMenuItem(value: key, child: Text(label)),
                      DropdownMenuItem(
                        value: '__new__',
                        child: Text(
                          loc.newPlaylist,
                          style: const TextStyle(fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                    onChanged: _isGenerating
                        ? null
                        : (v) {
                            if (v == '__new__') {
                              _createNewPlaylist();
                            } else if (v != null) {
                              setState(() => _targetPlaylist = v);
                            }
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Generate / Stop button
            if (!_isGenerating)
              ElevatedButton.icon(
                onPressed: _startGeneration,
                icon: const Icon(Icons.auto_fix_high),
                label: Text(loc.generateStart),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              )
            else
              ElevatedButton.icon(
                onPressed: _stopGeneration,
                icon: const Icon(Icons.stop),
                label: Text(loc.generateStop),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),

            const SizedBox(height: 16),

            // Progress section
            if (_isGenerating || _generated > 0) ...[
              LinearProgressIndicator(
                value: _count > 0 ? _generated / _count : 0,
              ),
              const SizedBox(height: 8),
              Text(
                loc.generateProgress(_generated, _count),
                textAlign: TextAlign.center,
              ),
              if (_isGenerating && _stopwatch != null)
                Text(
                  '${_stopwatch!.elapsed.inSeconds}s / ${_maxTimeSeconds}s',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              if (_isGenerating && _constraintsTotal > 0)
                Text(
                  '${loc.generateConstraints}: $_constraintsTried / $_constraintsTotal (${(_currentRatio * 100).toInt()}%)',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              if (_isDone && _generated > 0) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    loc.generateComplete,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _playGenerated,
                        icon: const Icon(Icons.play_arrow),
                        label: Text(loc.generatePlay),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => setState(() {
                          _isDone = false;
                        }),
                        icon: const Icon(Icons.auto_fix_high),
                        label: Text(loc.generateMore),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (_isDone && _generated == 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    loc.generateFailed,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSliderRow(
    String label,
    int value,
    int min,
    int max,
    ValueChanged<int> onChanged, {
    String suffix = '',
  }) {
    return Row(
      children: [
        SizedBox(width: 120, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            label: '$value$suffix',
            onChanged: _isGenerating ? null : (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text('$value$suffix', textAlign: TextAlign.right),
        ),
      ],
    );
  }
}
