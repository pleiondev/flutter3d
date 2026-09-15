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
    test('reads case 1 off disk and renders its Markdown', () {
      final cases = loadLearnCases();
      expect(cases, isNotEmpty);
      final case1 = cases.firstWhere((c) => c.slug == '01-prop-from-a-scan');
      expect(case1.title, contains('A prop from a scan'));
      expect(case1.bodyHtml, contains('<h1 '));
      expect(
        case1.bodyHtml,
        contains(
          '/assets/learn/modeler/prop-from-a-scan/06-final-material.png',
        ),
      );
    });

    test('an absent directory reads as no cases, not an error', () {
      expect(loadLearnCases(directory: 'content/nothing-here'), isEmpty);
    });

    test('case 1 serves end to end through learnRoutes', () async {
      final handler = _mounted(learnRoutes());
      final response = await _get(
        handler,
        '/learn/modeler/01-prop-from-a-scan',
      );
      expect(response.statusCode, 200);
      final body = await response.readAsString();
      expect(body, contains('A prop from a scan'));
      expect(
        body,
        contains('/assets/learn/modeler/prop-from-a-scan/05-imported-raw.png'),
      );
    });

    test('reads case 2 off disk and renders its Markdown', () {
      final cases = loadLearnCases();
      final case2 = cases.firstWhere((c) => c.slug == '02-vase-from-a-profile');
      expect(case2.title, contains('A vase from a profile'));
      expect(case2.bodyHtml, contains('<h1 '));
      expect(
        case2.bodyHtml,
        contains('/assets/learn/modeler/vase-from-a-profile/05-vase-mesh.png'),
      );
    });

    test('case 2 serves end to end through learnRoutes', () async {
      final handler = _mounted(learnRoutes());
      final response = await _get(
        handler,
        '/learn/modeler/02-vase-from-a-profile',
      );
      expect(response.statusCode, 200);
      final body = await response.readAsString();
      expect(body, contains('A vase from a profile'));
      expect(
        body,
        contains(
          '/assets/learn/modeler/vase-from-a-profile/06-vase-modifiers-preview.png',
        ),
      );
    });

    test('reads case 3 off disk and renders its Markdown', () {
      final cases = loadLearnCases();
      final case3 = cases.firstWhere((c) => c.slug == '03-a-lit-corner');
      expect(case3.title, contains('A lit corner'));
      expect(case3.bodyHtml, contains('<h1 '));
      expect(
        case3.bodyHtml,
        contains('/assets/learn/modeler/a-lit-corner/03-lit-corner.png'),
      );
    });

    test('case 3 serves end to end through learnRoutes', () async {
      final handler = _mounted(learnRoutes());
      final response = await _get(handler, '/learn/modeler/03-a-lit-corner');
      expect(response.statusCode, 200);
      final body = await response.readAsString();
      expect(body, contains('A lit corner'));
      expect(
        body,
        contains('/assets/learn/modeler/a-lit-corner/03-lit-corner.png'),
      );
    });

    test('reads case 4 off disk and renders its Markdown', () {
      final cases = loadLearnCases();
      final case4 = cases.firstWhere(
        (c) => c.slug == '04-character-from-a-bare-mesh',
      );
      expect(case4.title, contains('A character from a bare mesh'));
      expect(case4.bodyHtml, contains('<h1 '));
      expect(
        case4.bodyHtml,
        contains(
          '/assets/learn/modeler/character-from-a-bare-mesh/'
          '07-character-real-geometry.png',
        ),
      );
    });

    test('case 4 serves end to end through learnRoutes', () async {
      final handler = _mounted(learnRoutes());
      final response = await _get(
        handler,
        '/learn/modeler/04-character-from-a-bare-mesh',
      );
      expect(response.statusCode, 200);
      final body = await response.readAsString();
      expect(body, contains('A character from a bare mesh'));
      expect(
        body,
        contains(
          '/assets/learn/modeler/character-from-a-bare-mesh/'
          '07-character-real-geometry.png',
        ),
      );
    });
  });
}
