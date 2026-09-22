/// `setMaterialGraph`/`bakeTextureGraph` over the real MCP protocol —
/// `agent_builds_a_table_test.dart`'s own harness, narrowed to the two new
/// tools, since the risk these carry that a plain `ModelCommand` unit test
/// (`flutter3d_model_core/test/bake_texture_graph_test.dart`) cannot see is
/// in the argument plumbing itself: a nested `graph.nodes` list surviving
/// `tools/call`'s own JSON on the way to `modelCommandFromJson`.
///
///     dart test test/bake_texture_graph_mcp_test.dart
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
    workspace = Directory.systemTemp.createTempSync('flutter3d_model_mcp_bake');
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

  test('a graph handed to setMaterialGraph as plain JSON survives to '
      'bakeTextureGraph and paints a slot', () async {
    final added = await call('addMaterial', <String, Object?>{
      'materialName': 'chrome',
    });
    expect(added.did, isTrue, reason: added.says);

    final graphed = await call('setMaterialGraph', <String, Object?>{
      'materialIndex': 0,
      'graph': <String, Object?>{
        'nodes': <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'kind': 'color',
            'value': <double>[0.1, 0.2, 0.3, 1.0],
          },
          <String, Object?>{
            'id': 2,
            'kind': 'output',
            'result': 1,
            'slot': 'albedo',
          },
        ],
      },
    });
    expect(graphed.did, isTrue, reason: graphed.says);

    final baked = await call('bakeTextureGraph', <String, Object?>{
      'materialIndex': 0,
      'size': 4,
    });
    expect(baked.did, isTrue, reason: baked.says);
  });

  test('setMaterialGraph with no "graph" clears one', () async {
    await call('addMaterial');
    await call('setMaterialGraph', <String, Object?>{
      'materialIndex': 0,
      'graph': <String, Object?>{
        'nodes': <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'kind': 'color',
            'value': <double>[1, 1, 1, 1],
          },
        ],
      },
    });
    final cleared = await call('setMaterialGraph', <String, Object?>{
      'materialIndex': 0,
    });
    expect(cleared.did, isTrue, reason: cleared.says);

    final baked = await call('bakeTextureGraph', <String, Object?>{
      'materialIndex': 0,
    });
    expect(baked.did, isFalse);
    expect(baked.says, contains('no texture graph'));
  });

  test('bakeTextureGraph on a material that does not exist is refused, '
      'not silently ignored', () async {
    final baked = await call('bakeTextureGraph', <String, Object?>{
      'materialIndex': 9,
    });
    expect(baked.did, isFalse);
    expect(baked.says, contains('9'));
  });
}
