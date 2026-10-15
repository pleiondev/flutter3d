/// The sample plugin's editor half, installed into an editor's registries
/// and into a game's that have none, and its data half read with the
/// editor's section.
///
///     dart test test/acme_editor_test.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_plugin_runtime/flutter3d_plugin_runtime.dart';
import 'package:flutter3d_plugin_runtime_example/acme_editor.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show EngineLoop, InputState;
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Editing _harbour() => Editing.parse(
  jsonEncode(<String, Object?>{
    'version': 1,
    'name': 'forge',
    'entities': <Object?>[
      <String, Object?>{
        'type': 'ember',
        'at': <double>[0.0, 0.0, 0.0],
        'heat': 900.0,
      },
    ],
  }),
  path: '/forge/assets/levels/forge.json',
);

void main() {
  test('in an editor, every piece is published under the namespace', () {
    final pieces = EditorPieces();
    EngineLoop(
      input: InputState(),
      registries: <PluginRegistry>[pieces],
      plugins: <Flutter3dPlugin>[AcmeEditorPlugin()],
    );

    expect(pieces.hints.components.single.id, 'acme_sample.heat');
    expect(pieces.paletteEntries.single.properties, <String, Object?>{
      'heat': 900.0,
      'reach': 2.0,
    });
    expect(
      inspectorComponents(
        Piece.entity,
        type: 'ember',
        pieces: pieces,
      ).map((c) => c.kind),
      containsAll(<String>['type:ember', 'acme_sample.heat']),
    );
    expect(pieces.materialHint('acme_sample__Hair', 'gloss'), isNotNull);
    // A command, a gizmo and an entry are under the package's namespace, as
    // its MCP tools, its hints and the runtime half's names are: the editor
    // half publishes no namespace of its own.
    expect(pieces.argumentsOf('acme_sample.stoke').single.key, 'by');

    final editing = _harbour();
    final stoke = pieces.readCommand(<String, Object?>{
      'command': 'acme_sample.stoke',
    })!;
    expect(stoke.toJson()['command'], 'acme_sample.stoke');
    expect(editing.history.run(stoke), isTrue);
    expect(editing.level.entities.single.number('heat'), 1000.0);

    final ring = pieces.marksFor(editing.level).single;
    expect(ring.gizmo, 'acme_sample.reach');
    final pulled = pieces.dragged(
      ring,
      editing.level,
      from: Vector3(2.0, 0.0, 0.0),
      to: Vector3(3.0, 0.0, 0.0),
    )!;
    editing
      ..kind = Piece.entity
      ..selected = 0;
    expect(editing.history.run(pulled), isTrue);
    expect(editing.level.entities.single.number('reach'), 3.0);

    expect(pieces.assetEntryFor('more.embers')?.name, 'acme_sample.embers');
  });

  test('an ember list is imported as embers, and a bad line is said', () async {
    final pieces = EditorPieces();
    EngineLoop(
      input: InputState(),
      registries: <PluginRegistry>[pieces],
      plugins: <Flutter3dPlugin>[AcmeEditorPlugin()],
    );
    final editing = _harbour();
    final importer = pieces.importerFor('/downloads/more.embers')!.importer;
    final result = await importer.import(
      ImportRequest(
        path: '/downloads/more.embers',
        bytes: Uint8List.fromList(utf8.encode('1 0 2 800\nhot\n3 0 4 1200\n')),
        level: editing.level,
      ),
    );
    expect(result.files.keys.single, 'assets/embers/more.embers');
    expect(result.notes, <String>[
      '2 embers',
      'line 2 is not "x y z heat": left out',
    ]);
    for (final command in result.commands) {
      expect(editing.history.run(command), isTrue);
    }
    expect(editing.level.entities.last.number('heat'), 1200.0);
  });

  test('in a game, with no editor, it installs and adds nothing', () {
    final loop = EngineLoop(
      input: InputState(),
      plugins: <Flutter3dPlugin>[AcmeEditorPlugin()],
    );
    expect(loop.plugins.isEnabled('acme_sample.editor'), isTrue);
    // It touches only tooling: a run made with it carries nothing of it.
    expect(AcmeEditorPlugin().manifest.touches, PluginTouches.tooling);
    expect(
      loop.simulationVersion.plugins,
      isNot(contains('acme_sample.editor')),
    );
  });

  test(
    'the data half is the same hints, read by the editor\'s section',
    () async {
      final document = File('plugin/acme_editor.f3dplugin').readAsStringSync();
      final plugin = await DataPluginLoader(
        sections: DataSections(<DataSection>[editorSection]),
      ).load(document, MemoryPluginSource(const <String, Uint8List>{}));
      final pieces = EditorPieces();
      EngineLoop(
        input: InputState(),
        registries: <PluginRegistry>[pieces],
        plugins: <Flutter3dPlugin>[plugin],
      );
      expect(pieces.hints.components.single.toJson(), heatHints.toJson());
      expect(
        jsonEncode(pieces.hints.entityKinds.single.toJson()),
        jsonEncode(emberHints.toJson()),
      );
      expect(pieces.hints.materials.single.toJson(), hairHints.toJson());
    },
  );
}
