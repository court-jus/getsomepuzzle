import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/database.dart';
import 'package:getsomepuzzle/widgets/stats_page.dart';

class StatsBtn extends StatelessWidget {
  const StatsBtn({super.key, required this.database});

  final Database database;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.newspaper),
      tooltip: 'Stats',
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute<void>(
           builder: (context) => StatsPage(
            database: database,
           ),
          ),
        );
      },
    );
  }
}
