import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

Future<void> shareData(String content, String filename) async {
    if (kIsWeb) {
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
    }
}