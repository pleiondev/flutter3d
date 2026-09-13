/// A component, as the response a browser receives.
library;

import 'package:jaspr/server.dart';

/// Renders [page] and answers with it.
///
/// `no-store`, because almost every page here is somebody's own: a cabinet
/// kept by a shared cache would be a cabinet shown to the next person.
Future<Response> htmlPage(Component page, {int status = 200}) async {
  // A standalone render has no request and sets no status of its own, so only
  // the bytes are taken; the status is the caller's, who knows why it failed.
  final rendered = await renderComponent(page);
  return Response(
    status,
    body: rendered.body,
    headers: {
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'no-store',
    },
  );
}
