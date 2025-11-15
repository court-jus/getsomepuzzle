import 'package:flutter/material.dart';

class Initiallocalechooser extends StatelessWidget {
  const Initiallocalechooser({super.key, required this.selectLocale});
  final Function selectLocale;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 10,
      children: [
        OutlinedButton(
          onPressed: () => selectLocale("en"),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: const Text("English", style: TextStyle(fontSize: 24)),
          ),
        ),
        OutlinedButton(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: const Text("Español", style: TextStyle(fontSize: 24)),
          ),
          onPressed: () => selectLocale("es"),
        ),
        OutlinedButton(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: const Text("Français", style: TextStyle(fontSize: 24)),
          ),
          onPressed: () => selectLocale("fr"),
        ),
      ],
    );
  }
}
