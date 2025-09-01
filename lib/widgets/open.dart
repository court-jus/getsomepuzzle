import 'package:flutter/material.dart';
import 'package:getsomepuzzle/widgets/open_page.dart';

class Open extends StatefulWidget {
  final List<String> puzzles;
  final List<String> solvedPuzzles;
  final dynamic Function(String puz) onPuzzleSelected;

  const Open({
    super.key,
    required this.puzzles,
    required this.solvedPuzzles,
    required this.onPuzzleSelected,
  });

  @override
  State<Open> createState() => _OpenState();
}

class _OpenState extends State<Open> {
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.file_open),
      tooltip: "Open",
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (context) => OpenPage(
              puzzles: widget.puzzles,
              solvedPuzzles: widget.solvedPuzzles,
              onPuzzleSelected: widget.onPuzzleSelected,
            ),
          ),
        );
      },
    );
  }
}
