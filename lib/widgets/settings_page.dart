import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/settings.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/saf_access.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';

class SettingsPage extends StatefulWidget {
  final Settings settings;
  final ValueChanged<ChangeableSettings> onSettingsChange;

  /// Callback that wipes **every** persisted stat across every
  /// collection. Awaited so the snackbar only fires after the async
  /// work is done.
  final Future<void> Function() onClearStats;

  /// Callback that resets the constraint-discovery progress so the
  /// new-rule modals fire again. Does **not** touch play stats.
  final Future<void> Function() onReplayOnboarding;

  /// Callback that triggers the full-screen locale chooser. Invoked
  /// after the settings page pops itself so the chooser is revealed
  /// in the main scaffold.
  final VoidCallback onChangeLanguage;

  /// Called when the user picks or clears a stats sync directory.
  /// Passes the absolute path, or null to revert to the default location.
  final Future<void> Function(String?) onStatsDirectoryChanged;

  /// Error description for the stats sync directory, shown in red
  /// below the directory path when the directory is inaccessible.
  final String? statsDirectoryError;

  const SettingsPage({
    super.key,
    required this.settings,
    required this.onSettingsChange,
    required this.onClearStats,
    required this.onReplayOnboarding,
    required this.onChangeLanguage,
    required this.onStatsDirectoryChanged,
    this.statsDirectoryError,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Transient slider value while the player is dragging the level
  // slider. Showing it locally keeps the label following the thumb
  // without notifying the parent on every tick — `onSettingsChange`
  // (and its costly playlist recompute) only fires once, on release.
  int? _pendingPlayerLevel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints viewportConstraints) {
            return SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: viewportConstraints.maxHeight,
                ),
                child: Container(
                  margin: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(l10n.tooltipLanguage),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.language),
                            label: Text(_localeDisplayName(context)),
                            onPressed: () {
                              Navigator.of(context).pop();
                              widget.onChangeLanguage();
                            },
                          ),
                        ],
                      ),
                      _EnumSettingRow<ThemeModeType>(
                        label: l10n.settingTheme,
                        value: widget.settings.themeMode,
                        options: ThemeModeType.values,
                        labels: {
                          ThemeModeType.system: l10n.settingThemeSystem,
                          ThemeModeType.light: l10n.settingThemeLight,
                          ThemeModeType.dark: l10n.settingThemeDark,
                        },
                        onChanged: (v) => setState(() {
                          widget.onSettingsChange(
                            ChangeableSettings(themeMode: v),
                          );
                        }),
                      ),
                      _EnumSettingRow<ValidateType>(
                        label: l10n.settingValidateType,
                        value: widget.settings.validateType,
                        // ValidateType.intermediate is intentionally excluded.
                        options: const [
                          ValidateType.manual,
                          ValidateType.automatic,
                        ],
                        labels: {
                          ValidateType.manual: l10n.settingValidateTypeManual,
                          ValidateType.intermediate:
                              l10n.settingValidateTypeDefault,
                          ValidateType.automatic:
                              l10n.settingValidateTypeAutomatic,
                        },
                        onChanged: (v) => setState(() {
                          widget.onSettingsChange(
                            ChangeableSettings(validateType: v),
                          );
                        }),
                      ),
                      _EnumSettingRow<ShowRating>(
                        label: l10n.settingShowRating,
                        value: widget.settings.showRating,
                        options: ShowRating.values,
                        labels: {
                          ShowRating.yes: l10n.settingShowRatingYes,
                          ShowRating.no: l10n.settingShowRatingNo,
                        },
                        onChanged: (v) => setState(() {
                          widget.onSettingsChange(
                            ChangeableSettings(showRating: v),
                          );
                        }),
                      ),
                      _EnumSettingRow<LiveCheckType>(
                        label: l10n.settingsLiveCheckType,
                        value: widget.settings.liveCheckType,
                        options: LiveCheckType.values,
                        labels: {
                          LiveCheckType.all: l10n.settingsLiveCheckTypeAll,
                          LiveCheckType.count: l10n.settingsLiveCheckTypeCount,
                          LiveCheckType.complete:
                              l10n.settingsLiveCheckTypeComplete,
                        },
                        onChanged: (v) => setState(() {
                          widget.onSettingsChange(
                            ChangeableSettings(liveCheckType: v),
                          );
                        }),
                      ),
                      _EnumSettingRow<HintType>(
                        label: l10n.settingHintType,
                        value: widget.settings.hintType,
                        options: HintType.values,
                        labels: {
                          HintType.deducibleCell:
                              l10n.settingHintTypeDeducibleCell,
                          HintType.addConstraint:
                              l10n.settingHintTypeAddConstraint,
                        },
                        onChanged: (v) => setState(() {
                          widget.onSettingsChange(
                            ChangeableSettings(hintType: v),
                          );
                        }),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(l10n.settingGrayoutEnabled),
                          Switch(
                            value: widget.settings.grayoutEnabled,
                            onChanged: (newValue) {
                              setState(() {
                                widget.onSettingsChange(
                                  ChangeableSettings(grayoutEnabled: newValue),
                                );
                              });
                            },
                          ),
                        ],
                      ),
                      _EnumSettingRow<IdleTimeout>(
                        label: l10n.settingIdleTimeout,
                        value: widget.settings.idleTimeout,
                        options: IdleTimeout.values,
                        labels: {
                          IdleTimeout.disabled: l10n.settingIdleTimeoutDisabled,
                          IdleTimeout.s5: l10n.settingIdleTimeoutS5,
                          IdleTimeout.s10: l10n.settingIdleTimeoutS10,
                          IdleTimeout.s30: l10n.settingIdleTimeoutS30,
                          IdleTimeout.m1: l10n.settingIdleTimeoutM1,
                          IdleTimeout.m2: l10n.settingIdleTimeoutM2,
                        },
                        onChanged: (v) => setState(() {
                          widget.onSettingsChange(
                            ChangeableSettings(idleTimeout: v),
                          );
                        }),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.settingDifficultyLevel,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(l10n.settingPlayerLevel),
                              if (widget.settings.autoLevel) ...[
                                const SizedBox(width: 8),
                                Text(
                                  "(${l10n.settingPlayerLevelAuto})",
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(fontStyle: FontStyle.italic),
                                ),
                              ],
                            ],
                          ),
                          SizedBox(
                            width: 150,
                            child: Slider(
                              value:
                                  (_pendingPlayerLevel ??
                                          widget.settings.playerLevel)
                                      .toDouble(),
                              min: 0,
                              max: 100,
                              divisions: 100,
                              label:
                                  (_pendingPlayerLevel ??
                                          widget.settings.playerLevel)
                                      .toString(),
                              // Track the drag locally so the label/thumb
                              // follow the finger, but do not notify the
                              // parent on every tick.
                              onChanged: widget.settings.autoLevel
                                  ? null
                                  : (newValue) {
                                      setState(() {
                                        _pendingPlayerLevel = newValue.toInt();
                                      });
                                    },
                              // Commit once, on release: this is the only
                              // event that triggers the playlist recompute.
                              onChangeEnd: widget.settings.autoLevel
                                  ? null
                                  : (newValue) {
                                      widget.onSettingsChange(
                                        ChangeableSettings(
                                          playerLevel: newValue.toInt(),
                                        ),
                                      );
                                      setState(() {
                                        _pendingPlayerLevel = null;
                                      });
                                    },
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(l10n.settingAutoLevel),
                          Switch(
                            value: widget.settings.autoLevel,
                            onChanged: (newValue) {
                              setState(() {
                                widget.onSettingsChange(
                                  ChangeableSettings(autoLevel: newValue),
                                );
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.replay),
                          label: Text(l10n.settingReplayOnboarding),
                          onPressed: _confirmReplayOnboarding,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          icon: Icon(
                            Icons.delete_forever,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          label: Text(
                            l10n.settingClearStats,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          onPressed: _confirmClearStats,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          l10n.statsSyncDirectory,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _StatsDirectoryRow(
                        path: widget.settings.statsDirectory,
                        error: widget.statsDirectoryError,
                        onChange: (path) async {
                          await widget.onStatsDirectoryChanged(path);
                          if (mounted) setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmReplayOnboarding() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.settingReplayOnboardingConfirmTitle),
        content: Text(l10n.settingReplayOnboardingConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.onReplayOnboarding();
    if (!mounted) return;
    // Close the settings page so the freshly-loaded P0 puzzle (and
    // its "Nouvelle règle" modal) is revealed immediately — staying
    // on settings would hide the visible feedback of the reset.
    Navigator.of(context).pop();
  }

  Future<void> _confirmClearStats() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.settingClearStatsConfirmTitle),
        content: Text(l10n.settingClearStatsConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.onClearStats();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.settingStatsCleared)));
  }
}

String _localeDisplayName(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  switch (code) {
    case 'fr':
      return 'Français';
    case 'es':
      return 'Español';
    default:
      return 'English';
  }
}

/// Convert a `content://` tree URI to a human-readable filesystem path
/// for display in the UI. Non-content URIs are returned unchanged.
String _contentUriToDisplayPath(String path) {
  if (!path.startsWith('content://')) return path;
  try {
    final uri = Uri.parse(path);
    final last = uri.pathSegments.last;
    final decoded = Uri.decodeComponent(last);
    final colon = decoded.indexOf(':');
    return colon > 0 && colon < decoded.length - 1
        ? decoded.substring(colon + 1)
        : decoded;
  } catch (_) {
    return path;
  }
}

class _StatsDirectoryRow extends StatelessWidget {
  final String? path;
  final String? error;
  final ValueChanged<String?> onChange;

  const _StatsDirectoryRow({
    required this.path,
    this.error,
    required this.onChange,
  });

  Future<void> _pickDirectory(BuildContext context) async {
    String? selected;
    if (defaultTargetPlatform == TargetPlatform.android) {
      selected = await SafAccess.pickDirectory();
    } else {
      try {
        selected = await FilePicker.getDirectoryPath(
          dialogTitle: 'Select stats sync directory',
        );
      } catch (e) {
        if (context.mounted) {
          final controller = TextEditingController();
          selected = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Select stats sync directory'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: '/path/to/stats/directory',
                  ),
                  autofocus: true,
                  onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.pop(ctx, controller.text.trim()),
                  child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
                ),
              ],
            ),
          );
          if (selected != null && !await Directory(selected).exists()) {
            selected = null;
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Directory does not exist'),
                ),
              );
            }
          }
        }
      }
    }
    if (selected != null) {
      onChange(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (path != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                _contentUriToDisplayPath(path!),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      error!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (kIsWeb)
            Text(
              l10n.statsSyncDirectoryWebUnsupported,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            )
          else
            Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: Text(
                    path != null
                        ? l10n.statsSyncDirectoryChange
                        : l10n.statsSyncDirectoryChoose,
                  ),
                  onPressed: () => _pickDirectory(context),
                ),
                if (path != null) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.clear),
                    label: Text(l10n.statsSyncDirectoryClear),
                    onPressed: () => onChange(null),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _EnumSettingRow<T extends Enum> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> options;
  final Map<T, String> labels;
  final ValueChanged<T?> onChanged;

  const _EnumSettingRow({
    required this.label,
    required this.value,
    required this.options,
    required this.labels,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        DropdownButton<T>(
          value: value,
          onChanged: onChanged,
          items: options
              .map(
                (opt) =>
                    DropdownMenuItem<T>(value: opt, child: Text(labels[opt]!)),
              )
              .toList(),
        ),
      ],
    );
  }
}
