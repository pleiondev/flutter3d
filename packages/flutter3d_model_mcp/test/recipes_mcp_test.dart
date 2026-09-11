/// `cleanup`, `buildFrom` and `inspect` over the real MCP protocol —
/// narrowed to the JSON plumbing a plain `ModelSession` unit test
/// (`recipes_test.dart`) cannot see: `buildFrom`'s own `spec` argument is a
/// list of objects, and the risk is in that list surviving `tools/call`'s
/// own JSON on the way to `ModelSession.buildFrom`, the same risk
/// `bake_texture_graph_mcp_test.dart` checked for `setMaterialGraph`'s own
/// nested `graph`.
///
///     dart test test/recipes_mcp_test.dart
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

  setUp(() async {
    workspace = Directory.systemTemp.createTempSync(
      'flutter3d_model_mcp_recipes',
    );
    final pipe = StreamChannelController<String>(sync: true);
    ModelMcpServer(
      pipe.local,
      session: ModelSession.open('${workspace.path}/scene.f3dproj'),
    );

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

  test('a spec list of objects survives tools/call and builds a hierarchy', () async {
    final built = await call('buildFrom', <String, Object?>{
      'spec': <Map<String, Object?>>[
        <String, Object?>{'kind': 'box', 'name': 'trunk'},
        <String, Object?>{
          'kind': 'sphere',
          'name': 'leaves',
          'parent': 0,
          'at': <double>[0, 2, 0],
        },
      ],
    });
    expect(built.did, isTrue, reason: built.says);

    final listing = await call('list');
    expect(listing.says, contains('trunk'));
    expect(listing.says, contains('leaves'));
  });

  test('cleanup with nothing to clean answers plainly over the protocol', () async {
    await call('addPrimitive', <String, Object?>{'kind': 'box'});
    // A still-parametric box has no mesh at all; baking gives cleanup an
    // already-clean one to find nothing wrong with.
    await call('bakeToMesh', <String, Object?>{'id': 1});
    final cleaned = await call('cleanup');
    expect(cleaned.did, isFalse);
    expect(cleaned.says, contains('nothing needed cleaning'));
  });

  test('makeGameReady refuses an unknown profile name over the protocol', () async {
    final refused = await call('makeGameReady', <String, Object?>{
      'profile': 'potato',
    });
    expect(refused.did, isFalse);
    expect(refused.says, contains('potato'));
  });

  test('makeGameReady triangulates a baked mesh over the protocol', () async {
    await call('addPrimitive', <String, Object?>{'kind': 'box'});
    await call('bakeToMesh', <String, Object?>{'id': 1});
    final made = await call('makeGameReady', <String, Object?>{
      'profile': 'desktop',
    });
    expect(made.did, isTrue, reason: made.says);
  });

  test('inspect reports through the protocol what list and check would '
      'separately', () async {
    await call('addPrimitive', <String, Object?>{'kind': 'box'});
    final inspected = await call('inspect');
    expect(inspected.did, isTrue);
    expect(inspected.says, contains('1 object'));
  });
}
