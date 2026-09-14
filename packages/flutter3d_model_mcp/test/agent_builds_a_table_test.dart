/// A table, built by an agent, and the files that come out.
///
/// **A whole session, driven through the real protocol.** The client and the
/// server here are the ones a host would run; what is faked is only the pipe
/// between them, a pair of in-memory streams instead of a process's stdin and
/// stdout — the same arrangement `flutter3d_editor_mcp`'s `three_torches_test.dart`
/// uses, for the same reason: this covers what a unit test of `ModelSession`
/// cannot, that every tool is registered under the name the table claims, that
/// the schemas accept what the tools' own descriptions tell an agent to send,
/// and that a refusal comes back as a result the model can read rather than a
/// dead connection.
///
/// **And it diffs bytes, which is the point.** `writeProject` is already
/// deterministic — `project_format_test.dart` holds that — so a fixture is a
/// fair thing to compare against, and a change that moves one number moves one
/// line of a diff a person can read. `table.glb` is `GltfWriter` (`fmt-06`),
/// alongside `.f3d` and `.obj`/`.mtl` — the three formats an agent can export
/// this project to today.
library;

import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  late Directory workspace;
  late MCPClient client;
  late ServerConnection connection;
  late String started;

  setUp(() async {
    workspace = Directory.systemTemp.createTempSync('flutter3d_model_mcp');
    started = '${workspace.path}/table.f3dproj';

    final pipe = StreamChannelController<String>(sync: true);
    ModelMcpServer(pipe.local, session: ModelSession.open(started));

    client = MCPClient(
      Implementation(name: 'the suite', version: modelMcpVersion),
    );
    connection = client.connectServer(pipe.foreign);
    final ready = await connection.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: client.capabilities,
        clientInfo: client.implementation,
      ),
    );
    expect(ready.capabilities.tools, isNotNull);
    connection.notifyInitialized();
  });

  tearDown(() async {
    await client.shutdown();
    workspace.deleteSync(recursive: true);
  });

  Future<({bool did, String says})> call(
    String name, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]) async {
    final result = await connection.callTool(
      CallToolRequest(name: name, arguments: arguments),
    );
    final content = result.content.single;
    expect(content.isText, isTrue, reason: '$name answered with $content');
    return (did: result.isError != true, says: (content as TextContent).text);
  }

  test('a path that does not exist yet starts a fresh project', () async {
    expect((await call('list')).says, contains('the project is empty'));
  });

  test('the tools an agent is offered are the ones it can call', () async {
    final offered = await connection.listTools(ListToolsRequest());
    expect(offered.tools.map((Tool it) => it.name), <String>[
      ...modelTools.map((ModelTool it) => it.name),
      renderTool.name,
      renderSheetTool.name,
    ], reason: 'tools/list and the table this server was built from disagree');
    for (final tool in offered.tools) {
      expect(tool.description, isNotEmpty, reason: '${tool.name} says nothing');
    }
  });

  test(
    'an id the project does not have is refused rather than ignored',
    () async {
      final missed = await call('rename', <String, Object?>{
        'id': 40,
        'to': 'ghost',
      });
      expect(missed.did, isFalse);
      expect(missed.says, contains('there is no object 40'));
    },
  );

  test('export before anything exists is refused', () async {
    final refused = await call('export', <String, Object?>{
      'to': '${workspace.path}/nothing.f3d',
    });
    expect(refused.did, isFalse);
    expect(refused.says, contains('nothing in this project'));
  });

  test('.gltf says why rather than pretending to write one', () async {
    await call('addPrimitive', <String, Object?>{'kind': 'box'});
    final refused = await call('export', <String, Object?>{
      'to': '${workspace.path}/table.gltf',
    });
    expect(refused.did, isFalse);
    expect(refused.says, contains('not built'));
    expect(refused.says, contains('.glb'));
  });

  test(
    'a table, built, painted, checked, saved, exported and undone',
    () async {
      // The top, on the grid, one metre off the floor.
      final top = await call('addPrimitive', <String, Object?>{
        'kind': 'box',
        'size': 1.2,
        'at': <double>[0, 1.0, 0],
      });
      expect(top.did, isTrue, reason: top.says);
      await call('rename', <String, Object?>{'id': 1, 'to': 'top'});

      // Four legs, one cylinder each, at the corners.
      const corners = <List<double>>[
        <double>[0.5, 0.5, 0.5],
        <double>[-0.5, 0.5, 0.5],
        <double>[0.5, 0.5, -0.5],
        <double>[-0.5, 0.5, -0.5],
      ];
      for (var i = 0; i < corners.length; i++) {
        final leg = await call('addPrimitive', <String, Object?>{
          'kind': 'cylinder',
          'size': 0.1,
          'segments': 12,
          'at': corners[i],
        });
        expect(leg.did, isTrue, reason: leg.says);
        await call('rename', <String, Object?>{
          'id': 2 + i,
          'to': 'leg ${i + 1}',
        });
      }

      final listing = await call('list');
      expect(listing.says, contains('1 top (parametric)'));
      expect(listing.says, contains('5 leg 4 (parametric)'));

      // Paint every object with one wood material.
      final material = await call('addMaterial', <String, Object?>{
        'materialName': 'oak',
      });
      expect(material.did, isTrue, reason: material.says);
      for (var id = 1; id <= 5; id++) {
        final painted = await call('assignMaterial', <String, Object?>{
          'id': id,
          'to': 0,
        });
        expect(painted.did, isTrue, reason: painted.says);
      }

      expect((await call('check')).says, 'no issues');

      final saved = await call('save');
      expect(saved.did, isTrue, reason: saved.says);
      expect(
        File(started).readAsBytesSync(),
        File('test/fixtures/table.f3dproj').readAsBytesSync(),
        reason:
            'the project written after this scenario is not the one in '
            'test/fixtures. If the change was meant, copy the new file over '
            'the fixture and read the diff before you do',
      );

      final exportedF3d = await call('export', <String, Object?>{
        'to': '${workspace.path}/table.f3d',
      });
      expect(exportedF3d.did, isTrue, reason: exportedF3d.says);
      expect(
        File('${workspace.path}/table.f3d').readAsBytesSync(),
        File('test/fixtures/table.f3d').readAsBytesSync(),
      );

      final exportedObj = await call('export', <String, Object?>{
        'to': '${workspace.path}/table.obj',
      });
      expect(exportedObj.did, isTrue, reason: exportedObj.says);
      expect(
        File('${workspace.path}/table.obj').readAsStringSync(),
        File('test/fixtures/table.obj').readAsStringSync(),
      );
      expect(
        File('${workspace.path}/table.mtl').readAsStringSync(),
        File('test/fixtures/table.mtl').readAsStringSync(),
      );

      final exportedGlb = await call('export', <String, Object?>{
        'to': '${workspace.path}/table.glb',
      });
      expect(exportedGlb.did, isTrue, reason: exportedGlb.says);
      expect(
        File('${workspace.path}/table.glb').readAsBytesSync(),
        File('test/fixtures/table.glb').readAsBytesSync(),
      );

      final wroteJournal = await call('journal', <String, Object?>{
        'to': '${workspace.path}/table.jsonl',
      });
      expect(wroteJournal.did, isTrue, reason: wroteJournal.says);
      expect(
        File('${workspace.path}/table.jsonl').readAsStringSync(),
        File('test/fixtures/table.jsonl').readAsStringSync(),
      );

      // Undo the last paint and put it back.
      final back = await call('undo');
      expect(back.did, isTrue);
      expect(back.says, contains('assign a material'));
      final again = await call('redo');
      expect(again.did, isTrue);
    },
  );
}
