import 'package:flutter/material.dart';
import 'package:getsomepuzzle_ng/widgets/puzzle.dart';

import 'getsomepuzzle/puzzle.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Get Some Puzzle',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Get Some Puzzle'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool helpVisible = false;
  String something =
      "FM:211;PA:16.left;PA:41.top;PA:40.top;pa:28.left;FM:112;FM:2.2;PA:26.top;PA:38:left;PA:46.left;PA:25.top";
  // Puzzle currentPuzzle = Puzzle("12_4x5_00020210200022001201_FM:1.2;PA:10.top;PA:19.top_1:22222212221122111211");
  Puzzle currentPuzzle = Puzzle(
    "12_6x8_102102111011000120110111021202101010021210012020_FM:211;PA:16.left;PA:41.top;PA:40.top;PA:28.left;FM:112;FM:2.2;PA:26.top;PA:38.left;PA:46.left;PA:25.top",
  );

  void _showHelp() {
    setState(() {
      helpVisible = true;
    });
  }

  void _handlePuzzleTap(int idx) {
    setState(() {
      currentPuzzle.incrValue(idx);
    });
  }

  void _handleCheck() {
    setState(() {
      something = currentPuzzle.check().map((c) => c.toString()).join(", ");
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(something),
            PuzzleWidget(
              currentPuzzle: currentPuzzle,
              onCellTap: _handlePuzzleTap,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.amber
              ),
              child: IconButton(
                onPressed: _handleCheck, icon: Icon(Icons.check)
                ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showHelp,
        tooltip: 'Help',
        child: const Icon(Icons.help),
      ),
    );
  }
}
