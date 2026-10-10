/// `LoopbackMcpServer` and its session file: who gets in, how much they may
/// send, and who can read the token.
///
///     dart test test/kit/loopback_http_test.dart
///
/// Each test was written by breaking what it covers; the mutation is named.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_mcp/kit.dart';
import 'package:test/test.dart';

const String _token = 'sekret-token-0123456789abcdefghij';

/// A server whose peer answers every request with its own id, so a request
/// that gets in comes back `200`.
Future<LoopbackMcpServer> _echo({int? maxBodyBytes}) => LoopbackMcpServer.start(
  token: _token,
  maxBodyBytes: maxBodyBytes ?? LoopbackMcpServer.defaultMaxBodyBytes,
  serve: (channel) => channel.stream.listen((String message) {
    final id = (jsonDecode(message) as Map<String, Object?>)['id'];
    channel.sink.add(
      jsonEncode(<String, Object?>{'jsonrpc': '2.0', 'id': id, 'result': 1}),
    );
  }),
);

void main() {
  late HttpClient client;

  setUp(() => client = HttpClient());
  tearDown(() => client.close(force: true));

  Future<int> post(
    LoopbackMcpServer server, {
    String? bearer,
    String query = '',
    String? body,
    bool chunked = false,
  }) async {
    final request = await client.postUrl(
      Uri.parse('http://127.0.0.1:${server.port}/mcp$query'),
    );
    if (bearer != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
    }
    request.headers.contentType = ContentType.json;
    final text =
        body ?? jsonEncode(<String, Object?>{'jsonrpc': '2.0', 'id': 7});
    if (chunked) {
      request.headers.chunkedTransferEncoding = true;
    } else {
      request.contentLength = utf8.encode(text).length;
    }
    request.write(text);
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  }

  test(
    'the token is taken from the Authorization header and nowhere else',
    () async {
      final server = await _echo();
      addTearDown(server.close);
      expect(await post(server, bearer: _token), HttpStatus.ok);
      // Mutation: read `?token=` as well, as before 1.0. A URL with the token
      // in it is in shell history and proxy logs, and a page in a browser on
      // this machine can post a form to it.
      expect(
        await post(server, query: '?token=$_token'),
        HttpStatus.unauthorized,
      );
    },
  );

  test('a token that is nearly right is as wrong as one that is not', () async {
    final server = await _echo();
    addTearDown(server.close);
    // Mutation: compare only up to the shorter length, which is the easy
    // way to write a loop that does not stop early. A prefix, or the token
    // with more after it, would get in.
    for (final guess in <String>[
      _token.substring(0, _token.length - 1),
      '${_token}x',
      '${_token.substring(0, _token.length - 1)}X',
      '',
    ]) {
      expect(
        await post(server, bearer: guess),
        HttpStatus.unauthorized,
        reason: guess,
      );
    }
  });

  test('a body over the limit is refused, with a length or without', () async {
    final server = await _echo(maxBodyBytes: 256);
    addTearDown(server.close);
    final big = jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': 7,
      'params': 'x' * 1024,
    });
    // Mutation: read the body whole, as before 1.0. One request could make
    // the process hold as much as it is sent.
    expect(
      await post(server, bearer: _token, body: big),
      HttpStatus.requestEntityTooLarge,
    );
    // Mutation: trust `Content-Length` alone. A chunked body has none.
    expect(
      await post(server, bearer: _token, body: big, chunked: true),
      HttpStatus.requestEntityTooLarge,
    );
    expect(await post(server, bearer: _token), HttpStatus.ok);
  });

  test('the session file is readable by its owner alone', () {
    final dir = Directory.systemTemp.createTempSync('mcp_session_file');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/state/mcp.json');
    writeMcpSessionFile(file, port: 4242, token: _token);

    expect(jsonDecode(file.readAsStringSync()), <String, Object?>{
      'port': 4242,
      'token': _token,
    });
    // Nothing left of the staging file beside it.
    expect(
      file.parent.listSync().map((FileSystemEntity it) => it.path),
      <String>[file.path],
    );
    if (Platform.isWindows) return;
    // Mutation: write it with the default permissions, as before 1.0.
    // Under a usual umask that is `rw-r--r--`, and any user on the machine
    // reads the token.
    expect(file.statSync().modeString(), 'rw-------');
  });
}
