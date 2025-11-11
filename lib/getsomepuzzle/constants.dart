import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';

const cellSizeToFontSize = 48.0 / 64.0;
const minConstraintsInTopBarSize = 60.0;
const motifConstraintInTopBarFillRatio = 0.7;

final mdTheme = MarkdownThemeData(
  textStyle: TextStyle(fontSize: 16.0, color: Colors.black87),
  h1Style: TextStyle(
    fontSize: 24.0,
    fontWeight: FontWeight.bold,
    color: Colors.blue,
  ),
  h2Style: TextStyle(
    fontSize: 22.0,
    fontWeight: FontWeight.bold,
    color: Colors.blueGrey,
  ),
  quoteStyle: TextStyle(
    fontSize: 14.0,
    fontStyle: FontStyle.italic,
    color: Colors.grey[600],
  ),
);
