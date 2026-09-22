/// `mcp-16d`'s own mechanism: [ModelMcpServer.extraTools] and
/// [ModelHttpServer.start]'s own `extraTools` are how a GUI application
/// offers `ui.*` tools beside the ordinary document ones, without this
/// package knowing what any of them do. The actual `ui.*` tools live in
/// `apps/flutter3d_modeler` (they reach `ModelerCubit`, which this package
/// cannot import) — what belongs here is the plumbing: nothing extra is
/// listed unless a caller passes it, and whatever is passed is listed and
/// callable exactly like every other tool.
library;

import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  late Directory workspace;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync(
      'flutter3d_model_mcp_extra_tools',
    );
  });

  tearDown(() {
    workspace.deleteSync(recursive: true);
  });

  test('no extraTools means no tool named ui.* — the headless shape', () async {
    final connection = await _connect(
      ModelSession.open('${workspace.path}/plain.f3dproj'),
    );
    final tools = await connection.listTools();
    expect(tools.tools.where((tool) => tool.name.startsWith('ui.')), isEmpty);
    await connection.shutdown();
  });

  test('a passed extraTool is listed and callable — the GUI shape', () async {
    var called = false;
    final extra = ModelPictureTool(
      Tool(
        name: 'ui.test',
        description: 'a stand-in UI tool',
        inputSchema: ObjectSchema(),
      ),
      (ModelSession session, Map<String, Object?> arguments) async {
        called = true;
        return (did: true, says: 'did the thing', png: null);
      },
    );

    final connection = await _connect(
      ModelSession.open('${workspace.path}/extra.f3dproj'),
      extraTools: <ModelPictureTool>[extra],
    );

    final tools = await connection.listTools();
    expect(tools.tools.map((tool) => tool.name), contains('ui.test'));

    final result = await connection.callTool(
      CallToolRequest(name: 'ui.test', arguments: const <String, Object?>{}),
    );
    expect(result.isError, isNot(true));
    expect(called, isTrue);

    await connection.shutdown();
  });
}

Future<ServerConnection> _connect(
  ModelSession session, {
  List<ModelPictureTool> extraTools = const <ModelPictureTool>[],
}) async {
  final pipe = StreamChannelController<String>(sync: true);
  ModelMcpServer(pipe.local, session: session, extraTools: extraTools);

  final client = MCPClient(
    Implementation(name: 'test', version: modelMcpVersion),
  );
  final connection = client.connectServer(pipe.foreign);
  await connection.initialize(
    InitializeRequest(
      protocolVersion: ProtocolVersion.latestSupported,
      capabilities: client.capabilities,
      clientInfo: client.implementation,
    ),
  );
  connection.notifyInitialized();
  return connection;
}
