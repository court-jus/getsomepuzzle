/// Returns true when a native share sheet was opened, false when the URL
/// was copied to the clipboard instead (caller should show feedback).
Future<bool> shareUrl(String url, {String? subject}) async => false;
