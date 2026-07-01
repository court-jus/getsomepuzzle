import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Web target: copy the URL to the clipboard. The Web Share API exists but
/// is gated on user activation and not reliable across browsers; clipboard
/// is the lowest-friction primitive that works everywhere. Clipboard access
/// can fail (e.g. non-HTTPS, iframe) so both calls are guarded.
Future<bool> shareUrl(String url, {String? subject}) async {
  var copied = false;
  try {
    await Clipboard.setData(ClipboardData(text: url));
    copied = true;
  } catch (_) {
    // Clipboard unavailable — still try the native share sheet below.
  }
  // Best-effort: also try the native share sheet (mobile browsers) without
  // failing if the API is unavailable.
  try {
    await SharePlus.instance.share(
      ShareParams(uri: Uri.parse(url), subject: subject),
    );
    return true;
  } catch (_) {
    // Share sheet failed. If we copied to clipboard, signal the caller to
    // show the "copied" snackbar. If nothing worked, return true to avoid a
    // misleading snackbar.
    return !copied;
  }
}
