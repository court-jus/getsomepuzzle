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

  static const List<(String, String)> existingRules = [("LT", "Letter"), ("GS", "Group size"), ("FM", "Forbidden motif"), ("PA", "Parity"), ("QA", "Quantity")];

  @override
  void initState() {
    super.initState();
    updateShownPuzzles();
  }

  void applyFilter({
    RangeValues? newWidth,
    RangeValues? newHeight,
    RangeValues? newPrefilled,
    List<String>? newWRules,
    List<String>? newBRules,
    List<String>? newWFlags,
    List<String>? newBFlags,
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
        widget.database.currentFilters.bannedRules.removeAll(widget.database.currentFilters.wantedRules);
        changed = true;
      }
      if (newBRules != null) {
        widget.database.currentFilters.bannedRules = newBRules.toSet();
        widget.database.currentFilters.wantedRules.removeAll(widget.database.currentFilters.bannedRules);
        changed = true;
      }
      if (newWFlags != null) {
        widget.database.currentFilters.wantedFlags = newWFlags.toSet();
        widget.database.currentFilters.bannedFlags.removeAll(widget.database.currentFilters.wantedFlags);
        changed = true;
      }
      if (newBFlags != null) {
        widget.database.currentFilters.bannedFlags = newBFlags.toSet();
        widget.database.currentFilters.wantedFlags.removeAll(widget.database.currentFilters.bannedFlags);
        changed = true;
      }
      if (changed) {
        widget.database.currentFilters.save();
        widget.database.preparePlaylist();
        updateShownPuzzles();
      }
    });
  }

  void updateShownPuzzles() {
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
            "${puz.width}x${puz.height}\n$rules\nPLLD",
            puz,
          );
        })
        .toList();
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
                    Text("You can filter to find the kind of puzzle you like."),
                    Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Only"),
                        SegmentedButton(
                          multiSelectionEnabled: true,
                          emptySelectionAllowed: true,
                          showSelectedIcon: false,
                          selected: widget.database.currentFilters.wantedFlags,
                          onSelectionChanged: (newSelection) =>
                              applyFilter(newWFlags: newSelection.toList()),
                          segments: [
                            ButtonSegment(value: "played", label: Text("Played")),
                            ButtonSegment(value: "skipped", label: Text("Skipped")),
                            ButtonSegment(value: "liked", label: Text("Liked")),
                            ButtonSegment(value: "disliked", label: Text("Disliked")),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Not"),
                        SegmentedButton(
                          multiSelectionEnabled: true,
                          emptySelectionAllowed: true,
                          showSelectedIcon: false,
                          selected: widget.database.currentFilters.bannedFlags,
                          onSelectionChanged: (newSelection) =>
                              applyFilter(newBFlags: newSelection.toList()),
                          segments: [
                            ButtonSegment(value: "played", label: Text("Played")),
                            ButtonSegment(value: "skipped", label: Text("Skipped")),
                            ButtonSegment(value: "liked", label: Text("Liked")),
                            ButtonSegment(value: "disliked", label: Text("Disliked")),
                          ],
                        ),
                      ],
                    ),
                    Divider(),
                    // TextField(onChanged: (value) => selectPuzzle(PuzzleData(value), context)),
                    Text("Dimensions"),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Width"),
                        Expanded(
                          child: RangeSlider(
                            divisions: 4,
                            values: RangeValues(
                              widget.database.currentFilters.minWidth.toDouble(),
                              widget.database.currentFilters.maxWidth.toDouble(),
                            ),
                            onChanged: (value) => applyFilter(newWidth: value),
                            min: 2,
                            max: 10,
                            labels: RangeLabels(
                              widget.database.currentFilters.minWidth.toString(),
                              widget.database.currentFilters.maxWidth.toString(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Height"),
                        Expanded(
                          child: RangeSlider(
                            divisions: 5,
                            values: RangeValues(
                              widget.database.currentFilters.minHeight.toDouble(),
                              widget.database.currentFilters.maxHeight.toDouble(),
                            ),
                            onChanged: (value) => applyFilter(newHeight: value),
                            min: 2,
                            max: 10,
                            labels: RangeLabels(
                              widget.database.currentFilters.minHeight.toString(),
                              widget.database.currentFilters.maxHeight.toString(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text("Fill ratio"),
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
                                ButtonSegment(value: slug.$1, label: Text(slug.$2)),
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
                                ButtonSegment(value: slug.$1, label: Text(slug.$2)),
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
