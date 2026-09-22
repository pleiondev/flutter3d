import 'dart:developer' as developer;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';

/// Whether this build has no isolates in it — see `model_loader.dart`'s own
/// copy of this constant for why it replaces `kIsWeb` here (mcp-03n).
const bool _isWeb = bool.fromEnvironment('dart.library.js_interop');

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
  stlAscii;

  /// The writer `flutter3d_formats` keeps for this format.
  ///
  /// [encodeModel] is that writer's first file, so the engine, the modeller
  /// and the MCP server write one format one way — they used to be three
  /// `switch`es with three different lists.
  ModelWriter get writer => switch (this) {
    ModelWriteFormat.glb => const GlbModelWriter(),
    ModelWriteFormat.obj => const ObjModelWriter(),
    ModelWriteFormat.f3d => const F3dModelWriter(),
    ModelWriteFormat.stl => const StlModelWriter(),
    ModelWriteFormat.stlAscii => const StlModelWriter(ascii: true),
  };
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
Uint8List encodeModel(ModelWriteRequest request) => request.format.writer
    .write(request.document, baseName: request.name)
    .files
    .first
    .bytes;

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
  if (_isWeb) return encodeModel(request);

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
