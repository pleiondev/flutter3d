/// Reads the session file `apps/flutter3d_modeler/lib/src/mcp_bootstrap_io.dart`
/// writes — `mcp-session.json`, `{"port": <int>, "token": <string>}` — the
/// same shape and the same file `apps/flutter3d_modeler/test/mcp_bootstrap_test.dart`
/// and `mcp_ui_tools_test.dart` already read directly with a raw `HttpClient`
/// rather than a client library, since nothing in this repository is one yet.
/// [McpSession.readFile] is that same read, factored out so `bin/shoot.dart`
/// and its tests share it instead of each parsing the file by hand.
library;

import 'dart:convert';
import 'dart:io';

/// Where a running `ModelHttpServer` answers, and the token every request
/// must present — see `flutter3d_mcp_kit`'s `writeMcpSessionFile`.
final class McpSession {
  const McpSession({required this.port, required this.token});

  final int port;
  final String token;

  /// The endpoint every JSON-RPC request in this tool posts to.
  Uri get endpoint => Uri.parse('http://127.0.0.1:$port/mcp?token=$token');

  /// Reads [file] the way `mcp_bootstrap_io.dart` wrote it. Throws a
  /// [FormatException] for anything else — a stale or hand-edited file, or
  /// no server running at all (the file does not exist), is a loud failure
  /// here rather than a `null` a caller three steps later has to explain.
  factory McpSession.readFile(File file) {
    if (!file.existsSync()) {
      throw FormatException(
        'no mcp-session.json at ${file.path} — start the modeler with a '
        '--mcp-port first',
      );
    }
    final decoded = json.decode(file.readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      throw FormatException('${file.path} is not a JSON object');
    }
    final port = decoded['port'];
    final token = decoded['token'];
    if (port is! int || token is! String || token.isEmpty) {
      throw FormatException(
        '${file.path} is missing "port" (an int) or "token" (a string): '
        '$decoded',
      );
    }
    return McpSession(port: port, token: token);
  }
}
