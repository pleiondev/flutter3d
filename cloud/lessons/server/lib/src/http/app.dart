/// Every address the service answers, and what it does with each.
///
/// Three routes and a static mount — the whole surface, because there is no
/// account to sign into and no form to submit. `/l/<slug>` is a page for a
/// person; `/e/<slug>` is the address a third-party page's own `<iframe>`
/// points at, and is the entire reason this service does not simply reuse
/// `cloud/server`'s pattern unchanged: that service's `_securityHeaders()`
/// sets `frame-ancestors 'none'` on every page on purpose, so that nobody can
/// frame the models catalogue — the opposite of `edu-02`'s own acceptance,
/// "embedded in a Stepik page and a GitHub README".
library;

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config.dart';
import '../lessons_registry.dart';
import 'pages.dart';
import 'static_files.dart';

Handler buildHandler(Config config) {
  final router = Router(notFoundHandler: _notFound)
    ..get('/health', (Request request) => Response.ok('ok'))
    ..get('/', (Request request) => _html(homePage()));

  // Nothing a Flutter build emits carries a hash in its name, so the viewer
  // is revalidated on every load — the same finding `cloud/server` wrote
  // down for the modeller's own build.
  if (config.viewerDirectory case final viewer?) {
    router.mount('/app/', staticDirectory(viewer, cacheControl: 'no-cache'));
  }

  router
    ..get('/l/<slug>', (Request request, String slug) async {
      final lesson = lessonBySlug(slug);
      if (lesson == null) return _lessonNotFound();
      return _html(lessonPage(lesson, baseUrl: config.baseUrl));
    })
    ..get('/e/<slug>', (Request request, String slug) async {
      final lesson = lessonBySlug(slug);
      if (lesson == null) return _lessonNotFound();
      return _html(embedPage(lesson));
    });

  return const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_securityHeaders())
      .addHandler(router.call);
}

Response _notFound(Request request) => _html(notFoundPage(), status: 404);

Response _lessonNotFound() => _html(lessonNotFoundPage(), status: 404);

Response _html(String body, {int status = 200}) => Response(
  status,
  body: body,
  headers: {'content-type': 'text/html; charset=utf-8'},
);

/// `/e/` gets none of `x-frame-options`/`frame-ancestors` added HERE: their
/// absence from this map is what should let a third-party page frame it —
/// setting either, even to a permissive value, is one edit away from
/// breaking the embed silently. `/l/` gets a defensive `SAMEORIGIN`: nobody
/// has asked to frame the landing page itself, and there is no reason it
/// should be embeddable if something later starts trying.
///
/// **Not sufficient on its own — found by curling the deployed service, not
/// by reading this file.** `dart:io`'s `HttpServer` sets `x-frame-options:
/// SAMEORIGIN` (and `x-xss-protection`, `x-content-type-options`) on every
/// response by default, at the transport layer, before `shelf` ever builds
/// the response object this function returns — omitting the key from
/// `shelf`'s own header map, which this function does correctly, does not
/// make it absent on the wire. `shelf` has no call that reaches into
/// `dart:io`'s pre-populated `HttpHeaders` to remove it. The actual fix for
/// `/e/` lives one layer out: `cloud/lessons/deploy/nginx-lessons.pleion.dev.conf`'s
/// `location /e/` block strips it with `proxy_hide_header`, since nginx sees
/// the finished upstream response and can drop a header this process cannot.
Middleware _securityHeaders() =>
    (Handler inner) => (Request request) async {
      final response = await inner(request);
      final isEmbed = request.url.path.startsWith('e/');
      return response.change(
        headers: {
          'x-content-type-options': 'nosniff',
          'referrer-policy': 'same-origin',
          if (!isEmbed) 'x-frame-options': 'SAMEORIGIN',
        },
      );
    };
