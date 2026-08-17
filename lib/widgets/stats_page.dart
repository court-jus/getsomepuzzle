import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/stats.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/constraints/registry.dart';
import 'package:getsomepuzzle/utils/share_outcome.dart';
import 'package:getsomepuzzle/utils/share_stub.dart'
    if (dart.library.html) 'package:getsomepuzzle/utils/share_html.dart'
    if (dart.library.io) 'package:getsomepuzzle/utils/share_io.dart';
import 'package:getsomepuzzle/utils/share_link_stub.dart'
    if (dart.library.html) 'package:getsomepuzzle/utils/share_link_html.dart'
    if (dart.library.io) 'package:getsomepuzzle/utils/share_link_io.dart';

const _kShareBaseUrl = 'https://leveque.cc/getsomepuzzle/play/';

const _durationFormat = 60;

String _formatDuration(double seconds) {
  final totalSec = seconds.round();
  if (totalSec < _durationFormat) return '${totalSec}s';
  final m = totalSec ~/ _durationFormat;
  final s = totalSec % _durationFormat;
  return s > 0 ? '${m}m${s}s' : '${m}m';
}

double _toOneDec(double v) => (v * 10).roundToDouble() / 10;

int _extractCplx(String puzzleLine) {
  final parts = puzzleLine.split('_');
  return parts.length > 6 ? (int.tryParse(parts[6]) ?? 0) : 0;
}

class StatsPage extends StatefulWidget {
  const StatsPage({super.key, required this.database});

  final Database database;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  List<String> stats = [];
  StatsDashboard? dashboard;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => loading = true);
    final entries = widget.database.getAllStatEntries();
    entries.sort((a, b) {
      final aFin = a.finished ?? '';
      final bFin = b.finished ?? '';
      return bFin.compareTo(aFin);
    });
    final lookup = await widget.database.getCollectionLookup();
    if (!mounted) return;
    setState(() {
      stats = [for (final e in entries) e.toString()];
      dashboard = StatsDashboard(entries, collectionLookup: lookup);
      loading = false;
    });
  }

  Future<void> setData() async {
    final content = stats.join('\n');
    final outcome = await shareData(content);
    if (!mounted) return;
    if (outcome == ShareOutcome.clipboard) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.statsCopiedToClipboard),
        ),
      );
    }
  }

  Future<void> _importData() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    final bytes = await picked.readAsBytes();
    final content = utf8.decode(bytes, allowMalformed: true);
    final added = await widget.database.importStats(content);
    if (!mounted) return;
    final loc = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added == 0
              ? loc.statsImportNothingValid
              : loc.statsImportSuccess(added),
        ),
      ),
    );
    if (added > 0) {
      await _loadStats();
    }
  }

  Future<void> _shareRecentPuzzle(StatEntry entry) async {
    final url =
        '$_kShareBaseUrl?puzzle=${Uri.encodeQueryComponent(entry.puzzleLine)}';
    final shared = await shareUrl(url);
    if (!mounted) return;
    if (!shared) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.shareLinkCopied)),
      );
    }
  }

  CollectionLabels _collectionLabels(AppLocalizations loc) =>
      CollectionLabels.fromLocalizations(loc);

  @override
  Widget build(BuildContext context) {
    final isDesktopFile = !kIsWeb && (Platform.isWindows || Platform.isLinux);
    final shareText = isDesktopFile
        ? AppLocalizations.of(context)!.open
        : AppLocalizations.of(context)!.btnShareStats;
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dimStyle = TextStyle(
      color: colorScheme.onSurface.withValues(alpha: 0.6),
      fontSize: 12,
    );

    return Scaffold(
      appBar: AppBar(title: Text(loc.stats)),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, viewportConstraints) {
            return SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: viewportConstraints.maxHeight,
                ),
                child: Column(
                  children: [
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: loading || stats.isEmpty ? null : setData,
                          label: Text(shareText),
                          icon: const Icon(Icons.copy),
                        ),
                        TextButton.icon(
                          onPressed: loading ? null : _importData,
                          label: Text(loc.btnImportStats),
                          icon: const Icon(Icons.file_upload),
                        ),
                      ],
                    ),
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      )
                    else if (dashboard == null || dashboard!.totalPlays == 0)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text('No stats yet', style: dimStyle),
                      )
                    else
                      _buildDashboard(context, loc, theme, colorScheme),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDashboard(
    BuildContext context,
    AppLocalizations loc,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final d = dashboard!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryGrid(d, loc, colorScheme),
          if (d.byCollection.isNotEmpty) ...[
            const SizedBox(height: 20),
            _buildSectionTitle(loc.statsSectionCollection),
            _buildCollectionSection(d, colorScheme, loc),
          ],
          const SizedBox(height: 20),
          _buildSectionTitle(loc.statsSectionConstraint),
          _buildConstraintSection(d, colorScheme, loc),
          const SizedBox(height: 20),
          _buildSectionTitle(loc.statsSectionDifficulty),
          _buildDifficultySection(d, colorScheme),
          if (d.likes + d.dislikes > 0) ...[
            const SizedBox(height: 20),
            _buildSectionTitle(loc.statsSectionRating),
            _buildRatingSection(d, loc, colorScheme),
          ],
          const SizedBox(height: 20),
          _buildSectionTitle(loc.statsSectionRecent),
          _buildRecentPlaysSection(d, colorScheme),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildSummaryGrid(
    StatsDashboard d,
    AppLocalizations loc,
    ColorScheme colorScheme,
  ) {
    final approval = d.likes + d.dislikes > 0
        ? '${(d.likes / (d.likes + d.dislikes) * 100).round()}%'
        : '—';
    final cards = [
      (d.totalPlays.toString(), loc.statsDashboardPlayed, colorScheme.primary),
      (
        d.finishedPlays.toString(),
        loc.statsDashboardFinished,
        colorScheme.primary,
      ),
      (
        _formatDuration(d.avgDuration),
        loc.statsDashboardAvgDuration,
        colorScheme.primary,
      ),
      (
        d.totalHints.toString(),
        loc.statsDashboardTotalHints,
        colorScheme.primary,
      ),
      (
        d.totalPlays > 0 ? _toOneDec(d.avgHintsPerPuzzle).toString() : '0',
        loc.statsDashboardHintsPerPuzzle,
        colorScheme.primary,
      ),
      (approval, loc.statsDashboardApproval, colorScheme.primary),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (value, label, color) in cards)
          SizedBox(
            width: (MediaQuery.of(context).size.width - 40) / 3,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 8,
                ),
                child: Column(
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: color,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                        letterSpacing: 0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDifficultySection(StatsDashboard d, ColorScheme colorScheme) {
    if (d.byDifficulty.isEmpty) return const SizedBox.shrink();
    final maxCount = d.byDifficulty
        .map((b) => b.count)
        .reduce((a, b) => a > b ? a : b);
    return Column(
      children: [
        for (final bucket in d.byDifficulty)
          _buildStatRow(
            label: 'cplx ${bucket.label}',
            subtitle:
                '${bucket.count} · ${_formatDuration(bucket.avgDuration)} · ${_toOneDec(bucket.avgHints)}h',
            progress: maxCount > 0 ? bucket.count / maxCount : 0.0,
            color: colorScheme.primary,
          ),
      ],
    );
  }

  Widget _buildCollectionSection(
    StatsDashboard d,
    ColorScheme colorScheme,
    AppLocalizations loc,
  ) {
    if (d.byCollection.isEmpty) return const SizedBox.shrink();
    final labels = _collectionLabels(loc);
    final maxCount = d.byCollection
        .map((b) => b.count)
        .reduce((a, b) => a > b ? a : b);
    return Column(
      children: [
        for (final bucket in d.byCollection)
          _buildStatRow(
            label: labels.labelFor(bucket.label) ?? loc.collectionMyPuzzles,
            subtitle:
                '${bucket.count} · ${_formatDuration(bucket.avgDuration)} · ${_toOneDec(bucket.avgHints)}h',
            progress: maxCount > 0 ? bucket.count / maxCount : 0.0,
            color: colorScheme.secondary,
          ),
      ],
    );
  }

  Widget _buildConstraintSection(
    StatsDashboard d,
    ColorScheme colorScheme,
    AppLocalizations loc,
  ) {
    if (d.byConstraint.isEmpty) return const SizedBox.shrink();
    final maxCount = d.byConstraint
        .map((b) => b.instanceCount)
        .reduce((a, b) => a > b ? a : b);
    return Column(
      children: [
        for (final bucket in d.byConstraint)
          _buildStatRow(
            label:
                '${bucket.slug} — ${_constraintDisplayName(loc, bucket.slug)}',
            subtitle: bucket.instanceCount == bucket.puzzleCount
                ? '${bucket.puzzleCount} pz · ${_formatDuration(bucket.avgDuration)}'
                : '${bucket.puzzleCount} pz (${bucket.instanceCount} ctr) · ${_formatDuration(bucket.avgDuration)}',
            progress: maxCount > 0 ? bucket.instanceCount / maxCount : 0.0,
            color: colorScheme.tertiary,
          ),
      ],
    );
  }

  /// Localised name for a constraint slug, falling back to the raw slug
  /// for legacy slugs (e.g. `TX`) that never entered the UI registry.
  String _constraintDisplayName(AppLocalizations loc, String slug) =>
      constraintSlugs.contains(slug) ? constraintNameForSlug(loc, slug) : slug;

  Widget _buildStatRow({
    required String label,
    required String subtitle,
    required double progress,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: color.withValues(alpha: 0.15),
                  color: color,
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRatingSection(
    StatsDashboard d,
    AppLocalizations loc,
    ColorScheme colorScheme,
  ) {
    final avg = d.avgPleasure;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Row(
          children: [
            Expanded(
              child: _buildRatingCol(
                '👍',
                d.likes.toString(),
                loc.statsDashboardLiked,
              ),
            ),
            SizedBox(
              width: 1,
              child: Container(color: colorScheme.outlineVariant),
            ),
            Expanded(
              child: _buildRatingCol(
                '👎',
                d.dislikes.toString(),
                loc.statsDashboardDisliked,
              ),
            ),
            SizedBox(
              width: 1,
              child: Container(color: colorScheme.outlineVariant),
            ),
            Expanded(
              child: _buildRatingCol(
                '★',
                avg != null ? _toOneDec(avg).toString() : '—',
                loc.statsDashboardAvgScore,
                valueColor: avg != null && avg > 0 ? Colors.greenAccent : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingCol(
    String emoji,
    String count,
    String label, {
    Color? valueColor,
  }) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 22)),
        const SizedBox(height: 2),
        Text(
          count,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentPlaysSection(StatsDashboard d, ColorScheme colorScheme) {
    if (d.recentPlays.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final entry in d.recentPlays) _buildRecentItem(entry, colorScheme),
      ],
    );
  }

  Widget _buildRecentItem(StatEntry entry, ColorScheme colorScheme) {
    final dim = colorScheme.onSurface.withValues(alpha: 0.6);
    final dateStr = entry.finished != null
        ? entry.finished!.substring(0, 19).replaceAll('T', ' · ')
        : '—';
    final w = entry.puzzleLine.split('_').length > 2
        ? entry.puzzleLine.split('_')[2]
        : '?';
    final cplx = _extractCplx(entry.puzzleLine).toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _shareRecentPuzzle(entry),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateStr,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$w · cplx $cplx',
                      style: TextStyle(fontSize: 12, color: dim),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _recentStat(entry.duration, 's', 'time'),
              const SizedBox(width: 12),
              _recentStat(entry.hints, '', 'hints'),
              const SizedBox(width: 8),
              Icon(Icons.link, size: 18, color: dim),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recentStat(int value, String suffix, String label) {
    final display = suffix == 's' && value >= 60
        ? _formatDuration(value.toDouble())
        : '$value$suffix';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          display,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}
