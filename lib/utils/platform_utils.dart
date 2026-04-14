import 'dart:io';

import 'package:flutter/foundation.dart';

bool get isDesktopOrWeb {
  if (kIsWeb) return true;
  return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
}
