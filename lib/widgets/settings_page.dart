import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/settings.dart';
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

  const SettingsPage({
    super.key,
    required this.settings,
    required this.onSettingsChange,
    required this.onClearStats,
    required this.onReplayOnboarding,
    required this.onChangeLanguage,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: LayoutBuilder(
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l10n.settingHintsEnabled),
                        Switch(
                          value: widget.settings.hintsEnabled,
                          onChanged: (newValue) {
                            setState(() {
                              widget.onSettingsChange(
                                ChangeableSettings(hintsEnabled: newValue),
                              );
                            });
                          },
                        ),
                      ],
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
                            value: widget.settings.playerLevel.toDouble(),
                            min: 0,
                            max: 100,
                            divisions: 100,
                            label: widget.settings.playerLevel.toString(),
                            onChanged: widget.settings.autoLevel
                                ? null
                                : (newValue) {
                                    setState(() {
                                      widget.onSettingsChange(
                                        ChangeableSettings(
                                          playerLevel: newValue.toInt(),
                                        ),
                                      );
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
                  ],
                ),
              ),
            ),
          );
        },
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
