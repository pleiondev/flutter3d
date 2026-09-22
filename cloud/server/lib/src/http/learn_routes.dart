/// The modeler tutorial's own routes: `/learn/modeler/` and its cases.
///
/// **No signed-in state.** Every other page calls `userOf(request)` to ask
/// what the top bar should offer, which reads the session table — the one
/// thing here that would need [Services] and, through it, a live database.
/// The tutorial is the same page for everyone who opens it, so its cases are
/// read once, from the Markdown on disk, with nothing per-request to look
/// up; that is also what lets its own test open every route with no database
/// at all, the way `dart test -x db` runs in CI.
library;

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../content/learn_content.dart';
import '../pages/learn_page.dart';
import '../pages/plain_pages.dart';
import 'render.dart';

/// Builds the `/` (index) and `/<slug>` routes meant to be mounted at
/// `/learn/modeler/`. [cases] defaults to [loadLearnCases]; a test hands in
/// its own list instead of touching disk.
Handler learnRoutes({List<LearnCase>? cases}) {
  final learnCases = cases ?? loadLearnCases();
  final router = Router(notFoundHandler: _notFoundCase)
    ..get(
      '/',
      (Request request) async => htmlPage(LearnIndexPage(cases: learnCases)),
    )
    ..get('/<slug>', (Request request, String slug) async {
      for (final one in learnCases) {
        if (one.slug == slug) return htmlPage(LearnPage(learnCase: one));
      }
      return _notFoundCase(request);
    });
  return router.call;
}

Future<Response> _notFoundCase(Request request) async =>
    htmlPage(const NotFoundPage(), status: 404);
