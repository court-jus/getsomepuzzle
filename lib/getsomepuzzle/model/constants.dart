import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';

const cellSizeToFontSize = 44.0 / 64.0;
const minConstraintsInTopBarSize = 60.0;
const motifConstraintInTopBarFillRatio = 0.7;

final mdTheme = MarkdownThemeData(
  textStyle: TextStyle(fontSize: 16.0, color: Color(0xFF657B83)), // base00
  h1Style: TextStyle(
    fontSize: 24.0,
    fontWeight: FontWeight.bold,
    color: Color(0xFF268BD2), // solarized blue
  ),
  h2Style: TextStyle(
    fontSize: 22.0,
    fontWeight: FontWeight.bold,
    color: Color(0xFF586E75), // base01
  ),
  quoteStyle: TextStyle(
    fontSize: 14.0,
    fontStyle: FontStyle.italic,
    color: Color(0xFF93A1A1), // base1
  ),
);
