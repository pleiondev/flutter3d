/// `renderSheet`: `mcp-07n`'s own acceptance, driven over the real protocol —
/// the same shape `render_tool_test.dart` already drives `render` through.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  late Directory workspace;
  late MCPClient client;
  late ServerConnection connection;

  setUp(() async {
    workspace = Directory.systemTemp.createTempSync('flutter3d_model_mcp');

    final pipe = StreamChannelController<String>(sync: true);
    ModelMcpServer(
      pipe.local,
      session: ModelSession.open('${workspace.path}/table.f3dproj'),
    );

    client = MCPClient(
      Implementation(name: 'the suite', version: modelMcpVersion),
    );
    connection = client.connectServer(pipe.foreign);
    await connection.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: client.capabilities,
        clientInfo: client.implementation,
      ),
    );
    connection.notifyInitialized();
  });

  tearDown(() async {
    await client.shutdown();
    workspace.deleteSync(recursive: true);
  });

  Future<CallToolResult> call(
    String name, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]) => connection.callTool(CallToolRequest(name: name, arguments: arguments));

  test(
    'an empty project refuses rather than handing back a blank sheet',
    () async {
      final result = await call('renderSheet');
      expect(result.isError, isTrue);
      expect(
        (result.content.single as TextContent).text,
        contains('no objects'),
      );
    },
  );

  test('renderSheet on a real project gives a non-empty 2x2 image', () async {
    await call('addPrimitive', <String, Object?>{'kind': 'box'});

    final result = await call('renderSheet');
    expect(result.isError, isNot(true));
    expect(result.content, hasLength(2));

    final imageContent = result.content.last as ImageContent;
    expect(imageContent.mimeType, 'image/png');

    final png = base64Decode(imageContent.data);
    final decoded = await decodeImagePure(png);
    expect(decoded, isNotNull);
    // The default sheet is two square 256-wide quadrants side by side.
    expect(decoded!.width, 512);
    expect(decoded.height, 512);
  });
}
