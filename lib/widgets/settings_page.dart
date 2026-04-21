import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/settings.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';

class SettingsPage extends StatefulWidget {
  final Settings settings;
  final ValueChanged<ChangeableSettings> onSettingsChange;

  const SettingsPage({
    super.key,
    required this.settings,
    required this.onSettingsChange,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final Map<ValidateType, String> settingsValidateType = {
      ValidateType.manual: AppLocalizations.of(
        context,
      )!.settingValidateTypeManual,
      ValidateType.intermediate: AppLocalizations.of(
        context,
      )!.settingValidateTypeDefault,
      ValidateType.automatic: AppLocalizations.of(
        context,
      )!.settingValidateTypeAutomatic,
    };

    final Map<ShowRating, String> settingsShowRating = {
      ShowRating.yes: AppLocalizations.of(context)!.settingShowRatingYes,
      ShowRating.no: AppLocalizations.of(context)!.settingShowRatingNo,
    };

    final Map<ShareData, String> settingsShareData = {
      ShareData.yes: AppLocalizations.of(context)!.settingShareDataYes,
      ShareData.no: AppLocalizations.of(context)!.settingShareDataNo,
    };

    final Map<LiveCheckType, String> settingsLiveCheckType = {
      LiveCheckType.all: AppLocalizations.of(context)!.settingsLiveCheckTypeAll,
      LiveCheckType.count: AppLocalizations.of(
        context,
      )!.settingsLiveCheckTypeCount,
      LiveCheckType.complete: AppLocalizations.of(
        context,
      )!.settingsLiveCheckTypeComplete,
    };

    final Map<HintType, String> settingsHintType = {
      HintType.deducibleCell: AppLocalizations.of(
        context,
      )!.settingHintTypeDeducibleCell,
      HintType.addConstraint: AppLocalizations.of(
        context,
      )!.settingHintTypeAddConstraint,
    };

    final Map<IdleTimeout, String> settingsIdleTimeout = {
      IdleTimeout.disabled: AppLocalizations.of(
        context,
      )!.settingIdleTimeoutDisabled,
      IdleTimeout.s5: AppLocalizations.of(context)!.settingIdleTimeoutS5,
      IdleTimeout.s10: AppLocalizations.of(context)!.settingIdleTimeoutS10,
      IdleTimeout.s30: AppLocalizations.of(context)!.settingIdleTimeoutS30,
      IdleTimeout.m1: AppLocalizations.of(context)!.settingIdleTimeoutM1,
      IdleTimeout.m2: AppLocalizations.of(context)!.settingIdleTimeoutM2,
    };

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.settings)),
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
                        Text(AppLocalizations.of(context)!.settingValidateType),
                        DropdownButton<ValidateType>(
                          value: widget.settings.validateType,
                          items: [
                            DropdownMenuItem(
                              value: ValidateType.manual,
                              child: Text(
                                settingsValidateType[ValidateType.manual]!,
                              ),
                            ),
                            DropdownMenuItem(
                              value: ValidateType.automatic,
                              child: Text(
                                settingsValidateType[ValidateType.automatic]!,
                              ),
                            ),
                          ],
                          onChanged: (newValue) {
                            setState(() {
                              widget.onSettingsChange(
                                ChangeableSettings(validateType: newValue),
                              );
                            });
                          },
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(AppLocalizations.of(context)!.settingShowRating),
                        DropdownButton<ShowRating>(
                          value: widget.settings.showRating,
                          onChanged: (newValue) {
                            setState(() {
                              widget.onSettingsChange(
                                ChangeableSettings(showRating: newValue),
                              );
                            });
                          },
                          items: ShowRating.values
                              .map(
                                (slug) => DropdownMenuItem(
                                  value: slug,
                                  child: Text(settingsShowRating[slug]!),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.settingsLiveCheckType,
                        ),
                        DropdownButton<LiveCheckType>(
                          value: widget.settings.liveCheckType,
                          onChanged: (newValue) {
                            setState(() {
                              widget.onSettingsChange(
                                ChangeableSettings(liveCheckType: newValue),
                              );
                            });
                          },
                          items: LiveCheckType.values
                              .map(
                                (slug) => DropdownMenuItem(
                                  value: slug,
                                  child: Text(settingsLiveCheckType[slug]!),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(AppLocalizations.of(context)!.settingHintType),
                        DropdownButton<HintType>(
                          value: widget.settings.hintType,
                          onChanged: (newValue) {
                            setState(() {
                              widget.onSettingsChange(
                                ChangeableSettings(hintType: newValue),
                              );
                            });
                          },
                          items: HintType.values
                              .map(
                                (slug) => DropdownMenuItem(
                                  value: slug,
                                  child: Text(settingsHintType[slug]!),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(AppLocalizations.of(context)!.settingIdleTimeout),
                        DropdownButton<IdleTimeout>(
                          value: widget.settings.idleTimeout,
                          onChanged: (newValue) {
                            setState(() {
                              widget.onSettingsChange(
                                ChangeableSettings(idleTimeout: newValue),
                              );
                            });
                          },
                          items: IdleTimeout.values
                              .map(
                                (slug) => DropdownMenuItem(
                                  value: slug,
                                  child: Text(settingsIdleTimeout[slug]!),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(AppLocalizations.of(context)!.settingShareData),
                        DropdownButton<ShareData>(
                          value: widget.settings.shareData,
                          onChanged: (newValue) {
                            setState(() {
                              widget.onSettingsChange(
                                ChangeableSettings(shareData: newValue),
                              );
                            });
                          },
                          items: ShareData.values
                              .map(
                                (slug) => DropdownMenuItem(
                                  value: slug,
                                  child: Text(settingsShareData[slug]!),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      AppLocalizations.of(context)!.settingDifficultyLevel,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              AppLocalizations.of(context)!.settingPlayerLevel,
                            ),
                            if (widget.settings.autoLevel) ...[
                              const SizedBox(width: 8),
                              Text(
                                "(${AppLocalizations.of(context)!.settingPlayerLevelAuto})",
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
                        Text(AppLocalizations.of(context)!.settingAutoLevel),
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
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
