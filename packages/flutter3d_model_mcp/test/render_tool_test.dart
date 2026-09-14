/// `render`: `mcp-06n`'s own acceptance, driven over the real protocol the
/// same way `agent_builds_a_table_test.dart` drives every other tool —
/// a pair of in-memory streams, the real client and the real server.
library;

import 'dart:convert';
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
    'an empty project refuses rather than handing back a blank picture',
    () async {
      final result = await call('render');
      expect(result.isError, isTrue);
      expect(result.content.single.isText, isTrue);
      expect(
        (result.content.single as TextContent).text,
        contains('no objects'),
      );
    },
  );

  test('render on a real project gives a non-empty image', () async {
    await call('addPrimitive', <String, Object?>{'kind': 'box'});

    final result = await call('render');
    expect(result.isError, isNot(true));
    expect(result.content, hasLength(2));
    expect(result.content.first.isText, isTrue);

    final image = result.content.last;
    expect(image.isImage, isTrue);
    final imageContent = image as ImageContent;
    expect(imageContent.mimeType, 'image/png');

    final png = base64Decode(imageContent.data);
    final decoded = await decodeImagePure(png);
    expect(decoded, isNotNull);
    expect(decoded!.width, greaterThan(0));
    expect(decoded.height, greaterThan(0));
  });

  test(
    'a view name outside the schema is refused, not silently drawn',
    () async {
      await call('addPrimitive', <String, Object?>{'kind': 'box'});
      final result = await call('render', <String, Object?>{'view': 'nope'});
      expect(
        result.isError,
        isTrue,
        reason: 'the schema names seven views; this is not one of them',
      );
    },
  );
}
