import 'dart:developer' as developer;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter3d_formats/flutter3d_formats.dart';

/// Which format [encodeModel]/[encodeModelInIsolate] writes.
enum ModelWriteFormat {
  /// `GltfWriter.writeGlb()` — one self-contained binary file.
  glb,

  /// `ObjWriter.write()`. The `.mtl` beside it, when the document has
  /// materials, is a second call this request does not carry: unlike every
  /// other format here, OBJ is two files, and asking for one still has to
  /// leave room for a caller that does not want the other.
  obj,

  /// `F3dWriter.write()`.
  f3d,

  /// `StlWriter.write()` — binary.
  stl,

  /// `StlWriter.writeAscii()`.
  stlAscii,
}

/// What to encode, and as which format — `fmt-13`'s own row, the write-side
/// mirror of `ModelLoadRequest`.
final class ModelWriteRequest {
  const ModelWriteRequest({
    required this.document,
    required this.format,
    this.name = 'model',
  });

  final ModelDocument document;
  final ModelWriteFormat format;

  /// The base name a writer that needs one is given — `ObjWriter`'s own
  /// `mtllib` line, `StlWriter`'s header text. Ignored by [ModelWriteFormat
  /// .glb] and [ModelWriteFormat.f3d], which carry nothing that names
  /// itself.
  final String name;
}

/// Encodes [request] in place — the same bytes [encodeModelInIsolate] would
/// produce, run on the calling isolate instead of handed off. What
/// [encodeModelInIsolate] falls back to on the web, and what a caller with
/// no isolate to spare can call directly.
Uint8List encodeModel(ModelWriteRequest request) => switch (request.format) {
  ModelWriteFormat.glb => GltfWriter(request.document).writeGlb(),
  ModelWriteFormat.obj => ObjWriter(request.document, name: request.name).write(),
  ModelWriteFormat.f3d => F3dWriter(request.document).write(),
  ModelWriteFormat.stl => StlWriter(request.document, name: request.name).write(),
  ModelWriteFormat.stlAscii => StlWriter(
    request.document,
    name: request.name,
  ).writeAscii(),
};

/// Encodes a model on a background isolate — the write-side mirror of
/// `decodeModelInIsolate` (`model_loader.dart`), for the same reason:
/// writing a real model costs tens of milliseconds, which is jank on the UI
/// isolate however fast the encoder is. See that function's own doc comment
/// for why the web falls back to running in place instead.
///
/// **The document travels whole, not by reference.** `Isolate.run` sends
/// [request] the same way `decodeModelInIsolate` sends its own request and
/// receives a [ModelDocument] back — plain data, typed lists included, with
/// nothing here holding a closure or a platform resource that would refuse
/// to cross.
Future<Uint8List> encodeModelInIsolate(ModelWriteRequest request) async {
  // The web has no isolates. `dart:isolate` compiles there as a stub, so
  // this fails at run time rather than build time if it were tried —
  // encoding in place is what the name promises not to do and the only
  // thing available.
  if (kIsWeb) return encodeModel(request);

  final task = developer.TimelineTask()
    ..start(
      'encodeModelInIsolate',
      arguments: <String, Object?>{'format': request.format.name},
    );
  try {
    return await Isolate.run(() => encodeModel(request));
  } finally {
    task.finish();
  }
}
