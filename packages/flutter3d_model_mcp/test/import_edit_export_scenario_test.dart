/// An import-edit-export flow, end to end, over the real MCP protocol: an
/// agent brings in somebody else's asset, changes it, and ships it back out
/// — the shape most real modelling work actually takes, as distinct from
/// `agent_builds_a_table_test.dart`'s own "start from a primitive."
///
/// `test/fixtures/table.glb` is that other test's own export — the same
/// five objects (`top`, `leg 1`..`leg 4`) and the `oak` material it built —
/// so this reads back exactly what a real agent handoff would produce.
///
///     dart test test/import_edit_export_scenario_test.dart
library;

import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  late Directory workspace;
  late MCPClient client;
  late ServerConnection connection;
  late ModelSession session;

  setUp(() async {
    workspace = Directory.systemTemp.createTempSync('flutter3d_model_mcp_import');
    session = ModelSession.open('${workspace.path}/scene.f3dproj');

    final pipe = StreamChannelController<String>(sync: true);
    ModelMcpServer(pipe.local, session: session);

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

  test(
    "somebody else's table: imported, renamed, given a level of detail, exported again",
    () async {
      final imported = await call('import', <String, Object?>{
        'from': 'test/fixtures/table.glb',
      });
      expect(imported.did, isTrue, reason: imported.says);

      final listing = await call('list');
      // The same five objects `agent_builds_a_table_test.dart` built —
      // arriving as a caller who never ran that test would see them.
      expect(listing.says, contains('top'));
      expect(listing.says, contains('leg 1'));
      expect(listing.says, contains('leg 4'));
      expect(session.project.objects, hasLength(5));
      expect(session.project.materials, hasLength(1));
      expect(session.project.materials.single.surface.name, 'oak');

      // An edit an agent makes to somebody else's asset, not to one it
      // built itself: rename the top, and give it a level of detail — the
      // table might be one prop among many in a scene, and most of them
      // will be far from the camera.
      final tableTop = session.project.objects.firstWhere((o) => o.name == 'top');
      final renamed = await call('rename', <String, Object?>{
        'id': tableTop.id,
        'to': 'coffee table top',
      });
      expect(renamed.did, isTrue, reason: renamed.says);

      final lod = await call('addLod', <String, Object?>{
        'id': tableTop.id,
        'ratio': 0.4,
        'maxScreenFraction': 0.15,
      });
      expect(lod.did, isTrue, reason: lod.says);
      expect(session.project[tableTop.id]!.lods, hasLength(1));

      // Shipped back out — the whole point of bringing it in.
      final exported = await call('export', <String, Object?>{
        'to': '${workspace.path}/coffee_table.glb',
      });
      expect(exported.did, isTrue, reason: exported.says);

      final bytes = await File('${workspace.path}/coffee_table.glb').readAsBytes();
      final decoded = await GltfLoader().load(bytes);
      // Five surfaces still, the material still one shared row, and the
      // edited object's new name carried all the way to the file a caller
      // downstream — a game engine, another tool — would actually open.
      expect(decoded.surfaces, hasLength(5));
      expect(decoded.materials, hasLength(1));
      expect(decoded.materials.single.name, 'oak');
      expect(
        decoded.nodes.map((n) => n.name),
        contains('coffee table top'),
      );
    },
  );
}
