/// N7's three endpoints, mounted under `/api/telemetry/`.
///
/// **No account, on purpose.** A run arrives with the consent it was sent
/// under and leaves with the key that deletes it; tying it to a person would
/// make anonymous telemetry a thing this server promises and could break.
library;

import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../telemetry/telemetry_service.dart';

Response _json(TelemetryAnswer answer) => Response(
  answer.status,
  body: jsonEncode(answer.body),
  headers: <String, String>{
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  },
);

Router telemetryRoutes(TelemetryService service) => Router()
  ..post('/runs', (Request request) async {
    // Read no further than the limit allows: a body that announces itself as
    // too large is refused before it is held in memory.
    final length = request.contentLength;
    if (length != null && length > service.maxBodyBytes) {
      return _json((
        status: 413,
        body: <String, Object?>{
          'says': 'a run is at most ${service.maxBodyBytes} bytes here',
        },
      ));
    }
    return _json(await service.accept(await request.readAsString()));
  })
  ..delete('/runs/<id>', (Request request, String id) async {
    final run = int.tryParse(id);
    final key = request.url.queryParameters['key'];
    if (run == null || key == null || key.isEmpty) {
      return _json((
        status: 400,
        body: <String, Object?>{
          'says': 'erase with /api/telemetry/runs/<run>?key=<eraseKey>',
        },
      ));
    }
    return _json(await service.erase(run, key));
  })
  ..get('/heatmap', (Request request) async {
    final query = request.url.queryParameters;
    return _json(await service.heatmap(query['level'], query['cell']));
  });
