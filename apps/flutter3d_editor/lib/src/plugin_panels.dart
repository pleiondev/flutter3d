/// The two places the plugins' contract shows up in the editor's window
/// beyond the inspector and the palette: the asset browser, which lists the
/// project's files by the kinds the editor and the plugins know, and the tabs
/// that put a plugin's main-screen panel in the picture's place.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart'
    show EditorPanel;

/// The project's files under `assets/`, grouped by the asset-browser entry
/// each matches: the plugins' entries first, then the editor's own.
///
/// **A file a plugin knows how to place has a button that places it**, six
/// metres ahead of the camera, through the command the plugin's entry
/// answers. A file no entry matches is not listed: the browser shows what
/// the editor and its plugins can say something about.
final class AssetBrowser extends StatelessWidget {
  const AssetBrowser({
    super.key,
    required this.root,
    required this.files,
    required this.pieces,
    required this.onPlace,
  });

  /// The project's root, or null when the level belongs to none.
  final String? root;

  /// The files under the project's `assets/`, relative to it.
  final List<String> files;

  final EditorPieces pieces;

  /// Places the file at a path relative to `assets/`.
  final void Function(String path) onPlace;

  /// [files] by the published name of the entry each matches, in the order
  /// [EditorPieces.assetEntries] gives the entries.
  static List<(AddedAssetEntry, List<String>)> grouped(
    List<String> files,
    EditorPieces pieces,
  ) {
    final byEntry = <String, List<String>>{};
    for (final file in files) {
      final entry = pieces.assetEntryFor(file);
      if (entry == null) continue;
      (byEntry[entry.name] ??= <String>[]).add(file);
    }
    return <(AddedAssetEntry, List<String>)>[
      for (final entry in pieces.assetEntries)
        if (byEntry[entry.name] case final List<String> found) (entry, found),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (root == null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'This level belongs to no project with an assets directory',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    final groups = grouped(files, pieces);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: <Widget>[
        for (final (added, found) in groups) ...<Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
            child: Text(
              '${added.entry.label.toUpperCase()} · ${found.length}',
              key: ValueKey<String>('assets.group:${added.name}'),
              style: const TextStyle(
                color: Color(0xFF525A66),
                fontSize: 10,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (final path in found)
            ListTile(
              key: ValueKey<String>('assets.file:$path'),
              dense: true,
              title: Text(path, style: const TextStyle(fontSize: 12)),
              trailing: added.entry.place == null
                  ? null
                  : IconButton(
                      key: ValueKey<String>('assets.place:$path'),
                      tooltip: 'Place it in front of the camera',
                      iconSize: 16,
                      icon: const Icon(Icons.add_location_alt_outlined),
                      onPressed: () => onPlace(path),
                    ),
            ),
        ],
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Nothing under assets/ that the editor or a plugin lists',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

/// A row of tabs over the picture: the level, and each plugin's
/// main-screen panel.
final class MainScreenTabs extends StatelessWidget {
  const MainScreenTabs({
    super.key,
    required this.panels,
    required this.chosen,
    required this.onChoose,
  });

  final List<EditorPanel> panels;

  /// The panel shown, by id, or null for the level.
  final String? chosen;

  /// Called with a panel's id, or null for the level.
  final ValueChanged<String?> onChoose;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 30,
    child: Row(
      children: <Widget>[
        _tab('Level', Icons.view_in_ar, null),
        for (final panel in panels) _tab(panel.title, panel.icon, panel.id),
      ],
    ),
  );

  Widget _tab(String title, IconData icon, String? id) => TextButton.icon(
    key: ValueKey<String>('main.tab:${id ?? 'level'}'),
    onPressed: () => onChoose(id),
    icon: Icon(icon, size: 14),
    label: Text(
      title,
      style: TextStyle(
        fontSize: 12,
        fontWeight: id == chosen ? FontWeight.w700 : FontWeight.w400,
      ),
    ),
  );
}
