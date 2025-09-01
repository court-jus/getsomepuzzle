import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';

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
  RangeValues widthSlider = RangeValues(3, 7);
  RangeValues heightSlider = RangeValues(3, 8);

  @override
  void initState() {
    super.initState();
    setState(() {
      shownPuzzles = widget.puzzles.where((puz) => puz.isNotEmpty).take(10).map((puz) {
        final pu = Puzzle(puz);
        return ["${pu.width}x${pu.height}", puz];
      }).toList();
    });
  }

  void applyFilter({RangeValues? newWidth, RangeValues? newHeight}) {
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
      if (changed) {
        shownPuzzles = widget.puzzles.where((puz) => puz.isNotEmpty).map((puz) => Puzzle(puz)).where((puz) {
          return (
            puz.width >= widthSlider.start &&
            puz.width <= widthSlider.end &&
            puz.height >= heightSlider.start &&
            puz.height <= heightSlider.end
          );
        }).take(10).map((puz) => ["${puz.width}x${puz.height}", puz.lineRepresentation]).toList();
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
                      max: 7,
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
