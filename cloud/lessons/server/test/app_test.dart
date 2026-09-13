import 'package:flutter3d_lessons/src/config.dart';
import 'package:flutter3d_lessons/src/http/app.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  const config = Config(port: 0, baseUrl: 'https://lessons.pleion.dev');
  final handler = buildHandler(config);

  Future<Response> get(String path) => Future.sync(
    () => handler(Request('GET', Uri.parse('https://lessons.pleion.dev$path'))),
  );

  group('/health', () {
    test('answers ok', () async {
      final response = await get('/health');
      expect(response.statusCode, 200);
      expect(await response.readAsString(), 'ok');
    });
  });

  group('/', () {
    // Found live: the bare domain fell through to the router's
    // `notFoundHandler`, which answered "the lesson was not found" — true of
    // nothing the visitor asked for, since they named no lesson at all.
    test('lists the known lessons instead of falling through to 404', () async {
      final response = await get('/');
      expect(response.statusCode, 200);
      final body = await response.readAsString();
      expect(body, contains('/l/engine-tour'));
      expect(body, isNot(contains('Урок не найден')));
    });
  });

  group('/l/<slug>', () {
    test('a known lesson renders its iframe and the embed snippet', () async {
      final response = await get('/l/engine-tour');
      expect(response.statusCode, 200);
      final body = await response.readAsString();
      expect(body, contains('<iframe'));
      expect(body, contains('/app/?level='));
      expect(body, contains('https://lessons.pleion.dev/e/engine-tour'));
    });

    test('an unknown slug is a 404', () async {
      final response = await get('/l/does-not-exist');
      expect(response.statusCode, 404);
    });

    test('carries a defensive X-Frame-Options', () async {
      final response = await get('/l/engine-tour');
      expect(response.headers['x-frame-options'], 'SAMEORIGIN');
    });
  });

  group('/e/<slug>', () {
    test('a known lesson is a bare page with only the iframe', () async {
      final response = await get('/e/engine-tour');
      expect(response.statusCode, 200);
      final body = await response.readAsString();
      expect(body, contains('<iframe'));
      expect(body, contains('/app/?level='));
    });

    test('an unknown slug is a 404', () async {
      final response = await get('/e/does-not-exist');
      expect(response.statusCode, 404);
    });

    // The point of this route: absence, not a permissive value, is what lets
    // a third-party page frame it. A future edit that adds either header back
    // here breaks the embed silently, which is exactly what this test is for.
    // This only proves the app's own handler adds neither header — it calls
    // `buildHandler`'s `Handler` directly, never through `shelf_io`/`dart:io`.
    // It does NOT prove the deployed page is actually frameable: `dart:io`'s
    // `HttpServer` adds `x-frame-options: SAMEORIGIN` to every real response
    // regardless of what this handler returns, found by curling the deployed
    // service rather than by this test passing. The real guarantee is
    // `cloud/lessons/deploy/nginx-lessons.pleion.dev.conf`'s `location /e/`
    // block (`proxy_hide_header X-Frame-Options`), which no `dart test` run
    // exercises — see that file and `app.dart`'s own `_securityHeaders` doc.
    test(
      'carries no header that would stop a third party from framing it',
      () async {
        final response = await get('/e/engine-tour');
        expect(response.headers.containsKey('x-frame-options'), isFalse);
        expect(
          response.headers.containsKey('content-security-policy'),
          isFalse,
        );
      },
    );
  });

  group('unmatched routes', () {
    test(
      'answer 404 with the generic not-found page, not the lesson one',
      () async {
        final response = await get('/nothing-here');
        expect(response.statusCode, 404);
        final body = await response.readAsString();
        expect(body, contains('Страница не найдена'));
        expect(body, isNot(contains('Урок не найден')));
      },
    );
  });
}
