import 'dart:developer' as developer;

import 'package:flutter3d_core/formats.dart';

import '../platform/decode_worker_web.dart';

/// [request] decoded on the browser's decode worker where one is running
/// (`WebDecodeWorker`), its file read here and its siblings read here when
/// the worker asks for them; in place where there is none, or where the
/// worker sent it back, as every web decode was before 1.0.
Future<ModelDocument> decodeOnIsolate(
  ModelLoadRequest request,
  developer.TimelineTask task,
  AssetRead read,
) async {
  task.instant('read');
  // Read here, where [read]'s listener lives; only the bytes cross.
  final primary = await read.readFrom(request.source);
  task.instant('decode');
  return await decodeModelOnWorker(request, primary) ??
      await decodeModelBytes(request, primary, request.source.resolveUri);
}
