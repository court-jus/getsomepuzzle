import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:getsomepuzzle/utils/share_outcome.dart';
import 'package:web/web.dart' as web;

String _two(int v) => v.toString().padLeft(2, '0');

Future<ShareOutcome> shareData(String content) async {
  if (!kIsWeb) return ShareOutcome.failed;
  final now = DateTime.now();
  final filename = 'stats_${now.year}${_two(now.month)}${_two(now.day)}.txt';
  final jsContent = content.toJS;
  final JSArray<JSAny> jsArray = JSArray();
  jsArray.add(jsContent);
  final blob = web.Blob(jsArray, web.BlobPropertyBag(type: 'text/plain'));
  final url = web.URL.createObjectURL(blob);
  web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..click();
  web.URL.revokeObjectURL(url);
  return ShareOutcome.opened;
}
