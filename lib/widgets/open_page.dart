import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/database.dart';

class OpenPage extends StatefulWidget {
  final Database database;
  final dynamic Function(PuzzleData puz) onPuzzleSelected;

  const OpenPage({
    super.key,
    required this.database,
    required this.onPuzzleSelected,
  });

  @override
  State<OpenPage> createState() => _OpenPageState();
}

class _OpenPageState extends State<OpenPage> {
  List<(String, PuzzleData)> shownPuzzles = [];

  static const List<String> existingRules = ["LT", "GS", "FM", "PA"];

  void applyFilter({
    RangeValues? newWidth,
    RangeValues? newHeight,
    RangeValues? newPrefilled,
    List<String>? newWRules,
    List<String>? newBRules,
  }) {
    setState(() {
      bool changed = false;
      if (newWidth != null) {
        widget.database.currentFilters.minWidth = newWidth.start.toInt();
        widget.database.currentFilters.maxWidth = newWidth.end.toInt();
        changed = true;
      }
      if (newHeight != null) {
        widget.database.currentFilters.minHeight = newHeight.start.toInt();
        widget.database.currentFilters.maxHeight = newHeight.end.toInt();
        changed = true;
      }
      if (newPrefilled != null) {
        widget.database.currentFilters.minFilled = newPrefilled.start.toInt();
        widget.database.currentFilters.maxFilled = newPrefilled.end.toInt();
        changed = true;
      }
      if (newWRules != null) {
        widget.database.currentFilters.wantedRules = newWRules.toSet();
        changed = true;
      }
      if (newBRules != null) {
        widget.database.currentFilters.bannedRules = newBRules.toSet();
        changed = true;
      }
      if (changed) {
        widget.database.currentFilters.save();
        widget.database.preparePlaylist();
        shownPuzzles = widget.database
            .filter()
            .take(10)
            .map((puz) {
              final lineAttr = puz.lineRepresentation.split("_");
              final rules = lineAttr[3]
                  .split(";")
                  .map((r) => r.split(":")[0])
                  .toSet()
                  .join(" ");
              return (
                "${puz.width}x${puz.height}\n$rules",
                puz,
              );
            })
            .toList();
      }
    });
  }

  void selectPuzzle(PuzzleData puz, BuildContext context) {
    widget.onPuzzleSelected(puz);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Open puzzle")),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints viewportConstraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: viewportConstraints.maxHeight,
              ),
              child: Container(
                margin: EdgeInsets.all(8),
                child: Column(
                  children: [
                    TextField(onChanged: (value) => selectPuzzle(PuzzleData(value), context)),
                    RangeSlider(
                      divisions: 4,
                      values: RangeValues(
                        widget.database.currentFilters.minWidth.toDouble(),
                        widget.database.currentFilters.maxWidth.toDouble(),
                      ),
                      onChanged: (value) => applyFilter(newWidth: value),
                      min: 3,
                      max: 6,
                      labels: RangeLabels(
                        widget.database.currentFilters.minWidth.toString(),
                        widget.database.currentFilters.maxWidth.toString(),
                      ),
                    ),
                    RangeSlider(
                      divisions: 5,
                      values: RangeValues(
                        widget.database.currentFilters.minHeight.toDouble(),
                        widget.database.currentFilters.maxHeight.toDouble(),
                      ),
                      onChanged: (value) => applyFilter(newHeight: value),
                      min: 3,
                      max: 8,
                      labels: RangeLabels(
                        widget.database.currentFilters.minHeight.toString(),
                        widget.database.currentFilters.maxHeight.toString(),
                      ),
                    ),
                    RangeSlider(
                      values: RangeValues(
                        widget.database.currentFilters.minFilled.toDouble(),
                        widget.database.currentFilters.maxFilled.toDouble(),
                      ),
                      onChanged: (value) => applyFilter(newPrefilled: value),
                      min: 0,
                      max: 100,
                      labels: RangeLabels(
                        widget.database.currentFilters.minFilled.toString(),
                        widget.database.currentFilters.maxFilled.toString(),
                      ),
                    ),
                    const Text("Wanted rules"),
                    SegmentedButton(
                      multiSelectionEnabled: true,
                      emptySelectionAllowed: true,
                      showSelectedIcon: false,
                      selected: widget.database.currentFilters.wantedRules,
                      onSelectionChanged: (newSelection) =>
                          applyFilter(newWRules: newSelection.toList()),
                      segments: existingRules
                          .map(
                            (slug) =>
                                ButtonSegment(value: slug, label: Text(slug)),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 20),
                    const Text("Banned rules"),
                    SegmentedButton(
                      multiSelectionEnabled: true,
                      emptySelectionAllowed: true,
                      showSelectedIcon: false,
                      selected: widget.database.currentFilters.bannedRules,
                      onSelectionChanged: (newSelection) =>
                          applyFilter(newBRules: newSelection.toList()),
                      segments: existingRules
                          .map(
                            (slug) =>
                                ButtonSegment(value: slug, label: Text(slug)),
                          )
                          .toList(),
                    ),
                    Wrap(
                      direction: Axis.horizontal,
                      alignment: WrapAlignment.center,
                      spacing: 2,
                      runSpacing: 2,
                      children: [
                        for (final puz in shownPuzzles)
                          TextButton(
                            child: Text(puz.$1),
                            onPressed: () {
                              selectPuzzle(puz.$2, context);
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
