import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

class TimerBottomBar extends StatefulWidget {
  final PuzzleData? currentMeta;
  final Puzzle? currentPuzzle;
  final int dbSize;

  const TimerBottomBar({
    super.key,
    required this.currentMeta,
    required this.currentPuzzle,
    required this.dbSize,
  });

  @override
  State<TimerBottomBar> createState() => _TimerBottomBarState();
}

class _TimerBottomBarState extends State<TimerBottomBar> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.currentPuzzle != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.currentPuzzle == null) {
      return BottomAppBar(height: 40, color: Colors.amber, child: SizedBox());
    }
    return BottomAppBar(
      height: 40,
      color: Colors.amber,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "${widget.currentPuzzle!.width}x${widget.currentPuzzle!.height} (${widget.currentPuzzle!.width * widget.currentPuzzle!.height}) ",
              ),
              FaIcon(FontAwesomeIcons.brain, size: 12),
              Text(" ${widget.currentMeta!.cplx}"),
            ],
          ),
          Text(widget.currentMeta!.stats.toString()),
          Text("${widget.dbSize}"),
        ],
      ),
    );
  }
}
