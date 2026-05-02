import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Per-constraint mastery tracker. Records the date a player first
/// encountered a given slug — used by the onboarding system to decide
/// whether to surface the explanation modal, and by the Apprentissage
/// page to display "vue le …" labels.
///
/// Persistence: a single `SharedPreferences` entry under
/// [_prefsKey], holding a JSON map `slug → ISO-8601 date`. The on-disk
/// representation is regularly fully overwritten by [save]; we never
/// merge in place at the prefs layer, so callers must hold the
/// canonical state in this object.
///
/// Reconstruction safety: [noteSeen] takes `min(existing, when)` so
/// stats lines processed in non-chronological order still converge to
/// the genuine earliest play date — preserving the "first seen"
/// semantic and leaving room for later "you learnt this rule N months
/// ago, want a refresher?" prompts.
class ConstraintProgress {
  static const _prefsKey = 'constraintFirstSeen';

  final Map<String, DateTime> _firstSeen = {};

  /// Read-only view of the current map.
  Map<String, DateTime> get firstSeen => Map.unmodifiable(_firstSeen);

  /// Whether the player has never seen this slug before.
  bool isFirstTimeFor(String slug) => !_firstSeen.containsKey(slug);

  /// Record that the player has just encountered [slug] at [when].
  /// Keeps the **earliest** date if one was already stored, so the
  /// invariant "firstSeen[slug] is the genuine first encounter" holds
  /// regardless of the order in which stats are replayed.
  /// Returns true iff the stored value changed.
  bool noteSeen(String slug, DateTime when) {
    final existing = _firstSeen[slug];
    if (existing == null || when.isBefore(existing)) {
      _firstSeen[slug] = when;
      return true;
    }
    return false;
  }

  /// Forget every recorded encounter. Used by the "Rejouer
  /// l'onboarding" button — does not touch play stats.
  void clear() {
    _firstSeen.clear();
  }

  /// Hydrate from `SharedPreferences`. Silently resets to empty if the
  /// stored payload is missing or malformed (forward-compat with
  /// future formats and corrupted prefs).
  Future<void> load() async {
    _firstSeen.clear();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      decoded.forEach((key, value) {
        if (key is! String || value is! String) return;
        final parsed = DateTime.tryParse(value);
        if (parsed != null) _firstSeen[key] = parsed;
      });
    } catch (_) {
      // Malformed JSON — drop and start fresh rather than crash on next
      // launch.
    }
  }

  /// Persist the current map to `SharedPreferences`. Always overwrites
  /// the full payload — callers don't need to merge.
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, String>{
      for (final e in _firstSeen.entries) e.key: e.value.toIso8601String(),
    };
    await prefs.setString(_prefsKey, jsonEncode(payload));
  }

  /// Extract the constraint slugs declared in a v2 puzzle line.
  /// Pure-string: no `Puzzle` parsing, safe to call on every stat line
  /// at load time. Skips the legacy `TX` slug (HelpText) and any
  /// leading/trailing empty entries.
  static Set<String> slugsFromLine(String puzzleLine) {
    final parts = puzzleLine.split('_');
    // v2_<domain>_<wxh>_<prefill>_<constraints>_…
    if (parts.length < 5) return const <String>{};
    final start = parts[0].startsWith('v') ? 4 : 3;
    if (start >= parts.length) return const <String>{};
    final result = <String>{};
    for (final raw in parts[start].split(';')) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      final colon = trimmed.indexOf(':');
      final slug = colon < 0 ? trimmed : trimmed.substring(0, colon);
      if (slug.isEmpty || slug == 'TX') continue;
      result.add(slug);
    }
    return result;
  }
}
