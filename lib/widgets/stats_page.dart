import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class StatsPage extends StatelessWidget {
  const StatsPage({super.key, required this.stats});

  final List<String> stats;

Future<void> setData() async {
  await SystemChannels.platform.invokeMethod<void>('Clipboard.setData', <String, dynamic>{
    'text': stats.join("\n"),
  });
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Stats')),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints viewportConstraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: viewportConstraints.maxHeight,
              ),
              child: Column(
                children: [
                  TextButton.icon(
                      onPressed: setData,
                      label: Text("Copy to clipboard"),
                      icon: Icon(Icons.copy),
                    ),
                  Container(
                    margin: EdgeInsets.all(8),
                    child: Text(
                      stats.join("\n"),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall!.copyWith(
                        fontFamily: "monospace",
                        fontFamilyFallback: ["Courier", "Courier New"]
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
