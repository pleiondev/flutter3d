/// The editor installs the project's plugins and shows what they brought:
/// an inspector section from a data plugin's hints, a docked panel, the
/// asset browser's groups and its place button.
///
///     flutter test test/plugin_contract_test.dart
///
/// Each test was written by breaking what it covers; the mutation is named.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter3d_editor/src/editor_cubit.dart';
import 'package:flutter3d_editor/src/editor_inspector.dart';
import 'package:flutter3d_editor/src/editor_panels.dart';
import 'package:flutter3d_editor/src/editor_plugins.dart';
import 'package:flutter3d_editor/src/editor_theme.dart';
import 'package:flutter3d_editor/src/plugin_panels.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter3d_plugin_api/editor.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_cubit_helpers.dart';

/// A project on no disk: its files by path.
final Map<String, Uint8List> _project = <String, Uint8List>{
  '/game/assets/plugins/boats.f3dplugin': Uint8List.fromList(
    utf8.encode(
      jsonEncode(<String, Object?>{
        'format': 'f3d.plugin',
        'version': 3,
        'manifest': <String, Object?>{
          'id': 'boats',
          'apiVersion': '1.0',
          'touches': 'view',
        },
        'editor': <String, Object?>{
          'components': <Object?>[
            const ComponentHints(
              id: 'boats.buoyancy',
              title: 'Buoyancy',
              fields: <FieldHint>[
                FieldHint.number('buoyancy', min: 0, max: 4, defaultValue: 1.0),
              ],
              entityTypes: <String>{'boat'},
            ).toJson(),
          ],
          'entityKinds': <Object?>[
            const EntityKindHints(type: 'boat', label: 'Boat').toJson(),
          ],
        },
      }),
    ),
  ),
  '/game/assets/plugins/broken.f3dplugin': Uint8List.fromList(
    utf8.encode('{"format": "f3d.plugin"'),
  ),
  '/game/assets/levels/harbour.json': Uint8List(0),
};

List<String> _filesUnder(String directory) => <String>[
  for (final path in _project.keys)
    if (path.startsWith('$directory/')) path.substring(directory.length + 1),
]..sort();

Future<Uint8List> _read(String path) async =>
    _project[path] ?? (throw StateError('no $path'));

/// A plugin that docks a panel and lists `.hull` files it can place.
final class _Docks extends Flutter3dPlugin {
  @override
  PluginManifest get manifest => PluginManifest(
    id: 'docks',
    apiVersion: const PluginApiVersion(1, 0),
    touches: PluginTouches.view,
  );

  @override
  void install(PluginHost host) {
    host.registry<EditorPanels>().addPanel(
      EditorPanel(
        id: 'tide',
        title: 'Tide',
        dock: DockSide.right,
        builder: (EditorPanelContext panel) =>
            Text('tide for ${panel.selection.length}'),
      ),
    );
    host.registry<EditorPieces>().addAssetEntry(
      'hulls',
      AssetBrowserEntry(
        label: 'Hull',
        suffixes: const <String>['.hull'],
        place: (AssetPlacement placement) => Place(
          Piece.entity,
          'boat',
          placement.at,
          properties: <String, Object?>{'hull': placement.path},
        ),
      ),
    );
  }
}

void main() {
  test(
    'the project\'s data plugins are installed beside the compiled ones',
    () async {
      final plugins = await EditorPlugins.forProject(
        '/game',
        listFiles: _filesUnder,
        readBytes: _read,
        plugins: <Flutter3dPlugin>[_Docks()],
      );
      // Mutation: install the compiled plugins only.
      expect(
        plugins.statuses.map((s) => s.manifest.id),
        containsAll(<String>['docks', 'boats']),
      );
      expect(plugins.pieces.hints.components.single.id, 'boats.buoyancy');
      expect(plugins.pieces.paletteEntries.single.type, 'boat');
      // The one that does not read is left out alone, and said.
      expect(
        plugins.notes.where((n) => n.contains('broken.f3dplugin left out')),
        hasLength(1),
      );
      expect(plugins.refusal, isNull);
    },
  );

  testWidgets('a hinted field is a slider and a docked panel is a tab', (
    WidgetTester tester,
  ) async {
    final plugins = await EditorPlugins.forProject(
      '/game',
      listFiles: _filesUnder,
      readBytes: _read,
      plugins: <Flutter3dPlugin>[_Docks()],
    );
    final editing = Editing.parse(
      jsonEncode(<String, Object?>{
        'version': 1,
        'name': 'harbour',
        'entities': <Object?>[
          <String, Object?>{
            'type': 'boat',
            'at': <double>[0.0, 0.0, 0.0],
            'buoyancy': 2.0,
          },
        ],
      }),
      path: '/game/assets/levels/harbour.json',
    )..select(Piece.entity, 0);
    final state = EditorReady(
      editing: editing,
      assetRoot: '/game',
      looks: noLooks,
      said: '',
    );
    final panels = editorPanels(
      state: state,
      log: EditorLog(),
      game: null,
      frame: null,
      onSelect: (Picked _, {required bool add}) {},
      onFlyTo: (Picked _) {},
      onChanged: (String _) {},
      onLive: (String _, Map<String, Object?> _) {},
      pieces: plugins.pieces,
      plugins: plugins.panels,
      panelContext: (BuildContext context) => EditorPanelContext(
        context: context,
        document: const <String, Object?>{},
        selection: const <PanelSelection>[
          PanelSelection(piece: 'entity', index: 0),
        ],
        run: (Map<String, Object?> command) => false,
      ),
    );
    // Mutation: leave the plugins' docked panels out of `editorPanels`.
    expect(panels.map((p) => p.id), contains('docks.tide'));

    await tester.pumpWidget(
      MaterialApp(
        theme: editorTheme(),
        home: Scaffold(
          body: EditorInspector(
            state: state,
            onChanged: (String _) {},
            pieces: plugins.pieces,
          ),
        ),
      ),
    );
    // The data plugin's section, and its range as a slider.
    expect(find.byKey(const ValueKey<String>('component:Buoyancy')), findsOne);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('field:buoyancy')),
        matching: find.byType(Slider),
      ),
      findsOneWidget,
    );
  });

  test('the asset browser groups files by entry, a plugin\'s first', () {
    final pieces = EditorPlugins(plugins: <Flutter3dPlugin>[_Docks()]).pieces;
    final groups = AssetBrowser.grouped(<String>[
      'hulls/skiff.hull',
      'levels/harbour.json',
      'notes.txt',
    ], pieces);
    // Mutation: group by suffix and lose the entry's name.
    expect(groups.map((g) => g.$1.name), <String>['docks.hulls', 'level']);
    expect(groups.map((g) => g.$2), <List<String>>[
      <String>['hulls/skiff.hull'],
      <String>['levels/harbour.json'],
    ]);
  });
}
