import 'dart:developer';
import 'dart:io' as java_io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/plusminus.dart';
import 'package:getsomepuzzle/widgets/flags_selector.dart';

class OpenPage extends StatefulWidget {
  final Database database;
  final ValueChanged<PuzzleData> onPuzzleSelected;

  const OpenPage({
    super.key,
    required this.database,
    required this.onPuzzleSelected,
  });

  @override
  State<OpenPage> createState() => _OpenPageState();
}

class _OpenPageState extends State<OpenPage> {
  int matchingCount = 0;
  String collection = "tutorial";
  bool showAdvanced = false;
  Map<String, bool?> rules = {};

  static List<String> get existingRules =>
      constraintRegistry.map((r) => r.slug).toList();

  @override
  void initState() {
    super.initState();
    collection = widget.database.collection;
    updateMatchingCount();
  }

  void applyFilter({
    RangeValues? newWidth,
    RangeValues? newHeight,
    RangeValues? newPrefilled,
    List<String>? newWRules,
    List<String>? newBRules,
    List<String>? newWFlags,
    List<String>? newBFlags,
  }) {
    setState(() {
      bool changed = false;
      if (newWidth != null) {
        widget.database.currentFilters.minWidth = newWidth.start.toInt();
        widget.database.currentFilters.maxWidth = newWidth.end.toInt();
        changed = true;
      }
      if (newHeight != null) {
        widget.database.currentFilters.minHeight = newHeight.start.toInt();
        widget.database.currentFilters.maxHeight = newHeight.end.toInt();
        changed = true;
      }
      if (newPrefilled != null) {
        widget.database.currentFilters.minFilled = newPrefilled.start.toInt();
        widget.database.currentFilters.maxFilled = newPrefilled.end.toInt();
        changed = true;
      }
      if (newWRules != null) {
        log("New WRules $newWRules");
        widget.database.currentFilters.wantedRules = newWRules.toSet();
        widget.database.currentFilters.bannedRules.removeAll(
          widget.database.currentFilters.wantedRules,
        );
        changed = true;
      }
      if (newBRules != null) {
        widget.database.currentFilters.bannedRules = newBRules.toSet();
        widget.database.currentFilters.wantedRules.removeAll(
          widget.database.currentFilters.bannedRules,
        );
        changed = true;
      }
      if (newWFlags != null) {
        widget.database.currentFilters.wantedFlags = newWFlags.toSet();
        widget.database.currentFilters.bannedFlags = widget
            .database
            .currentFilters
            .bannedFlags
            .where((flag) => !newWFlags.contains(flag))
            .toSet();
        changed = true;
      }
      if (newBFlags != null) {
        widget.database.currentFilters.bannedFlags = newBFlags.toSet();
        widget.database.currentFilters.wantedFlags = widget
            .database
            .currentFilters
            .wantedFlags
            .where((flag) => !newBFlags.contains(flag))
            .toSet();
        changed = true;
      }
      if (changed) {
        widget.database.currentFilters.save();
        widget.database.preparePlaylist();
        updateMatchingCount();
      }
    });
  }

  void chooseCollection(String newCollection) {
    setState(() {
      collection = newCollection;
    });
    widget.database
        .loadPuzzlesFile(collection)
        .then((void _) => setState(updateMatchingCount));
  }

  void setShuffle(bool newValue) {
    setState(() {
      widget.database.setShouldShuffle(newValue);
    });
    updateMatchingCount();
  }

  void updateMatchingCount() {
    widget.database.preparePlaylist();
    matchingCount = widget.database.playlist.length;
  }

  void selectPuzzle(
    PuzzleData puz,
    BuildContext context, [
    bool popFromDatabase = true,
  ]) {
    if (popFromDatabase) {
      widget.database.removePuzzleFromPlaylist(puz);
    }
    widget.onPuzzleSelected(puz);
    Navigator.pop(context);
  }

  void _showCreatePlaylistDialog() {
    final loc = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.createPlaylist),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: loc.playlistName),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              await widget.database.createUserPlaylist(name);
              final key = 'user_${Database.slugify(name)}';
              chooseCollection(key);
            },
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );
  }

  void _deleteCurrentPlaylist() {
    final loc = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.deletePlaylist),
        content: Text(loc.confirmDeletePlaylist),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // Find the display name from the slug
              final slug = collection.replaceFirst('user_', '');
              final name = widget.database.userPlaylistNames.firstWhere(
                (n) => Database.slugify(n) == slug,
                orElse: () => slug,
              );
              await widget.database.deleteUserPlaylist(name);
              chooseCollection('tutorial');
            },
            child: Text(
              MaterialLocalizations.of(ctx).deleteButtonTooltip,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _importPlaylistFromFile() async {
    final loc = AppLocalizations.of(context)!;
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;
    final content = await java_io.File(file.path!).readAsString();
    final lines = content
        .split('\n')
        .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
        .toList();
    if (lines.isEmpty) return;
    if (!mounted) return;

    // Ask for playlist name
    final controller = TextEditingController(
      text: file.name.replaceAll('.txt', ''),
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.importPlaylist),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: loc.playlistName),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    await widget.database.createUserPlaylist(name);
    final key = 'user_${Database.slugify(name)}';
    await widget.database.importToPlaylist(key, content);
    if (!mounted) return;
    chooseCollection(key);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.titleOpenPuzzlePage),
      ),
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
                    Text(AppLocalizations.of(context)!.infoFilterCollection),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.labelSelectCollection,
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DropdownButton<String>(
                              value: collection,
                              items: [
                                for (final item
                                    in widget.database.getCollections(
                                      AppLocalizations.of(
                                        context,
                                      )!.collectionMyPuzzles,
                                    ))
                                  DropdownMenuItem(
                                    value: item.$1,
                                    child: item.$2,
                                  ),
                              ],
                              onChanged: (newValue) =>
                                  chooseCollection(newValue ?? "tutorial"),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add),
                              tooltip: AppLocalizations.of(
                                context,
                              )!.createPlaylist,
                              onPressed: _showCreatePlaylistDialog,
                            ),
                            IconButton(
                              icon: const Icon(Icons.file_open),
                              tooltip: AppLocalizations.of(
                                context,
                              )!.importPlaylist,
                              onPressed: _importPlaylistFromFile,
                            ),
                            if (collection.startsWith('user_'))
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                tooltip: AppLocalizations.of(
                                  context,
                                )!.deletePlaylist,
                                onPressed: _deleteCurrentPlaylist,
                              ),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(AppLocalizations.of(context)!.labelToggleShuffle),
                        Switch(
                          value: widget.database.shouldShuffle,
                          onChanged: setShuffle,
                        ),
                      ],
                    ),
                    const Divider(),
                    Text(
                      "${AppLocalizations.of(context)!.msgCountMatchingPuzzles}: $matchingCount",
                    ),
                    const Divider(),
                    if (widget.database.collection == "custom" &&
                        widget.database.puzzles.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          AppLocalizations.of(context)!.noCustomPuzzles,
                          style: TextStyle(
                            fontSize: 16,
                            fontStyle: FontStyle.italic,
                            color: Colors.grey,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),

                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyan,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadiusGeometry.circular(16),
                        ),
                      ),
                      onPressed: widget.database.playlist.isNotEmpty
                          ? () => selectPuzzle(
                              widget.database.playlist.first,
                              context,
                            )
                          : null,
                      child: SizedBox(
                        height: 96,
                        child: Container(
                          alignment: AlignmentGeometry.center,
                          child: FaIcon(FontAwesomeIcons.play, size: 80),
                        ),
                      ),
                    ),
                    ExpansionPanelList(
                      expansionCallback: (panelIndex, isExpanded) {
                        setState(() {
                          showAdvanced = isExpanded;
                        });
                      },
                      children: [
                        ExpansionPanel(
                          isExpanded: showAdvanced,
                          body: SingleChildScrollView(
                            child: Column(
                              children: [
                                const Divider(),
                                Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.labelWidgetDimensions,
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      )!.labelWidgetWidth,
                                    ),
                                    PlusMinusField(
                                      onChanged: (minValue, maxValue) {
                                        final value = RangeValues(
                                          minValue.toDouble(),
                                          maxValue.toDouble(),
                                        );
                                        applyFilter(newWidth: value);
                                      },
                                      initialMin: widget
                                          .database
                                          .currentFilters
                                          .minWidth,
                                      initialMax: widget
                                          .database
                                          .currentFilters
                                          .maxWidth,
                                      showReset: true,
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      )!.labelWidgetHeight,
                                    ),
                                    PlusMinusField(
                                      onChanged: (minValue, maxValue) {
                                        final value = RangeValues(
                                          minValue.toDouble(),
                                          maxValue.toDouble(),
                                        );
                                        applyFilter(newHeight: value);
                                      },
                                      initialMin: widget
                                          .database
                                          .currentFilters
                                          .minHeight,
                                      initialMax: widget
                                          .database
                                          .currentFilters
                                          .maxHeight,
                                      showReset: true,
                                    ),
                                  ],
                                ),
                                const Divider(),
                                Text(
                                  AppLocalizations.of(context)!.labelChooseOnly,
                                ),
                                FlagsSelector(
                                  choices: [
                                    ("played", "PL"),
                                    ("skipped", "SK"),
                                    ("liked", "LI"),
                                    ("disliked", "DI"),
                                  ],
                                  wanted: widget
                                      .database
                                      .currentFilters
                                      .wantedFlags,
                                  banned: widget
                                      .database
                                      .currentFilters
                                      .bannedFlags,
                                  apply: (value) => {
                                    applyFilter(
                                      newWFlags: value.$1.toList(),
                                      newBFlags: value.$2.toList(),
                                    ),
                                  },
                                ),
                                const Divider(),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      )!.labelWidgetFillRatio,
                                    ),
                                    PlusMinusField(
                                      onChanged: (minValue, maxValue) {
                                        final value = RangeValues(
                                          minValue.toDouble(),
                                          maxValue.toDouble(),
                                        );
                                        applyFilter(newPrefilled: value);
                                      },
                                      initialMin: widget
                                          .database
                                          .currentFilters
                                          .minFilled,
                                      initialMax: widget
                                          .database
                                          .currentFilters
                                          .maxFilled,
                                      minimum: 0,
                                      maximum: 100,
                                      increment: 5,
                                      showReset: true,
                                    ),
                                  ],
                                ),
                                const Divider(),
                                Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.labelWidgetWantedrules,
                                ),
                                FlagsSelector(
                                  choices: existingRules
                                      .map((e) => (e, e))
                                      .toList(),
                                  wanted: widget
                                      .database
                                      .currentFilters
                                      .wantedRules,
                                  banned: widget
                                      .database
                                      .currentFilters
                                      .bannedRules,
                                  apply: (value) => {
                                    applyFilter(
                                      newWRules: value.$1.toList(),
                                      newBRules: value.$2.toList(),
                                    ),
                                  },
                                ),
                                const Divider(),
                                TextField(
                                  onChanged: (value) => selectPuzzle(
                                    PuzzleData(value),
                                    context,
                                    false,
                                  ),
                                  decoration: InputDecoration(
                                    label: Text(
                                      AppLocalizations.of(
                                        context,
                                      )!.placeholderWidgetPastePuzzle,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          headerBuilder: (context, isExpanded) {
                            return ListTile(
                              title: Text(
                                AppLocalizations.of(
                                  context,
                                )!.labelAdvancedFilters,
                              ),
                            );
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
