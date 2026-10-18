/// N10's routes, mounted under `/api/`: what `RunService` in `flutter3d_sim`
/// calls from a base of `https://<host>/api/`, and the moderation routes for
/// whoever runs the server.
///
/// **No session and no cookie, the same as telemetry.** A share is anonymous,
/// so there is no account for a forged form to ride on; the moderation routes
/// are a bearer token a tool sends, never a cookie a browser would send on its
/// own.
library;

import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../shares/share_service.dart';
import 'request.dart';

/// The longest report or decision read: both are a sentence.
const int _smallBodyBytes = 4096;

Response _json(ShareAnswer answer) => Response(
  answer.status,
  body: jsonEncode(answer.body),
  headers: <String, String>{
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  },
);

/// The body as text, or null when it is over [limit] — counted as it arrives,
/// so a body that never says how long it is is still refused before it is
/// held whole.
Future<String?> _text(Request request, int limit) async {
  final bytes = await readBody(request, limit: limit);
  return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
}

/// Unmatched paths fall through to the routes mounted after this, which is
/// why the router keeps shelf_router's own not-found: `/api/v1/models` is
/// under the same prefix.
Router shareRoutes(ShareService service) => Router()
  ..post('/v1/shares', (Request request) async {
    final body = await _text(request, service.maxBodyBytes);
    if (body == null) return _json(tooLarge(service.maxBodyBytes));
    return _json(await service.share(body));
  })
  ..get(
    '/v1/shares/<code>',
    (Request request, String code) async => _json(await service.open(code)),
  )
  ..post('/v1/shares/<code>/reports', (Request request, String code) async {
    final body = await _text(request, _smallBodyBytes);
    if (body == null) return _json(tooLarge(_smallBodyBytes));
    return _json(await service.report(code, body));
  })
  ..get(
    '/v1/moderation/queue',
    (Request request) async =>
        _json(await service.queue(request.headers['authorization'])),
  )
  ..get(
    '/v1/moderation/shares/<code>',
    (Request request, String code) async =>
        _json(await service.inspect(request.headers['authorization'], code)),
  )
  ..post('/v1/moderation/shares/<code>', (Request request, String code) async {
    final body = await _text(request, _smallBodyBytes);
    if (body == null) return _json(tooLarge(_smallBodyBytes));
    return _json(
      await service.decide(request.headers['authorization'], code, body),
    );
  });
