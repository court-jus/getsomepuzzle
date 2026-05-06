import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/game_model.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';

/// App-wide navigation drawer (left side).
///
/// Pure presentation widget: declares the menu structure and forwards every
/// click to a typed callback. Navigation pushes and state mutations live in
/// the parent (`_MyHomePageState`) so the drawer stays decoupled from the
/// app's lifecycle and dependency wiring.
///
/// Each entry pops the drawer first (so it disappears synchronously) before
/// invoking its callback, freeing callers from having to remember `Navigator
/// .pop(context)` in every handler.
class MainDrawer extends StatelessWidget {
  const MainDrawer({
    super.key,
    required this.title,
    required this.versionText,
    required this.authorText,
    required this.database,
    required this.game,
    required this.onLoadPuzzleSkipped,
    required this.onSaveProgress,
    required this.onSharePuzzle,
    required this.onBrowse,
    required this.onGenerate,
    required this.onCreate,
    required this.onStats,
    required this.onLearning,
    required this.onSettings,
    required this.onHelp,
  });

  final String title;
  final String versionText;
  final String authorText;
  final Database? database;
  final GameModel game;

  /// "Current puzzle" section. Shown only when both [database] is loaded
  /// and a puzzle is in play.
  final VoidCallback onLoadPuzzleSkipped;
  final VoidCallback onSaveProgress;
  final VoidCallback onSharePuzzle;

  /// "Library" section. Shown only when [database] is loaded.
  final VoidCallback onBrowse;
  final VoidCallback onGenerate;
  final VoidCallback onCreate;

  /// "Progress" section. Shown only when [database] is loaded.
  final VoidCallback onStats;
  final VoidCallback onLearning;

  /// Always visible.
  final VoidCallback onSettings;
  final VoidCallback onHelp;

  /// Drawer collapsible section: an [ExpansionTile] whose header is a
  /// small uppercase primary-coloured label. Children are shown only
  /// when the section is expanded — keeps the drawer compact.
  Widget _drawerSection(
    BuildContext context, {
    required String title,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) {
    final theme = Theme.of(context);
    return ExpansionTile(
      title: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          letterSpacing: 1.0,
          fontWeight: FontWeight.w600,
        ),
      ),
      initiallyExpanded: initiallyExpanded,
      childrenPadding: EdgeInsets.zero,
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      shape: const Border(),
      collapsedShape: const Border(),
      children: children,
    );
  }

  /// Build a drawer menu entry that closes the drawer before invoking
  /// [onTap]. Saves every caller from repeating `Navigator.pop(context)`.
  ListTile _entry(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Colors.blue),
            child: Column(
              children: [
                Text(title, style: const TextStyle(fontSize: 24)),
                Text(versionText),
                const SizedBox(height: 10),
                Text(authorText),
              ],
            ),
          ),
          if (database != null && game.currentPuzzle != null)
            _drawerSection(
              context,
              title: l10n.menuSectionCurrentPuzzle,
              initiallyExpanded: true,
              children: [
                _entry(
                  context,
                  icon: Icons.skip_next,
                  label: l10n.nextPuzzle,
                  onTap: onLoadPuzzleSkipped,
                ),
                _entry(
                  context,
                  icon: Icons.save_outlined,
                  label: l10n.saveProgress,
                  onTap: onSaveProgress,
                ),
                _entry(
                  context,
                  icon: Icons.share_outlined,
                  label: l10n.sharePuzzle,
                  onTap: onSharePuzzle,
                ),
              ],
            ),
          if (database != null)
            _drawerSection(
              context,
              title: l10n.menuSectionLibrary,
              children: [
                _entry(
                  context,
                  icon: Icons.file_open,
                  label: l10n.browse,
                  onTap: onBrowse,
                ),
                _entry(
                  context,
                  icon: Icons.auto_fix_high,
                  label: l10n.generate,
                  onTap: onGenerate,
                ),
                _entry(
                  context,
                  icon: Icons.edit,
                  label: l10n.create,
                  onTap: onCreate,
                ),
              ],
            ),
          if (database != null)
            _drawerSection(
              context,
              title: l10n.menuSectionProgress,
              children: [
                _entry(
                  context,
                  icon: Icons.newspaper,
                  label: l10n.stats,
                  onTap: onStats,
                ),
                _entry(
                  context,
                  icon: Icons.school,
                  label: l10n.learning,
                  onTap: onLearning,
                ),
              ],
            ),
          _entry(
            context,
            icon: Icons.settings,
            label: l10n.settings,
            onTap: onSettings,
          ),
          _entry(context, icon: Icons.help, label: l10n.help, onTap: onHelp),
        ],
      ),
    );
  }
}
