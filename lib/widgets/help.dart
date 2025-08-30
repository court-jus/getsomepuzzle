import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_md/flutter_md.dart';
import 'package:getsomepuzzle_ng/widgets/help_page.dart';

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
