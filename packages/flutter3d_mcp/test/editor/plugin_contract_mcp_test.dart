/// The editor's plugin contract seen by an agent: a plugin's command is a
/// tool of its own with its argument hints as its schema, `plugin.list` says
/// what the plugins brought, and `asset.import` runs a plugin's importer
/// inside the project.
///
///     dart test test/editor/plugin_contract_mcp_test.dart
///
/// Each test was written by breaking what it covers; the mutation is named.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_mcp/editor.dart';
import 'package:flutter3d_mcp/kit.dart';
import 'package:flutter3d_plugin_api/editor.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

final class _Scope extends PluginScope {
  _Scope(String id)
    : manifest = PluginManifest(
        id: id,
        apiVersion: const PluginApiVersion(1, 0),
      );

  @override
  final PluginManifest manifest;

  @override
  int get rank => 0;

  final List<Registration> registrations = <Registration>[];

  @override
  void track(Registration registration) => registrations.add(registration);
}

/// Raises every entity of a type by a number of metres.
final class _Raise extends PluginCommand {
  const _Raise(this.type, this.by);

  static _Raise? read(Map<String, Object?> arguments) =>
      switch ((arguments['type'], arguments['by'] ?? 1.0)) {
        (final String type, final num by) => _Raise(type, by.toDouble()),
        _ => null,
      };

  final String type;
  final double by;

  @override
  String get name => 'boats.raise';

  @override
  String get says => 'raise every $type by $by';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'type': type,
    'by': by,
  };

  @override
  bool apply(Editing editing) {
    final level = editing.level;
    var moved = false;
    for (var i = 0; i < level.entities.length; i++) {
      if (level.entities[i].type != type) continue;
      editing
        ..kind = Piece.entity
        ..selected = i
        ..nudge(Vector3(0.0, by, 0.0));
      moved = true;
    }
    return moved;
  }
}

final class _HullImporter extends EditorImporter {
  const _HullImporter();

  @override
  String get label => 'Hull';

  @override
  List<String> get suffixes => const <String>['.hull'];

  @override
  Future<ImportResult> import(ImportRequest request) async => ImportResult(
    files: <String, Uint8List>{'assets/hulls/${request.name}': request.bytes},
    commands: <DocumentCommand>[
      Place(
        Piece.entity,
        'boat',
        request.at ?? Vector3.zero(),
        properties: <String, Object?>{'hull': 'hulls/${request.name}'},
      ),
    ],
  );
}

final class _Escaping extends EditorImporter {
  const _Escaping();

  @override
  String get label => 'Escaping';

  @override
  List<String> get suffixes => const <String>['.bad'];

  @override
  Future<ImportResult> import(ImportRequest request) async => ImportResult(
    files: <String, Uint8List>{'../../outside.txt': request.bytes},
  );
}

void main() {
  late Directory sandbox;
  late Directory project;
  late EditorSession session;
  late EditorPieces pieces;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('editor_plugin_contract');
    project = Directory('${sandbox.path}/game')..createSync();
    File('${project.path}/pubspec.yaml').writeAsStringSync('name: game\n');
    Directory('${project.path}/assets/levels').createSync(recursive: true);
    final level = '${project.path}/assets/levels/harbour.json';
    File(level).writeAsStringSync(
      jsonEncode(<String, Object?>{
        'version': 1,
        'name': 'harbour',
        'brushes': <Object?>[],
        'lights': <Object?>[],
        'entities': <Object?>[
          <String, Object?>{
            'type': 'boat',
            'at': <double>[0.0, 0.0, 0.0],
          },
        ],
      }),
    );
    pieces = EditorPieces();
    pieces.forPlugin(_Scope('boats'))
      ..addCommand(
        'raise',
        _Raise.read,
        description: 'Raise every entity of a type.',
        arguments: const <FieldHint>[
          FieldHint.text('type'),
          FieldHint.number('by', defaultValue: 1.0),
        ],
      )
      ..addImporter('hull', const _HullImporter())
      ..addImporter('bad', const _Escaping())
      ..hints.addComponent(
        const ComponentHints(
          id: 'boats.buoyancy',
          title: 'Buoyancy',
          fields: <FieldHint>[FieldHint.number('buoyancy')],
          entityTypes: <String>{'boat'},
        ),
      );
    session = EditorSession(
      Editing.parse(File(level).readAsStringSync(), path: level),
      pieces: pieces,
    );
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  Future<Answer> call(String name, Map<String, Object?> arguments) =>
      Future<Answer>.value(
        editorTools
            .firstWhere((EditorTool it) => it.name == name)
            .runOn(session, arguments),
      );

  test('a plugin command is a tool, its arguments its schema', () async {
    final tools = McpTools();
    final sharing = shareCommands(pieces, tools, session);
    // Mutation: publish the tool under the command's bare name.
    final tool = tools.named('boats.raise')!;
    final schema = tool.spec.inputSchema;
    expect((schema['properties']! as Map<String, Object?>).keys, <String>[
      'type',
      'by',
    ]);
    // Only the argument without a default is required.
    expect(schema['required'], <String>['type']);

    final result = await tool.run(
      ToolCall(
        name: tool.name,
        arguments: <String, Object?>{'type': 'boat', 'by': 2},
      ),
    );
    expect(result.isError, isFalse);
    expect(session.editing.level.entities.single.position.y, 2.0);
    // The same command, the same history: one undo takes it back.
    session.editing.history.undo();
    expect(session.editing.level.entities.single.position.y, 0.0);

    final refused = await tool.run(
      ToolCall(name: tool.name, arguments: const <String, Object?>{}),
    );
    expect(refused.isError, isTrue);

    sharing.cancel();
    expect(tools.named('boats.raise'), isNull);
  });

  test('a command added later is offered, one withdrawn is not', () {
    final tools = McpTools();
    shareCommands(pieces, tools, session);
    final scope = _Scope('sails');
    pieces.forPlugin(scope).addCommand('furl', (_) => null);
    // Mutation: share once, without listening.
    expect(tools.named('sails.furl'), isNotNull);
    for (final registration in scope.registrations) {
      registration.cancel();
    }
    expect(tools.named('sails.furl'), isNull);
  });

  test('the editor half of a package offers its command under the '
      'package\'s namespace', () async {
    final tools = McpTools();
    shareCommands(pieces, tools, session);
    pieces.forPlugin(_Scope('boats.editor')).addCommand('sink', (_) => null);
    // Mutation: share under the plugin's whole id, `boats.editor.sink`, or
    // name the tool `editor.sink` under `boats`.
    expect(tools.named('boats.sink'), isNotNull);
    expect(tools.named('boats.sink')!.namespace, 'boats');
    expect(tools.tools.map((ProjectTool t) => t.name), <String>[
      'boats.raise',
      'boats.sink',
    ]);
  });

  test('plugin.list says what the plugins brought', () async {
    final answer = await call('plugin.list', const <String, Object?>{});
    // Mutation: leave the commands out of the listing.
    expect(answer.says, contains('boats.raise: type (text), by (number)'));
    expect(answer.says, contains('boats.buoyancy "Buoyancy"'));
    expect(answer.says, contains('boats.hull "Hull": .hull'));
  });

  test(
    'asset.import writes inside the project and places in the level',
    () async {
      File('${project.path}/skiff.hull').writeAsStringSync('keel');
      final answer = await call('asset.import', <String, Object?>{
        'path': '${project.path}/skiff.hull',
        'at': <double>[3.0, 0.0, 3.0],
      });
      expect(answer.did, isTrue, reason: answer.says);
      expect(
        File('${project.path}/assets/hulls/skiff.hull').readAsStringSync(),
        'keel',
      );
      expect(
        session.editing.level.entities.last.string('hull'),
        'hulls/skiff.hull',
      );

      // Mutation: write the importer's files unresolved.
      File('${project.path}/escape.bad').writeAsStringSync('x');
      final escaping = await call('asset.import', <String, Object?>{
        'path': '${project.path}/escape.bad',
      });
      expect(escaping.did, isFalse);
      expect(File('${sandbox.path}/outside.txt').existsSync(), isFalse);

      // A file outside the project is not read.
      File('${sandbox.path}/stray.hull').writeAsStringSync('x');
      final outside = await call('asset.import', <String, Object?>{
        'path': '${sandbox.path}/stray.hull',
      });
      expect(outside.did, isFalse);
      expect(outside.says, contains('outside the project'));

      final unknown = await call('asset.import', <String, Object?>{
        'path': '${project.path}/skiff.glb',
      });
      expect(unknown.says, contains('.hull'));
    },
  );
}
