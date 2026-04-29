import 'dart:io';

import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Mobile/macOS open the system share sheet via share_plus; Linux/Windows
/// don't have one — fall back to copying the URL to the clipboard. Returns
/// true on share-sheet path, false on clipboard path so the caller can
/// surface a "copied to clipboard" snackbar.
Future<bool> shareUrl(String url, {String? subject}) async {
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    final params = ShareParams(uri: Uri.parse(url), subject: subject);
    await SharePlus.instance.share(params);
    return true;
  }
  await Clipboard.setData(ClipboardData(text: url));
  return false;
}
