/// `McpSession.readFile` — the same `{"port": ..., "token": ...}` shape
/// `mcp_bootstrap_io.dart` writes, read back with no server involved: a
/// plain file on disk, not a socket.
///
///     dart test tool/tutorial/test/mcp_session_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tutorial/tutorial.dart';

void main() {
  late Directory workspace;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('mcp_session_test');
  });

  tearDown(() {
    if (workspace.existsSync()) workspace.deleteSync(recursive: true);
  });

  test('reads port and token, and builds the loopback endpoint', () {
    final file = File('${workspace.path}/mcp-session.json')
      ..writeAsStringSync(
        json.encode(<String, Object?>{'port': 54321, 'token': 'sekret'}),
      );

    final session = McpSession.readFile(file);

    expect(session.port, 54321);
    expect(session.token, 'sekret');
    expect(
      session.endpoint,
      Uri.parse('http://127.0.0.1:54321/mcp?token=sekret'),
    );
  });

  test('refuses a missing file', () {
    expect(
      () => McpSession.readFile(File('${workspace.path}/nope.json')),
      throwsFormatException,
    );
  });

  test('refuses a file with no token', () {
    final file = File('${workspace.path}/mcp-session.json')
      ..writeAsStringSync(json.encode(<String, Object?>{'port': 1}));
    expect(() => McpSession.readFile(file), throwsFormatException);
  });

  test('refuses a file whose port is not an int', () {
    final file = File('${workspace.path}/mcp-session.json')
      ..writeAsStringSync(
        json.encode(<String, Object?>{'port': '1', 'token': 't'}),
      );
    expect(() => McpSession.readFile(file), throwsFormatException);
  });

  test('refuses a file that is not a JSON object', () {
    final file = File('${workspace.path}/mcp-session.json')
      ..writeAsStringSync('[1, 2, 3]');
    expect(() => McpSession.readFile(file), throwsFormatException);
  });
}
