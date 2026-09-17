/// `/learn/modeler/*`, without a database: these routes carry no signed-in
/// state (see `learn_routes.dart`), so they are testable on their own, the
/// way the rest of the server's routes cannot be without Postgres.
library;

import 'dart:io';

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

    test('reads case 5 off disk and renders its Markdown', () {
      final cases = loadLearnCases();
      final case5 = cases.firstWhere((c) => c.slug == '05-borrowing-a-walk');
      expect(case5.title, contains('Borrowing a walk'));
      expect(case5.bodyHtml, contains('<h1 '));
      expect(
        case5.bodyHtml,
        contains(
          '/assets/learn/modeler/borrowing-a-walk/'
          '04-character-after-retarget.png',
        ),
      );
    });

    test('case 5 serves end to end through learnRoutes', () async {
      final handler = _mounted(learnRoutes());
      final response = await _get(
        handler,
        '/learn/modeler/05-borrowing-a-walk',
      );
      expect(response.statusCode, 200);
      final body = await response.readAsString();
      expect(body, contains('Borrowing a walk'));
      expect(
        body,
        contains(
          '/assets/learn/modeler/borrowing-a-walk/'
          '04-character-after-retarget.png',
        ),
      );
    });

    test('the mode tour is the first page, and shows every mode', () {
      final cases = loadLearnCases();
      // Sorted by file name, and it is `00-` — the tour is what somebody
      // reads before a case tells them to switch into a mode.
      expect(cases.first.slug, '00-every-mode');
      expect(cases.first.title, contains('Every mode'));

      // **A page that claims to cover every mode has to name every mode.**
      // Mutation: write the page once and let a mode be added later without
      // it. The tutorial then promises a tour and quietly misses whichever
      // mode arrived last, which is exactly what this row exists to stop.
      for (final String mode in <String>[
        'object',
        'mesh',
        'material',
        'sculpt',
        'retopo',
        'paint',
        'simulation',
        'animation',
        'render',
        'scene',
      ]) {
        expect(
          cases.first.bodyHtml,
          contains('/assets/learn/modeler/modes/$mode-mode.png'),
          reason: 'the tour has no picture of $mode mode',
        );
      }
      for (final String screen in <String>[
        'start-screen',
        'settings-screen',
        'shortcuts-screen',
      ]) {
        expect(
          cases.first.bodyHtml,
          contains('/assets/learn/modeler/modes/$screen.png'),
          reason: 'the tour has no picture of the $screen',
        );
      }
      // The dialogs a mode opens over itself. No case page shows any of
      // them, so if the tour drops one there is no picture of it anywhere
      // in the tutorial at all.
      for (final String dialog in <String>[
        'export-dialog',
        'gallery-dialog',
        'material-studio-dialog',
        'add-primitive-menu',
      ]) {
        expect(
          cases.first.bodyHtml,
          contains('/assets/learn/modeler/modes/$dialog.png'),
          reason: 'the tour has no picture of the $dialog',
        );
      }
    });

    test('and it serves end to end through learnRoutes', () async {
      final handler = _mounted(learnRoutes());
      final response = await _get(handler, '/learn/modeler/00-every-mode');
      expect(response.statusCode, 200);
      final body = await response.readAsString();
      expect(body, contains('Every mode'));
      expect(body, contains('/assets/learn/modeler/modes/sculpt-mode.png'));
    });

    test('reads case 6 off disk and renders its Markdown', () {
      final cases = loadLearnCases();
      final case6 = cases.firstWhere((c) => c.slug == '06-an-agent-beside-you');
      expect(case6.title, contains('An agent beside you'));
      expect(case6.bodyHtml, contains('<h1 '));
      expect(
        case6.bodyHtml,
        contains(
          '/assets/learn/modeler/an-agent-beside-you/02-final-material.png',
        ),
      );
    });

    test('case 6 serves end to end through learnRoutes', () async {
      final handler = _mounted(learnRoutes());
      final response = await _get(
        handler,
        '/learn/modeler/06-an-agent-beside-you',
      );
      expect(response.statusCode, 200);
      final body = await response.readAsString();
      expect(body, contains('An agent beside you'));
      expect(
        body,
        contains(
          '/assets/learn/modeler/an-agent-beside-you/02-final-material.png',
        ),
      );
    });
  });

  group('every picture a page points at is on disk', () {
    test('no page references an asset that is not there', () {
      // **What the checks above could not see.** Each of them asks whether a
      // page *mentions* a picture, which is the half that catches a tour
      // quietly dropping a mode. It says nothing about whether the file
      // exists — and four references in the tour pointed at pictures nobody
      // had taken, so the page rendered with four broken images and every
      // test passed.
      //
      // This walks the other way: from what the pages point at to what is on
      // disk. Nothing else can, because the pages are Markdown read at run
      // time and the pictures are written by a tool in a different package.
      final missing = <String>[];
      var checked = 0;
      for (final LearnCase page in loadLearnCases()) {
        for (final Match match in _assetLinks.allMatches(page.bodyHtml)) {
          final String url = match.group(1)!;
          if (_pendingPictures.contains(url)) continue;
          checked++;
          if (!File('web$url').existsSync()) missing.add('${page.slug}: $url');
        }
      }
      expect(missing, isEmpty);
      // A walk that visited nothing proves nothing, and this one can stop
      // visiting in two silent ways: the pages could stop carrying `src="…"`
      // at all if the Markdown renderer changed how it writes an image, and
      // this test would keep passing over an empty list for ever.
      expect(
        checked,
        greaterThan(30),
        reason: 'seven pages carry far more than thirty pictures between them',
      );
    });

    test('nothing on the pending list has quietly arrived', () {
      // The other side of the list, and the reason it is safe to have one:
      // `cross_backend_test`'s own `_provisional` does exactly this for a
      // scene waiting on a backend's reference set. A name left behind after
      // its picture lands is a check that has stopped checking, so finding
      // the file is a failure here rather than a quiet pass.
      for (final String url in _pendingPictures) {
        expect(
          File('web$url').existsSync(),
          isFalse,
          reason: '$url is on disk now — take it off the pending list',
        );
      }
    });
  });
}

/// `src="/assets/…"` in a rendered page, however the Markdown spelled it.
final RegExp _assetLinks = RegExp(r'src="(/assets/[^"]+)"');

/// Pictures the pages already point at and the screenshot pass has not taken.
///
/// **Named with a reason rather than left to render as a broken image.** These
/// four are the dialogs the tour gained after the last time the modeller's
/// golden screenshots were recorded: `tutorial_screenshots_test.dart` knows
/// how to shoot them, and doing it is one `--update-goldens` run followed by
/// `tool/publish_modeler_screenshots.dart`. Until that runs the page is
/// honestly incomplete, which is a different thing from silently wrong, and
/// the test above turns the difference into something a reader of this file
/// can see.
const Set<String> _pendingPictures = <String>{
  '/assets/learn/modeler/modes/export-dialog.png',
  '/assets/learn/modeler/modes/gallery-dialog.png',
  '/assets/learn/modeler/modes/material-studio-dialog.png',
  '/assets/learn/modeler/modes/add-primitive-menu.png',
};
