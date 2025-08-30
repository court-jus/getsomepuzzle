import 'package:flutter/material.dart';
import 'package:getsomepuzzle_ng/widgets/help.dart';
import 'package:getsomepuzzle_ng/widgets/puzzle.dart';
import 'package:flutter/services.dart' show rootBundle;

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
  String topMessage = "";
  // Puzzle currentPuzzle = Puzzle("12_4x5_00020210200022001201_FM:1.2;PA:10.top;PA:19.top_1:22222212221122111211");
  Puzzle? currentPuzzle;
  List<String> unsolvedPuzzles = [];
  int puzzleCount = 0;
  bool shouldCheck = false;

  @override
  void initState() {
    super.initState();
    loadPuzzle();
  }

  String get bottomMessage {
    final int played = puzzleCount - unsolvedPuzzles.length;
    return "$played/$puzzleCount";
  }

  Future<List<String>> loadPuzzles() async {
    if (unsolvedPuzzles.isNotEmpty) return unsolvedPuzzles;
    final assetContent = await rootBundle.loadString('assets/puzzles.txt');
    unsolvedPuzzles = assetContent.split("\n");
    unsolvedPuzzles.shuffle();
    puzzleCount = unsolvedPuzzles.length;
    return unsolvedPuzzles;
  }

  void loadPuzzle() async {
    try {
      final unsolved = await loadPuzzles();

      final randomPuzzle = unsolved.removeAt(0);
      print("puzzle $randomPuzzle");
      setState(() {
        currentPuzzle = Puzzle(randomPuzzle);
      });
    } catch (e) {
      // If encountering an error, return 0
      print(e);
      return;
    }
  }

  void restartPuzzle() {
    if (currentPuzzle == null) return;
    setState(() {
      currentPuzzle!.restart();
    });
  }

  void handlePuzzleTap(int idx) {
    if (currentPuzzle == null) return;
    setState(() {
      currentPuzzle!.incrValue(idx);
      shouldCheck = currentPuzzle!.complete;
      if (shouldCheck) Future.delayed(Duration(seconds: 2), autoCheck);
    });
  }

  void autoCheck() {
    if (!shouldCheck) return;
    shouldCheck = false;
    if (currentPuzzle == null) return;
    final failedConstraints = currentPuzzle!.check();
    if (failedConstraints.isEmpty) {
      if (currentPuzzle!.complete) loadPuzzle();
    } else {
      setState(() {
        topMessage = "Some constraints are not valid.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: Icon(Icons.fiber_new),
            tooltip: "New",
            onPressed: loadPuzzle,
          ),
          IconButton(
            icon: Icon(Icons.restart_alt_rounded),
            tooltip: "Restart",
            onPressed: restartPuzzle,
          ),
          Help(),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 2,
          children: <Widget>[
            Text(topMessage),
            (currentPuzzle != null)
                ? PuzzleWidget(
                    currentPuzzle: currentPuzzle!,
                    onCellTap: handlePuzzleTap,
                  )
                : Text("No puzzle loaded."),

            DecoratedBox(
              decoration: BoxDecoration(color: Colors.amber),
              child: Row(
                spacing: 2,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    margin: EdgeInsets.all(4),
                    child: Text(bottomMessage),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
