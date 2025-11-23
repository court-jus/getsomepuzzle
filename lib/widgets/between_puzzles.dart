import 'package:flutter/material.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';

class BetweenPuzzles extends StatelessWidget {
  final Function(int) like;
  final Function() loadPuzzle;

  const BetweenPuzzles({
    super.key,
    required this.like,
    required this.loadPuzzle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 16,
      children: [
        Text(
          AppLocalizations.of(context)!.msgPuzzleSolved,
          style: TextStyle(fontSize: 48),
        ),
        Text(
          AppLocalizations.of(context)!.questionFunToPlay,
          style: TextStyle(fontSize: 24),
        ),
        Wrap(
          direction: Axis.horizontal,
          runAlignment: WrapAlignment.center,
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent[100],
                    minimumSize: Size(96, 96),
                    maximumSize: Size(128, 200),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadiusGeometry.circular(16),
                    ),
                  ),
                  onPressed: () => like(-2),
                  child: const Icon(
                    Icons.sentiment_very_dissatisfied,
                    size: 48,
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[100],
                    minimumSize: Size(96, 96),
                    maximumSize: Size(128, 200),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadiusGeometry.circular(16),
                    ),
                  ),
                  onPressed: () => like(-1),
                  child: const Icon(Icons.sentiment_dissatisfied, size: 48),
                ),
              ],
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[100],
                minimumSize: Size(96, 96),
                maximumSize: Size(128, 200),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadiusGeometry.circular(16),
                ),
              ),
              onPressed: () {
                loadPuzzle();
              },
              child: Icon(Icons.sentiment_neutral, size: 48),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[100],
                    minimumSize: Size(96, 96),
                    maximumSize: Size(128, 200),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadiusGeometry.circular(16),
                    ),
                  ),
                  onPressed: () => like(1),
                  child: const Icon(Icons.sentiment_satisfied, size: 48),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent[200],
                    minimumSize: Size(96, 96),
                    maximumSize: Size(128, 200),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadiusGeometry.circular(16),
                    ),
                  ),
                  onPressed: () => like(2),
                  child: const Icon(Icons.sentiment_very_satisfied, size: 48),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
