import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OpenPage extends StatefulWidget {
  final List<String> puzzles;
  final List<String> solvedPuzzles;
  final dynamic Function(String puz) onPuzzleSelected;

  const OpenPage({
    super.key,
    required this.puzzles,
    required this.solvedPuzzles,
    required this.onPuzzleSelected,
  });

  @override
  State<OpenPage> createState() => _OpenPageState();
}

class _OpenPageState extends State<OpenPage> {
  List<List<String>> shownPuzzles = [];
  RangeValues widthSlider = RangeValues(3, 6);
  RangeValues heightSlider = RangeValues(3, 8);
  RangeValues prefilledSlider = RangeValues(0, 100);
  List<String> wantedRules = [];
  List<String> bannedRules = [];
  String manualLoad = "";

  @override
  void initState() {
    super.initState();
    loadFilters();
    setState(() {
      shownPuzzles = widget.puzzles.where((puz) => puz.isNotEmpty).take(10).map((puz) {
        final pu = Puzzle(puz);
        return ["${pu.width}x${pu.height}", puz];
      }).toList();
    });
  }

  void loadFilters() async {
    final prefs = await SharedPreferences.getInstance();
    final newWidth = RangeValues(
      prefs.getDouble("minWidthFilter") ?? 3,
      prefs.getDouble("maxWidthFilter") ?? 6,
    );
    final newHeight = RangeValues(
      prefs.getDouble("minHeightFilter") ?? 3,
      prefs.getDouble("maxHeightFilter") ?? 8,
    );
    final newPrefilled = RangeValues(
      prefs.getDouble("minPrefilledFilter") ?? 0,
      prefs.getDouble("maxPrefilledFilter") ?? 100,
    );
    applyFilter(
      newWidth: newWidth,
      newHeight: newHeight,
      newPrefilled: newPrefilled,
      newWRules: prefs.getStringList("wantedRulesFilter") ?? [],
      newBRules: prefs.getStringList("bannedRulesFilter") ?? [],
    );
  }

  void saveFilters() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setDouble("minWidthFilter", widthSlider.start);
    prefs.setDouble("maxWidthFilter", widthSlider.end);
    prefs.setDouble("minHeightFilter", heightSlider.start);
    prefs.setDouble("maxHeightFilter", heightSlider.end);
    prefs.setDouble("minPrefilledFilter", prefilledSlider.start);
    prefs.setDouble("maxPrefilledFilter", prefilledSlider.end);
    prefs.setStringList("wantedRulesFilter", wantedRules);
    prefs.setStringList("bannedRulesFilter", bannedRules);
  }

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
        widthSlider = newWidth;
        changed = true;
      }
      if (newHeight != null) {
        heightSlider = newHeight;
        changed = true;
      }
      if (newPrefilled != null) {
        prefilledSlider = newPrefilled;
        changed = true;
      }
      if (newWRules != null) {
        wantedRules = newWRules;
        changed = true;
      }
      if (newBRules != null) {
        bannedRules = newBRules;
        changed = true;
      }
      if (changed) {
        shownPuzzles = widget.puzzles.where((puz) => puz.isNotEmpty).map((puz) => Puzzle(puz)).where((puz) {
          final double pref = (puz.cellValues.where((v) => v == 0).length / puz.cellValues.length) * 100;
          if (wantedRules.isNotEmpty || bannedRules.isNotEmpty) {
            final lineAttr = puz.lineRepresentation.split("_");
            final rules = ((lineAttr.length == 5) ? lineAttr[3] : lineAttr[2]).split(";").map((r) => r.split(":")[0]).toSet();
            final wanted = wantedRules.toSet();
            final banned = bannedRules.toSet();
            if (wanted.isNotEmpty && wanted.intersection(rules).isEmpty) return false;
            if (banned.isNotEmpty && banned.intersection(rules).isNotEmpty) return false;
          }
          return (
            puz.width >= widthSlider.start &&
            puz.width <= widthSlider.end &&
            puz.height >= heightSlider.start &&
            puz.height <= heightSlider.end &&
            pref >= prefilledSlider.start &&
            pref <= prefilledSlider.end
          );
        }).take(30).map((puz) {
            final lineAttr = puz.lineRepresentation.split("_");
            final rules = ((lineAttr.length == 5) ? lineAttr[3] : lineAttr[2]).split(";").map((r) => r.split(":")[0]).toSet().join(" ");
          return ["${puz.width}x${puz.height}\n$rules", puz.lineRepresentation];
        }).toList();
        saveFilters();
      }
    });
  }

  void selectPuzzle(String puz, BuildContext context) {
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
                    RangeSlider(
                      divisions: 4,
                      values: widthSlider,
                      onChanged: (value) => applyFilter(newWidth: value),
                      min: 3,
                      max: 6,
                      labels: RangeLabels(
                        widthSlider.start.round().toString(),
                        widthSlider.end.round().toString(),
                      ),
                    ),
                    RangeSlider(
                      divisions: 5,
                      values: heightSlider,
                      onChanged: (value) => applyFilter(newHeight: value),
                      min: 3,
                      max: 8,
                      labels: RangeLabels(
                        heightSlider.start.round().toString(),
                        heightSlider.end.round().toString(),
                      ),
                    ),
                    RangeSlider(
                      values: prefilledSlider,
                      onChanged: (value) => applyFilter(newPrefilled: value),
                      min: 0,
                      max: 100,
                      labels: RangeLabels(
                        prefilledSlider.start.round().toString(),
                        prefilledSlider.end.round().toString(),
                      ),
                    ),
                    TextField(
                      onChanged: (value) => applyFilter(newWRules: value.split(" ")),
                    ),
                    TextField(
                      onChanged: (value) => applyFilter(newBRules: value.split(" ")),
                    ),
                    TextField(
                      onChanged: (value) {
                        manualLoad = value;
                        selectPuzzle(value, context);
                      }
                    ),
                    Wrap(
                      direction: Axis.horizontal,
                      alignment: WrapAlignment.center,
                      spacing: 2,
                      runSpacing: 2,
                      children: [
                        for (final puz in shownPuzzles)
                          TextButton(
                            child: Text(puz[0]),
                            onPressed: () {
                              selectPuzzle(puz[1], context);
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
