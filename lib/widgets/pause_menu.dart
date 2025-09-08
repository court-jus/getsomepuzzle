import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/database.dart';
import 'package:getsomepuzzle/widgets/open_page.dart';

// This is the type used by the menu below.
enum SampleItem { itemOne, itemTwo, itemThree }

class MenuAnchorPause extends StatefulWidget {
  const MenuAnchorPause({
    super.key,
    required this.database,
    required this.togglePause,
    required this.newPuzzle,
    required this.selectPuzzle,
    required this.restartPuzzle,
  });

  final Database database;
  final Function() togglePause;
  final Function() newPuzzle;
  final Function(PuzzleData) selectPuzzle;
  final Function() restartPuzzle;

  @override
  State<MenuAnchorPause> createState() => _MenuAnchorPauseState();
}

class _MenuAnchorPauseState extends State<MenuAnchorPause> {
  SampleItem? selectedMenu;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder:
          (BuildContext context, MenuController controller, Widget? child) {
            return IconButton(
              onPressed: () {
                widget.togglePause();
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
              icon: const Icon(Icons.pause),
              tooltip: 'Pause...',
            );
          },
      menuChildren: [
        MenuItemButton(
          leadingIcon: Icon(Icons.fiber_new),
          onPressed: widget.newPuzzle,
          child: Text("New"),
        ),
        MenuItemButton(
          leadingIcon: Icon(Icons.file_open),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (context) => OpenPage(
                  database: widget.database,
                  onPuzzleSelected: widget.selectPuzzle,
                ),
              ),
            );
          },
          child: Text("Open"),
        ),
        MenuItemButton(
          leadingIcon: Icon(Icons.restart_alt_rounded),
          onPressed: widget.restartPuzzle,
          child: Text("Restart"),
        ),
      ],
    );
  }
}
