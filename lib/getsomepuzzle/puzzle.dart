// ignore_for_file: avoid_print
import 'package:collection/collection.dart';

class Puzzle {
  String lineRepresentation;
  List<int> domain = [];
  int width = 0;
  int height = 0;
  List<int> values = [];

  Puzzle(this.lineRepresentation) {
    print("New Puzzle $lineRepresentation");
    final attributesStr = lineRepresentation.split("_");
    final dimensions = attributesStr[1].split("x");
    domain = attributesStr[0].split("").map((e) => int.parse(e)).toList();
    width = int.parse(dimensions[0]);
    height = int.parse(dimensions[1]);
    values = attributesStr[2].split("").map((e) => int.parse(e)).toList();
  }

  List<List<int>> getRows() {
    // 12_4x5_00020210200022001201_FM:1.2;PA:10.top;PA:19.top_1:22222212221122111211
    print("dom $domain");
    print("dim $width   $height");
    print("VAL $values");
    final rows = values.slices(width);
    print("rows $rows");
    return rows.toList();
  }
}