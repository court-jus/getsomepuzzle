import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/settings.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';

class SettingsPage extends StatefulWidget {
  final Settings settings;
  final dynamic Function(ChangeableSettings settings) onSettingsChange;

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
      ValidateType.manual: AppLocalizations.of(context)!.settingValidateTypeManual,
      ValidateType.intermediate: AppLocalizations.of(context)!.settingValidateTypeDefault,
      ValidateType.automatic: AppLocalizations.of(context)!.settingValidateTypeAutomatic,
    };

    final Map<LiveCheckType, String> settingsLiveCheckType = {
      LiveCheckType.all: AppLocalizations.of(context)!.settingsLiveCheckTypeAll,
      LiveCheckType.count: AppLocalizations.of(context)!.settingsLiveCheckTypeCount,
      LiveCheckType.complete: AppLocalizations.of(context)!.settingsLiveCheckTypeComplete,
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
                margin: EdgeInsets.all(8),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(AppLocalizations.of(context)!.settingValidateType),
                        SegmentedButton(
                          multiSelectionEnabled: false,
                          emptySelectionAllowed: false,
                          showSelectedIcon: false,
                          selected: {widget.settings.validateType},
                          onSelectionChanged: (newValue) {
                            setState(() {
                              widget.settings.change(ChangeableSettings(validateType: newValue.first));
                            });
                          },
                          segments: ValidateType.values
                              .map(
                                (slug) => ButtonSegment(
                                  value: slug,
                                  label: Text(settingsValidateType[slug]!),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(AppLocalizations.of(context)!.settingsLiveCheckType),
                        SegmentedButton(
                          multiSelectionEnabled: false,
                          emptySelectionAllowed: false,
                          showSelectedIcon: false,
                          selected: {widget.settings.liveCheckType},
                          onSelectionChanged: (newValue) {
                            setState(() {
                              widget.settings.change(ChangeableSettings(liveCheckType: newValue.first));
                            });
                          },
                          segments: LiveCheckType.values
                              .map(
                                (slug) => ButtonSegment(
                                  value: slug,
                                  label: Text(settingsLiveCheckType[slug]!),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
          );
        }
      ),
    );
  }
}
