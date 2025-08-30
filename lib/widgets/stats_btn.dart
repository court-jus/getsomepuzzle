import 'package:flutter/material.dart';
import 'package:getsomepuzzle_ng/widgets/stats_page.dart';

class StatsBtn extends StatelessWidget {
  const StatsBtn({super.key, required this.stats});

  final List<String> stats;

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
            stats: stats,
           ),
          ),
        );
      },
    );
  }
}
