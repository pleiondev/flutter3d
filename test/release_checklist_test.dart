/// `tool/release_checklist.sh`: after the site is deployed on a tag, five
/// pages answer 200 or the release is not done.
///
///     dart test test/release_checklist_test.dart
///
/// Against a server on localhost that answers the way the live one might,
/// so the script is proved on what it reads and not on the network.
library;

import 'dart:io';

import 'package:test/test.dart';

/// The five pages, as the script asks for them.
const List<String> _pages = <String>[
  '/',
  '/quickstart/',
  '/reference/migrating-to-1.0/',
  '/download/',
  '/changelog/',
];

Future<HttpServer> _site(Map<String, int> statusByPath) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    final status = statusByPath[request.uri.path] ?? HttpStatus.notFound;
    request.response
      ..statusCode = status
      ..write('<html><body>flutter3d 1.0.0-rc.1</body></html>');
    request.response.close();
  });
  return server;
}

Future<ProcessResult> _check(
  HttpServer server, [
  List<String> more = const [],
]) => Process.run('bash', <String>[
  'tool/release_checklist.sh',
  '--base',
  'http://127.0.0.1:${server.port}',
  ...more,
]);

void main() {
  test('five pages that answer 200 pass, and each is named', () async {
    final server = await _site({for (final page in _pages) page: 200});
    addTearDown(server.close);
    final result = await _check(server);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    for (final page in _pages) {
      expect(result.stdout, contains(page));
    }
  });

  test(
    'one page that does not answer 200 fails the checklist by name',
    () async {
      // Mutation: let the script exit with the last curl's status rather than
      // any of them, and a missing download page in the middle passes.
      final server = await _site({
        for (final page in _pages) page: page == '/download/' ? 404 : 200,
      });
      addTearDown(server.close);
      final result = await _check(server);
      expect(result.exitCode, 1);
      expect(result.stdout, contains('404'));
      expect(result.stdout, contains('/download/'));
    },
  );

  test('a redirect is not a 200', () async {
    final server = await _site({
      for (final page in _pages) page: page == '/changelog/' ? 301 : 200,
    });
    addTearDown(server.close);
    final result = await _check(server);
    expect(result.exitCode, 1);
    expect(result.stdout, contains('/changelog/'));
  });

  test('the index carries the version the tag names', () async {
    final server = await _site({for (final page in _pages) page: 200});
    addTearDown(server.close);
    expect((await _check(server, ['--version', '1.0.0-rc.1'])).exitCode, 0);
    final stale = await _check(server, ['--version', '1.0.0-rc.2']);
    expect(stale.exitCode, 1);
    expect(stale.stdout, contains('1.0.0-rc.2'));
  });
}
