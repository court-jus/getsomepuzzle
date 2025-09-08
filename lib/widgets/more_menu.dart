import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/database.dart';
import 'package:getsomepuzzle/widgets/help_page.dart';
import 'package:getsomepuzzle/widgets/stats_page.dart';

// This is the type used by the menu below.
enum SampleItem { itemOne, itemTwo, itemThree }

class MenuAnchorMore extends StatefulWidget {
  final Database database;
  final Function() togglePause;

  const MenuAnchorMore({
    super.key,
    required this.database,
    required this.togglePause,
  });

  @override
  State<MenuAnchorMore> createState() => _MenuAnchorMoreState();
}

class _MenuAnchorMoreState extends State<MenuAnchorMore> {
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
              icon: const Icon(Icons.more_horiz),
              tooltip: 'More...',
            );
          },
      menuChildren: [
        MenuItemButton(
          leadingIcon: Icon(Icons.newspaper),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (context) => StatsPage(database: widget.database),
              ),
            );
          },
          child: Text("Stats"),
        ),
        MenuItemButton(
          leadingIcon: Icon(Icons.help),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => HelpPage()),
            );
          },
          child: Text("Help"),
        ),
      ],
    );
  }
}
