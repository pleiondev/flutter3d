/// Posting a save-back to the cabinet, on a desktop where a request is
/// exactly what `dart:io` makes of it.
///
/// **A real launch never reaches this build with a cabinet [id] to save
/// back to.** `CabinetLink.fromQuery` only turns on when the page this build
/// was loaded into named one, and the only page that does is the browser
/// build `cloud/server` embeds in an iframe. This half exists for the same
/// reason `fetch_model_io.dart` beside it does: one function per platform, so
/// a desktop build compiles, and — if it is ever pointed at a live query
/// string by hand, or run against a local `cloud/server` for a spike — POSTs
/// the same bytes and headers the browser build would.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'cabinet_save_outcome.dart';

/// The bytes at `/api/v1/models/<modelId>/source`, on this build's own
/// origin — `Uri.base`, the same base `screen/files.dart`'s own `_openLinked`
/// already resolves a cabinet link's `model` address against.
Future<CabinetSaveOutcome> postSourceToCabinet({
  required int modelId,
  required String csrf,
  required Uint8List bytes,
}) async {
  final client = HttpClient();
  try {
    final url = Uri.base.resolve('/api/v1/models/$modelId/source');
    final request = await client.postUrl(url);
    request.headers
      ..set('content-type', 'application/octet-stream')
      ..set('x-csrf', csrf)
      ..set('x-filename', Uri.encodeComponent('model.f3dproj'));
    request.add(bytes);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) {
      return CabinetSaveFailed(_errorFrom(body, response.statusCode));
    }
    return const CabinetSaveWritten();
  } catch (error) {
    return CabinetSaveFailed('$error');
  } finally {
    client.close();
  }
}

/// The server's own `{'error': '...'}` body, or a sentence built from the
/// status when the body is not that shape at all — a proxy's own error page,
/// say, rather than anything `cloud/server` wrote itself.
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
