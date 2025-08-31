import 'package:flutter/material.dart';
import 'package:getsomepuzzle/widgets/help_page.dart';

class Help extends StatefulWidget {
  const Help({super.key});

  @override
  State<Help> createState() => _HelpState();
}

class _HelpState extends State<Help> {

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.help),
      tooltip: 'Help',
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute<void>(
           builder: (context) => HelpPage(),
          ),
        );
      },
    );
  }
}
