/// Posting a save-back to the cabinet, from the browser —
/// `web.window.fetch` carrying the same origin's cookies, the way
/// `fetch_model_web.dart`'s own `fetchModel` already reads with them.
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'cabinet_save_outcome.dart';

/// The bytes at `/api/v1/models/<modelId>/source`, on this build's own
/// origin. `credentials: 'same-origin'` is what sends the session cookie a
/// signed-in cabinet owner already holds; [csrf] is a page-supplied value
/// this build has no other way to reach, since the cookie
/// `cloud/server`'s own `scriptIsOurs` checks it against is `HttpOnly` and
/// unreadable from here — see `CabinetLink`'s own doc comment.
Future<CabinetSaveOutcome> postSourceToCabinet({
  required int modelId,
  required String csrf,
  required Uint8List bytes,
}) async {
  try {
    final headers = web.Headers()
      ..set('content-type', 'application/octet-stream')
      ..set('x-csrf', csrf)
      ..set('x-filename', Uri.encodeComponent('model.f3dproj'));
    final url = Uri.base.resolve('/api/v1/models/$modelId/source').toString();
    final response = await web.window
        .fetch(
          url.toJS,
          web.RequestInit(
            method: 'POST',
            credentials: 'same-origin',
            headers: headers,
            body: bytes.toJS,
          ),
        )
        .toDart;
    if (!response.ok) {
      final text = (await response.text().toDart).toDart;
      return CabinetSaveFailed(_errorFrom(text, response.status));
    }
    return const CabinetSaveWritten();
  } catch (error) {
    return CabinetSaveFailed('$error');
  }
}

/// See `cabinet_save_io.dart`'s own `_errorFrom` — the same fallback, for the
/// same reason.
String _errorFrom(String body, int status) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map && decoded['error'] is String) {
      return decoded['error'] as String;
    }
  } catch (_) {
    // Not JSON at all — falls through to the status-only sentence below.
  }
  return 'the server answered $status';
}
