/// `ux-45`: the person stays in charge — a paused agent is refused by name,
/// and every step it made is stamped with the client that made it.
///
///     dart test test/person_in_charge_test.dart
library;

import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  late Directory workspace;
  late ModelSession session;
  late MCPClient client;
  late ServerConnection connection;

  /// The person's own brake, read by the server before every call.
  var paused = false;

  Future<void> connect({String name = 'claude'}) async {
    final pipe = StreamChannelController<String>(sync: true);
    ModelMcpServer(
      pipe.local,
      session: session,
      pausedBecause: () =>
          paused ? 'the person has paused agent calls' : null,
    );
    client = MCPClient(Implementation(name: name, version: modelMcpVersion));
    connection = client.connectServer(pipe.foreign);
    await connection.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: client.capabilities,
        clientInfo: client.implementation,
      ),
    );
    connection.notifyInitialized();
  }

  setUp(() async {
    paused = false;
    workspace = Directory.systemTemp.createTempSync(
      'flutter3d_model_mcp_in_charge',
    );
    session = ModelSession.open('${workspace.path}/scene.f3dproj');
    await connect();
  });

  tearDown(() async {
    await client.shutdown();
    workspace.deleteSync(recursive: true);
  });

  Future<CallToolResult> call(
    String name, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]) => connection.callTool(
    CallToolRequest(name: name, arguments: arguments),
  );

  String saidBy(CallToolResult result) =>
      (result.content.first as TextContent).text;

  test('a paused agent is refused, and told why', () async {
    expect((await call('addPrimitive', <String, Object?>{'kind': 'box'})).isError,
        isNot(true));

    paused = true;
    final CallToolResult refused = await call(
      'addPrimitive',
      <String, Object?>{'kind': 'sphere'},
    );

    // Mutation: let the call through, or drop it silently. A person's only
    // ways to stop an agent were killing the process — which loses the
    // session — and closing the window, which loses the work; and an agent
    // that is dropped rather than told cannot say so, it just retries.
    expect(refused.isError, isTrue);
    expect(saidBy(refused), contains('paused'));
    expect(session.project.objects, hasLength(1));

    paused = false;
    expect(
      (await call('addPrimitive', <String, Object?>{'kind': 'sphere'})).isError,
      isNot(true),
    );
    expect(session.project.objects, hasLength(2));
  });

  test('a pause refuses a read as well as an edit', () async {
    paused = true;
    expect((await call('list')).isError, isTrue);
  });

  test('the client name is on every step it makes', () async {
    await call('addPrimitive', <String, Object?>{'kind': 'box'});
    await call('rename', <String, Object?>{'id': 1, 'to': 'theirs'});

    // Mutation: stamp every agent step `agent` and nothing else. With two
    // clients on one document that is one undo stack and no way to tell
    // which of them did what.
    expect(
      session.history.authorship.map((it) => it.client),
      everyElement('claude'),
    );
    expect(session.client, 'claude');
  });

  test('a person taking over an agent step stops the agent undoing it',
      () async {
    await call('addPrimitive', <String, Object?>{'kind': 'box'});
    await call('moveBy', <String, Object?>{
      'by': <double>[0, 1, 0],
    });

    // The person drags the operation card's own slider: the same command,
    // different distance, amended by a hand rather than by the agent.
    expect(
      session.history.amend(MoveBy(Vector3(0, 2, 0))),
      isNull,
    );

    final CallToolResult refused = await call('undo');
    expect(refused.isError, isTrue);
    expect(saidBy(refused), contains("person's own"));
    expect(session.project[1]!.transform.storage[13], closeTo(2.0, 1e-6));
  });
}
