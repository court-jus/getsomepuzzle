import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/settings.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';

class SettingsPage extends StatefulWidget {
  final Settings settings;
  final ValueChanged<ChangeableSettings> onSettingsChange;

  /// Callback that wipes the player's stats on tutorial puzzles. Awaited so
  /// the snackbar only fires after the async work is done.
  final Future<void> Function() onRestartTutorial;

  const SettingsPage({
    super.key,
    required this.settings,
    required this.onSettingsChange,
    required this.onRestartTutorial,
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
                    _EnumSettingRow<ShareData>(
                      label: l10n.settingShareData,
                      value: widget.settings.shareData,
                      options: ShareData.values,
                      labels: {
                        ShareData.yes: l10n.settingShareDataYes,
                        ShareData.no: l10n.settingShareDataNo,
                      },
                      onChanged: (v) => setState(() {
                        widget.onSettingsChange(
                          ChangeableSettings(shareData: v),
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
                    Text(
                      l10n.settingTutorialSection,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: Text(l10n.settingRestartTutorial),
                        onPressed: _confirmRestartTutorial,
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

  Future<void> _confirmRestartTutorial() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.settingRestartTutorialConfirmTitle),
        content: Text(l10n.settingRestartTutorialConfirmBody),
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
    await widget.onRestartTutorial();
    if (!mounted) return;
    // Pop back to the game screen so the player lands directly on the first
    // tutorial puzzle that the callback just queued up.
    Navigator.of(context).pop();
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
