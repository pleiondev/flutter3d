/// A minimal MCP client over [McpSession]'s own loopback HTTP endpoint —
/// the same raw JSON-RPC exchange `mcp_bootstrap_test.dart` and
/// `mcp_ui_tools_test.dart` already run in `apps/flutter3d_modeler/test`,
/// factored out here as the thing `bin/shoot.dart` actually calls. One
/// message per request, matching `LoopbackMcpServer`'s own framing — see
/// that file for why.
library;

import 'dart:convert';
import 'dart:io';

import 'mcp_session.dart';

/// Calls tools over [session]'s loopback socket. [initialize] must run
/// before the first [callTool] — the same handshake every MCP client owes
/// a server before it answers anything else.
final class McpClient {
  McpClient(this.session) : _http = HttpClient();

  final McpSession session;
  final HttpClient _http;
  int _nextId = 1;

  Future<Map<String, Object?>> _post(Object? body) async {
    final request = await _http.postUrl(session.endpoint);
    request.headers.contentType = ContentType.json;
    request.write(json.encode(body));
    final response = await request.close();
    // A notification gets `202 Accepted` and no body; a request gets `200`
    // and its reply — `LoopbackMcpServer._handle`'s own two shapes.
    final text = await response.transform(utf8.decoder).join();
    return text.isEmpty
        ? const <String, Object?>{}
        : json.decode(text) as Map<String, Object?>;
  }

  /// The handshake: `initialize`, then the `notifications/initialized` that
  /// tells the server the client is ready to call tools.
  Future<void> initialize() async {
    await _post(<String, Object?>{
      'jsonrpc': '2.0',
      'id': _nextId++,
      'method': 'initialize',
      'params': <String, Object?>{
        'protocolVersion': '2024-11-05',
        'capabilities': <String, Object?>{},
        'clientInfo': <String, Object?>{
          'name': 'tutorial_shoot',
          'version': '0.0.1',
        },
      },
    });
    await _post(<String, Object?>{
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
    });
  }

  /// Calls tool [name] with [arguments] — a document tool or one of
  /// `mcp-16d`'s `ui.*` tools, `tools/call`'s own request. Throws a
  /// [StateError] naming the tool when the server refuses the call
  /// (`result.isError`), so a scenario that names a stale mode or a dialog
  /// this build has not wired up fails loudly instead of shooting a
  /// screenshot of whatever the screen already showed.
  Future<Map<String, Object?>> callTool(
    String name,
    Map<String, Object?> arguments,
  ) async {
    final reply = await _post(<String, Object?>{
      'jsonrpc': '2.0',
      'id': _nextId++,
      'method': 'tools/call',
      'params': <String, Object?>{'name': name, 'arguments': arguments},
    });
    final result = reply['result'];
    if (result is! Map<String, Object?>) {
      throw StateError('tools/call "$name" got no result: $reply');
    }
    if (result['isError'] == true) {
      throw StateError('tool "$name" refused the call: $result');
    }
    return result;
  }

  /// Closes the underlying socket. Idempotent, the way `HttpClient.close`
  /// already is.
  void close() => _http.close(force: true);
}
