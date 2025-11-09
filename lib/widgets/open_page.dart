import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/database.dart';
import 'package:getsomepuzzle/widgets/plusminus.dart';

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
  int matchingCount = 0;
  Set<String> collection = {"puzzles"};
  static const List<(String, String)> collections = [
    ("tutorial", "Tutorial"),
    ("puzzles", "A"),
    ("new_puzzles", "B"),
    ("high_ratio", "C"),
  ];

  static const List<(String, String)> existingRules = [
    ("LT", "Letter"),
    ("GS", "Group size"),
    ("FM", "Forbidden motif"),
    ("PA", "Parity"),
    ("QA", "Quantity"),
  ];

  @override
  void initState() {
    super.initState();
    collection = {widget.database.collection};
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
        log("New WRules $newWRules");
        widget.database.currentFilters.wantedRules = newWRules.toSet();
        widget.database.currentFilters.bannedRules.removeAll(
          widget.database.currentFilters.wantedRules,
        );
        changed = true;
      }
      if (newBRules != null) {
        widget.database.currentFilters.bannedRules = newBRules.toSet();
        widget.database.currentFilters.wantedRules.removeAll(
          widget.database.currentFilters.bannedRules,
        );
        changed = true;
      }
      if (newWFlags != null) {
        widget.database.currentFilters.wantedFlags = newWFlags.toSet();
        widget.database.currentFilters.bannedFlags = widget
            .database
            .currentFilters
            .bannedFlags
            .where((flag) => !newWFlags.contains(flag))
            .toSet();
        changed = true;
      }
      if (newBFlags != null) {
        widget.database.currentFilters.bannedFlags = newBFlags.toSet();
        widget.database.currentFilters.wantedFlags = widget
            .database
            .currentFilters
            .wantedFlags
            .where((flag) => !newBFlags.contains(flag))
            .toSet();
        changed = true;
      }
      if (changed) {
        widget.database.currentFilters.save();
        widget.database.preparePlaylist();
        updateShownPuzzles();
      }
    });
  }

  void chooseCollection(Set<String> newCollection) {
    setState(() {
      collection = newCollection;
    });
    widget.database.loadPuzzlesFile(collection.first).then((void _) => setState(updateShownPuzzles));
  }

  void setShuffle(bool newValue) {
    setState(() {
      widget.database.shouldShuffle = newValue;
    });
  }

  void updateShownPuzzles() {
    final filteredDatabase = widget.database.filter();
    matchingCount = filteredDatabase.length;
    shownPuzzles = filteredDatabase.take(10).map((puz) {
      final lineAttr = puz.lineRepresentation.split("_");
      final rules = lineAttr[3]
          .split(";")
          .map((r) => r.split(":")[0])
          .toSet()
          .join(" ");
      var flags =
          ((puz.played ? "P" : "_") +
          (puz.liked != null ? "L" : "_") +
          (puz.skipped != null ? "S" : "_") +
          (puz.disliked != null ? "D" : "_"));
      return ("${puz.width}x${puz.height}\n$rules\n$flags", puz);
    }).toList();
  }

  void selectPuzzle(PuzzleData puz, BuildContext context, [bool popFromDatabase = true]) {
    if (popFromDatabase) {
      widget.database.removePuzzleFromPlaylist(puz);
    }
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
                        Text("Collection"),
                        SegmentedButton(
                          multiSelectionEnabled: false,
                          emptySelectionAllowed: false,
                          showSelectedIcon: false,
                          selected: collection,
                          onSelectionChanged: chooseCollection,
                          segments: collections
                              .map(
                                (slug) => ButtonSegment(
                                  value: slug.$1,
                                  label: Text(slug.$2),
                                ),
                              )
                              .toList(),
                        ),
                        Text("Shuffle"),
                        Switch(
                          value: widget.database.shouldShuffle,
                          onChanged: setShuffle,
                        )
                      ],
                    ),
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
                            ButtonSegment(
                              value: "played",
                              label: Text("Played"),
                            ),
                            ButtonSegment(
                              value: "skipped",
                              label: Text("Skipped"),
                            ),
                            ButtonSegment(value: "liked", label: Text("Liked")),
                            ButtonSegment(
                              value: "disliked",
                              label: Text("Disliked"),
                            ),
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
                            ButtonSegment(
                              value: "played",
                              label: Text("Played"),
                            ),
                            ButtonSegment(
                              value: "skipped",
                              label: Text("Skipped"),
                            ),
                            ButtonSegment(value: "liked", label: Text("Liked")),
                            ButtonSegment(
                              value: "disliked",
                              label: Text("Disliked"),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Divider(),
                    TextField(
                      onChanged: (value) =>
                          selectPuzzle(PuzzleData(value), context, false),
                      decoration: InputDecoration(
                        label: Text(
                          "Paste a puzzle representation here to open it",
                        ),
                      ),
                    ),
                    Divider(),
                    const Text("Dimensions"),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Width"),
                        PlusMinusField(
                          onChanged: (minValue, maxValue) {
                            final value = RangeValues(
                              minValue.toDouble(),
                              maxValue.toDouble(),
                            );
                            applyFilter(newWidth: value);
                          },
                          initialMin: widget.database.currentFilters.minWidth,
                          initialMax: widget.database.currentFilters.maxWidth,
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Height"),
                        PlusMinusField(
                          onChanged: (minValue, maxValue) {
                            final value = RangeValues(
                              minValue.toDouble(),
                              maxValue.toDouble(),
                            );
                            applyFilter(newHeight: value);
                          },
                          initialMin: widget.database.currentFilters.minHeight,
                          initialMax: widget.database.currentFilters.maxHeight,
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Fill ratio"),
                        PlusMinusField(
                          onChanged: (minValue, maxValue) {
                            final value = RangeValues(
                              minValue.toDouble(),
                              maxValue.toDouble(),
                            );
                            applyFilter(newPrefilled: value);
                          },
                          initialMin: widget.database.currentFilters.minFilled,
                          initialMax: widget.database.currentFilters.maxFilled,
                          minimum: 0,
                          maximum: 100,
                          increment: 5,
                        ),
                      ],
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
                            (slug) => ButtonSegment(
                              value: slug.$1,
                              label: Text(slug.$2),
                            ),
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
                            (slug) => ButtonSegment(
                              value: slug.$1,
                              label: Text(slug.$2),
                            ),
                          )
                          .toList(),
                    ),
                    Divider(),
                    Text("Puzzles matching filters: $matchingCount"),
                    Divider(),
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
