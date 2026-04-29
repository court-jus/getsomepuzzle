import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Web target: copy the URL to the clipboard. The Web Share API exists but
/// is gated on user activation and not reliable across browsers; clipboard
/// is the lowest-friction primitive that works everywhere.
Future<bool> shareUrl(String url, {String? subject}) async {
  await Clipboard.setData(ClipboardData(text: url));
  // Best-effort: also try the native share sheet (mobile browsers) without
  // failing if the API is unavailable.
  try {
    await SharePlus.instance.share(
      ShareParams(uri: Uri.parse(url), subject: subject),
    );
    return true;
  } catch (_) {
    return false;
  }
}
