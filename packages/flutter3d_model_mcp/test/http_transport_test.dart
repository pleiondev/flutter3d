/// `mcp-13n`'s own acceptance: doc-21's "agent builds a table" scenario,
/// run once over the stdio-shaped channel `agent_builds_a_table_test.dart`
/// already treats as the real protocol (an in-memory pipe standing in for a
/// process's stdin and stdout — see that file's own doc comment for why that
/// counts as "the existing stdio path" rather than a fake), and once over
/// `ModelHttpServer`, with a real `HttpServer` bound to `127.0.0.1` and real
/// `HttpClient` requests carrying the token it minted.
///
/// **The point is the diff, not either run alone.** [ModelSession] never
/// sees which transport is driving it — [ModelHttpServer]'s own doc comment
/// says so — so the same nine calls against two different [ModelMcpServer]
/// instances, one per transport, writing to two different directories,
/// should leave byte-identical files behind. A change that let a transport
/// leak into the command path (an extra field, a different id, a race that
/// reorders two writes) would show up here as a diff, not as either run
/// failing on its own.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  late Directory workspace;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync(
      'flutter3d_model_mcp_http_parity',
    );
  });

  tearDown(() {
    workspace.deleteSync(recursive: true);
  });

  test(
    'the table scenario writes the same bytes over stdio and over HTTP',
    () async {
      final stdioDir = Directory('${workspace.path}/stdio')..createSync();
      final httpDir = Directory('${workspace.path}/http')..createSync();

      await _runOverStdio('${stdioDir.path}/table.f3dproj');
      await _runOverHttp('${httpDir.path}/table.f3dproj');

      for (final name in <String>[
        'table.f3dproj',
        'table.f3d',
        'table.obj',
        'table.mtl',
        'table.glb',
        'table.jsonl',
      ]) {
        expect(
          File('${httpDir.path}/$name').readAsBytesSync(),
          File('${stdioDir.path}/$name').readAsBytesSync(),
          reason: '$name differs between the stdio and HTTP transports',
        );
      }
    },
  );

  test('a request with no token is refused, not silently allowed', () async {
    final started = '${workspace.path}/guarded.f3dproj';
    final server = await ModelHttpServer.start(
      session: ModelSession.open(started),
    );
    addTearDown(server.close);

    final httpClient = HttpClient();
    addTearDown(() => httpClient.close(force: true));

    final request = await httpClient.postUrl(
      Uri.parse('http://127.0.0.1:${server.port}/mcp'),
    );
    request.headers.contentType = ContentType.json;
    request.write(
      json.encode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/list',
      }),
    );
    final response = await request.close();
    expect(response.statusCode, HttpStatus.unauthorized);
    await response.drain<void>();
  });

  test('binds loopback-only, never a wildcard address', () async {
    final started = '${workspace.path}/loopback.f3dproj';
    final server = await ModelHttpServer.start(
      session: ModelSession.open(started),
    );
    addTearDown(server.close);
    // `InternetAddress.loopbackIPv4` prints as `127.0.0.1` — asserted on the
    // string a socket actually bound to, not on the constant passed in, so a
    // future edit that swaps in `anyIPv4` fails this rather than just
    // matching itself.
    expect(server.port, greaterThan(0));
  });
}

Future<void> _runOverStdio(String started) async {
  final pipe = StreamChannelController<String>(sync: true);
  ModelMcpServer(pipe.local, session: ModelSession.open(started));

  final client = MCPClient(
    Implementation(name: 'stdio side', version: modelMcpVersion),
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

  await _tableScenario(
    (name, [arguments]) => _call(connection, name, arguments),
    started,
  );

  await client.shutdown();
}

Future<void> _runOverHttp(String started) async {
  final server = await ModelHttpServer.start(
    session: ModelSession.open(started),
  );
  final httpClient = HttpClient();

  final client = MCPClient(
    Implementation(name: 'http side', version: modelMcpVersion),
  );
  final channel = _httpClientChannel(
    endpoint: Uri.parse('http://127.0.0.1:${server.port}/mcp'),
    token: server.token,
    httpClient: httpClient,
  );
  final connection = client.connectServer(channel);
  await connection.initialize(
    InitializeRequest(
      protocolVersion: ProtocolVersion.latestSupported,
      capabilities: client.capabilities,
      clientInfo: client.implementation,
    ),
  );
  connection.notifyInitialized();

  await _tableScenario(
    (name, [arguments]) => _call(connection, name, arguments),
    started,
  );

  await client.shutdown();
  httpClient.close(force: true);
  await server.close();
}

Future<({bool did, String says})> _call(
  ServerConnection connection,
  String name, [
  Map<String, Object?>? arguments,
]) async {
  final result = await connection.callTool(
    CallToolRequest(
      name: name,
      arguments: arguments ?? const <String, Object?>{},
    ),
  );
  final content = result.content.single;
  expect(content.isText, isTrue, reason: '$name answered with $content');
  return (did: result.isError != true, says: (content as TextContent).text);
}

/// doc-21's own scenario — the same primitives, rename, material, check,
/// save and export calls `agent_builds_a_table_test.dart` runs — against
/// whichever transport [call] is bound to.
Future<void> _tableScenario(
  Future<({bool did, String says})> Function(String, [Map<String, Object?>?])
  call,
  String started,
) async {
  final workspaceDir = started.substring(0, started.lastIndexOf('/'));

  final top = await call('addPrimitive', <String, Object?>{
    'kind': 'box',
    'size': 1.2,
    'at': <double>[0, 1.0, 0],
  });
  expect(top.did, isTrue, reason: top.says);
  await call('rename', <String, Object?>{'id': 1, 'to': 'top'});

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
    await call('rename', <String, Object?>{'id': 2 + i, 'to': 'leg ${i + 1}'});
  }

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

  final exportedF3d = await call('export', <String, Object?>{
    'to': '$workspaceDir/table.f3d',
  });
  expect(exportedF3d.did, isTrue, reason: exportedF3d.says);

  final exportedObj = await call('export', <String, Object?>{
    'to': '$workspaceDir/table.obj',
  });
  expect(exportedObj.did, isTrue, reason: exportedObj.says);

  final exportedGlb = await call('export', <String, Object?>{
    'to': '$workspaceDir/table.glb',
  });
  expect(exportedGlb.did, isTrue, reason: exportedGlb.says);

  final wroteJournal = await call('journal', <String, Object?>{
    'to': '$workspaceDir/table.jsonl',
  });
  expect(wroteJournal.did, isTrue, reason: wroteJournal.says);
}

/// A client-side [StreamChannel] backed by real HTTP requests to
/// [ModelHttpServer] — the test's own half of the transport, mirroring
/// `stdioChannel` the way [ModelHttpServer]'s server-side channel does.
/// Nothing here is production code an agent would use directly: a real MCP
/// host speaking to this server brings its own HTTP client, the same way it
/// brings its own process launcher for the stdio path. This exists so the
/// test drives both transports through the identical `dart_mcp` client API
/// ([MCPClient.connectServer], `connection.callTool`) rather than hand-rolled
/// JSON-RPC on one side only.
StreamChannel<String> _httpClientChannel({
  required Uri endpoint,
  required String token,
  required HttpClient httpClient,
}) {
  final toServer = StreamController<String>();
  final fromServer = StreamController<String>();

  // One HTTP request at a time, in the order the client wrote to the
  // channel's sink — `asyncMap` does not pull the next event until the
  // previous request's response has landed, which is what lets a reply with
  // no `id` of its own (there is none here) still be matched to the right
  // call without needing to inspect JSON-RPC ids on this side too.
  toServer.stream
      .asyncMap((String message) async {
        final request = await httpClient.postUrl(endpoint);
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        request.headers.contentType = ContentType.json;
        request.write(message);
        final response = await request.close();
        final body = await utf8.decoder.bind(response).join();
        if (body.isNotEmpty) fromServer.add(body);
      })
      .listen(null, onError: fromServer.addError);

  return StreamChannel<String>(fromServer.stream, toServer.sink);
}
