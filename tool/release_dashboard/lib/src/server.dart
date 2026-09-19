/// The page and the stream that keeps it current.
///
/// **Bound to the loopback address and to nothing else.** The routes that start
/// scripts on this machine must not be reachable from another one, and a
/// dashboard has no business being a network service.
///
/// **A browser tab can still send this server a request.** Any page open in the
/// same browser may POST to `127.0.0.1`, and one that did would be starting the
/// full pipeline on somebody else's say-so. So a POST is refused unless it
/// carries a header a cross-site request cannot add without a preflight this
/// server never answers, and a `Host` that is this server's own, which is what a
/// DNS-rebinding page does not have.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dashboard.dart';

/// Serves [dashboard] on [port] (0 for any free one) and returns the server.
Future<HttpServer> serveDashboard(
  Dashboard dashboard, {
  required File page,
  int port = 8765,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  final clients = <HttpResponse>[];

  final sub = dashboard.updates.listen((String state) {
    final frame = 'event: state\ndata: $state\n\n';
    for (final client in List<HttpResponse>.of(clients)) {
      try {
        client.write(frame);
      } on Object {
        clients.remove(client);
      }
    }
  });

  bool ownHost(HttpRequest request) {
    final host = request.headers.host;
    return host == '127.0.0.1' || host == 'localhost';
  }

  final listening = server.listen((HttpRequest request) async {
    final response = request.response;
    try {
      if (!ownHost(request)) {
        response.statusCode = HttpStatus.forbidden;
        await response.close();
        return;
      }

      final path = request.uri.path;
      switch ((request.method, path)) {
        case ('GET', '/'):
          response.headers.contentType = ContentType.html;
          response.headers.set('cache-control', 'no-store');
          response.write(page.readAsStringSync());
          await response.close();

        case ('GET', '/api/state'):
          response.headers.contentType = ContentType.json;
          response.headers.set('cache-control', 'no-store');
          response.write(jsonEncode(dashboard.state()));
          await response.close();

        case ('GET', '/events'):
          response.headers.contentType = ContentType(
            'text',
            'event-stream',
            charset: 'utf-8',
          );
          response.headers.set('cache-control', 'no-store');
          response.headers.set('x-accel-buffering', 'no');
          response.bufferOutput = false;
          response.write('retry: 2000\n\n');
          // The first frame is the state as it is now, so a page that opens or
          // reconnects is never blank while it waits for something to change.
          response.write(
            'event: state\ndata: ${jsonEncode(dashboard.state())}\n\n',
          );
          clients.add(response);
          unawaited(
            response.done.then<void>(
              (_) => clients.remove(response),
              onError: (Object _) => clients.remove(response),
            ),
          );

        case ('POST', _) when path.startsWith('/api/run/'):
          if (request.headers.value('x-dashboard') != '1') {
            response.statusCode = HttpStatus.forbidden;
            await response.close();
            return;
          }
          final id = path.substring('/api/run/'.length);
          final known = dashboard.gates.any((gate) => gate.id == id);
          final queued = dashboard.runGate(id);
          response.statusCode = !known
              ? HttpStatus.notFound
              : queued
              ? HttpStatus.accepted
              : HttpStatus.conflict;
          await response.close();

        case ('POST', '/api/refresh'):
          if (request.headers.value('x-dashboard') != '1') {
            response.statusCode = HttpStatus.forbidden;
            await response.close();
            return;
          }
          unawaited(dashboard.refreshLocal());
          unawaited(dashboard.refreshRemote());
          response.statusCode = HttpStatus.accepted;
          await response.close();

        default:
          response.statusCode = HttpStatus.notFound;
          await response.close();
      }
    } on Object {
      // A client that went away mid-write is not an event worth stopping for.
      try {
        await response.close();
      } on Object {
        // Nothing left to tell it.
      }
    }
  });

  listening.onDone(sub.cancel);
  return server;
}
