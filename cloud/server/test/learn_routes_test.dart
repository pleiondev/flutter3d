/// `/learn/modeler/*`, without a database: these routes carry no signed-in
/// state (see `learn_routes.dart`), so they are testable on their own, the
/// way the rest of the server's routes cannot be without Postgres.
library;

import 'package:flutter3d_models/main.server.options.dart';
import 'package:flutter3d_models/src/content/learn_content.dart';
import 'package:flutter3d_models/src/http/learn_routes.dart';
import 'package:jaspr/server.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

Handler _mounted(Handler routes) =>
    (Router()..mount('/learn/modeler/', routes)).call;

Future<Response> _get(Handler handler, String path) async =>
    handler(Request('GET', Uri.parse('http://localhost$path')));

void main() {
  setUpAll(() => Jaspr.initializeApp(options: defaultServerOptions));

  group('learnRoutes with a fixture case', () {
    late Handler handler;

    setUp(() {
      handler = _mounted(
        learnRoutes(
          cases: const [
            LearnCase(
              slug: 'fixture-case',
              title: 'A fixture case',
              summary: 'Exists only for this test.',
              bodyHtml: '<p>Body content.</p>',
            ),
          ],
        ),
      );
    });

    test('the index lists the case and renders through Page', () async {
      final response = await _get(handler, '/learn/modeler/');
      expect(response.statusCode, 200);
      final body = await response.readAsString();
      expect(body, contains('Learn the modeler'));
      expect(body, contains('A fixture case'));
      expect(body, contains('Exists only for this test.'));
      // Came through the shared `Page` layout, not a bespoke shell.
      expect(body, contains('class="topbar"'));
      expect(body, contains('href="/learn/modeler/fixture-case"'));
    });

    test('a case slug renders its body through LearnPage', () async {
      final response = await _get(handler, '/learn/modeler/fixture-case');
      expect(response.statusCode, 200);
      final body = await response.readAsString();
      expect(body, contains('A fixture case'));
      expect(body, contains('<p>Body content.</p>'));
      expect(body, contains('class="topbar"'));
    });

    test('an unknown slug 404s instead of crashing', () async {
      final response = await _get(handler, '/learn/modeler/does-not-exist');
      expect(response.statusCode, 404);
      expect(await response.readAsString(), contains('Nothing here'));
    });
  });

  group('learnRoutes with no cases', () {
    test('the index still renders, saying nothing is published yet', () async {
      final handler = _mounted(learnRoutes(cases: const []));
      final response = await _get(handler, '/learn/modeler/');
      expect(response.statusCode, 200);
      expect(
        await response.readAsString(),
        contains('Nothing is published here yet'),
      );
    });
  });

  group('loadLearnCases against the real content directory', () {
    test('reads the placeholder case off disk and renders its Markdown', () {
      final cases = loadLearnCases();
      expect(cases, isNotEmpty);
      final placeholder = cases.firstWhere((c) => c.slug == '00-placeholder');
      expect(placeholder.title, contains('Placeholder'));
      expect(placeholder.bodyHtml, contains('<h1 '));
      expect(
        placeholder.bodyHtml,
        contains('/assets/learn/modeler/placeholder/01-hello.png'),
      );
    });

    test('an absent directory reads as no cases, not an error', () {
      expect(loadLearnCases(directory: 'content/nothing-here'), isEmpty);
    });

    test(
      'the placeholder case serves end to end through learnRoutes',
      () async {
        final handler = _mounted(learnRoutes());
        final response = await _get(handler, '/learn/modeler/00-placeholder');
        expect(response.statusCode, 200);
        final body = await response.readAsString();
        expect(body, contains('Placeholder'));
        expect(
          body,
          contains('/assets/learn/modeler/placeholder/01-hello.png'),
        );
      },
    );
  });
}
