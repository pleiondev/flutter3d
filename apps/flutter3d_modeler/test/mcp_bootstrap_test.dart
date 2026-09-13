/// `mcp-13n`'s own `--mcp-port` wiring: the GUI's own live [ModelHistory],
/// reachable over a real `HttpServer`, with a real session file an agent
/// finds it by.
///
///     flutter test test/mcp_bootstrap_test.dart
///
/// **Imports `mcp_bootstrap_io.dart` directly, not the conditional facade.**
/// `mcp_bootstrap.dart` picks between this file and `mcp_bootstrap_web.dart`
/// by `dart.library.js_interop`, which is false for a `flutter test` run on
/// the VM either way — going straight to the real implementation is the
/// same file the facade would have picked here, without the indirection.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/mcp_bootstrap_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory workspace;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('flutter3d_modeler_mcp');
  });

  tearDown(() async {
    await stopMcpServer();
    if (workspace.existsSync()) workspace.deleteSync(recursive: true);
  });

  test(
    'starts a real server over the live history, and a real request answers',
    () async {
      final history = ModelHistory(const ModelProject());

      await startMcpServer(
        history: history,
        port: 0,
        sessionDirectory: workspace,
      );

      final sessionFile = File('${workspace.path}/mcp-session.json');
      expect(sessionFile.existsSync(), isTrue);
      final written =
          json.decode(sessionFile.readAsStringSync()) as Map<String, Object?>;
      final port = written['port']! as int;
      final token = written['token']! as String;
      expect(port, greaterThan(0));
      expect(token, isNotEmpty);

      final httpClient = HttpClient();
      addTearDown(() => httpClient.close(force: true));

      Future<Map<String, Object?>> call(Object? body) async {
        final request = await httpClient.postUrl(
          Uri.parse('http://127.0.0.1:$port/mcp?token=$token'),
        );
        request.headers.contentType = ContentType.json;
        request.write(json.encode(body));
        final response = await request.close();
        // A notification (no `id`) gets `202 Accepted` and no body; a
        // request gets `200` and its reply.
        expect(
          response.statusCode,
          anyOf(HttpStatus.ok, HttpStatus.accepted),
        );
        final text = await response.transform(utf8.decoder).join();
        return text.isEmpty
            ? const <String, Object?>{}
            : json.decode(text) as Map<String, Object?>;
      }

      // The protocol's own handshake — a raw JSON-RPC exchange rather than
      // `dart_mcp`'s own `MCPClient` (which `http_transport_test.dart`,
      // in `flutter3d_model_mcp` itself, already runs against this same
      // server): this row's own acceptance is that *this* wiring — the port
      // and token this session actually wrote — reaches a live server
      // answering for the GUI's own document, not a second, disconnected
      // one, and the raw exchange is what shows that with the least
      // machinery standing between the assertion and the request.
      final initialized = await call(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': <String, Object?>{
          'protocolVersion': '2024-11-05',
          'capabilities': <String, Object?>{},
          'clientInfo': <String, Object?>{
            'name': 'mcp_bootstrap_test',
            'version': '0.0.1',
          },
        },
      });
      expect(initialized['result'], isNotNull);

      // A notification: no `id`, and the server sends no body back.
      await call(<String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      });

      final listed = await call(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/list',
      });
      final tools = (listed['result']! as Map<String, Object?>)['tools']!
          as List<Object?>;
      expect(tools, isNotEmpty);
    },
  );

  test('a second start while one is running does nothing', () async {
    final history = ModelHistory(const ModelProject());
    await startMcpServer(
      history: history,
      port: 0,
      sessionDirectory: workspace,
    );
    final sessionFile = File('${workspace.path}/mcp-session.json');
    final firstToken =
        (json.decode(sessionFile.readAsStringSync())
                as Map<String, Object?>)['token']!
            as String;

    // A different history, a different directory — proof the second call
    // is a no-op rather than silently rebinding over the first server.
    final second = Directory.systemTemp.createTempSync(
      'flutter3d_modeler_mcp_second',
    );
    addTearDown(() => second.deleteSync(recursive: true));
    await startMcpServer(
      history: ModelHistory(const ModelProject()),
      port: 0,
      sessionDirectory: second,
    );

    expect(File('${second.path}/mcp-session.json').existsSync(), isFalse);
    final stillToken =
        (json.decode(sessionFile.readAsStringSync())
                as Map<String, Object?>)['token']!
            as String;
    expect(stillToken, firstToken);
  });

  test('stopMcpServer removes the session file', () async {
    final history = ModelHistory(const ModelProject());
    await startMcpServer(
      history: history,
      port: 0,
      sessionDirectory: workspace,
    );
    final sessionFile = File('${workspace.path}/mcp-session.json');
    expect(sessionFile.existsSync(), isTrue);

    await stopMcpServer();

    expect(sessionFile.existsSync(), isFalse);
  });

  test('stopMcpServer with nothing running is a no-op, not a crash', () async {
    await stopMcpServer();
  });
}
