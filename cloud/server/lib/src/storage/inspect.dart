/// Deciding whether an upload is a model, before it is stored.
///
/// **Read by the decoders the editor uses, not by a list of extensions.** A file
/// called `chair.glb` is whatever its bytes say, and the only way to know that
/// a model will open in the viewer is to open it. So every upload is decoded
/// here once; what does not decode is refused with the decoder's own sentence,
/// and the triangle count shown on the card is the one the decoder counted.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

/// What an accepted file is, as stored in `models.source_format`.
enum SourceFormat {
  glb('glb', 'model/gltf-binary', '.glb'),
  gltf('gltf', 'model/gltf+json', '.gltf'),
  obj('obj', 'model/obj', '.obj'),
  f3d('f3d', 'application/octet-stream', '.f3d'),
  project('f3dproj', 'application/octet-stream', '.f3dproj');

  const SourceFormat(this.column, this.contentType, this.suffix);

  final String column;
  final String contentType;
  final String suffix;

  static SourceFormat? of(String column) =>
      values.where((f) => f.column == column).firstOrNull;
}

sealed class Inspection {
  const Inspection();
}

final class Accepted extends Inspection {
  const Accepted(this.format, this.triangleCount);

  final SourceFormat format;
  final int triangleCount;
}

final class Rejected extends Inspection {
  const Rejected(this.because);

  final String because;
}

/// Reads [bytes] as a model and says whether to keep it.
///
/// **In its own isolate, with a deadline.** A decoder handed a hostile or
/// merely enormous file can spend seconds on it, and on the request isolate
/// those are seconds in which nobody else gets a page. The deadline stops the
/// wait rather than the work — an isolate cannot be interrupted mid-computation
/// — but the answer goes back to the person who uploaded, and the event loop
/// never stopped turning.
Future<Inspection> inspectUpload(
  Uint8List bytes, {
  required String fileName,
  Duration deadline = const Duration(seconds: 30),
}) async {
  if (bytes.isEmpty) return Rejected('$fileName is empty.');
  try {
    final result = await Isolate.run(
      () => _inspect(bytes, fileName),
    ).timeout(deadline);
    return switch (result) {
      (format: final format?, triangles: final triangles, refusal: null) =>
        Accepted(format, triangles),
      (refusal: final refusal?, format: _, triangles: _) => Rejected(refusal),
      _ => Rejected('$fileName could not be read.'),
    };
  } on TimeoutException {
    return Rejected(
      'Reading $fileName took longer than ${deadline.inSeconds} seconds, so it '
      'was not stored.',
    );
  }
}

/// A title a person would give the model, from the name of its file.
///
/// `old_oak-chair.v2.glb` becomes `old oak chair.v2`: only the last suffix is a
/// format, and the rest is what somebody chose to call it.
String titleFromFileName(String fileName) {
  final base = fileName.split(RegExp(r'[/\\]')).last;
  final dot = base.lastIndexOf('.');
  final stem = (dot > 0 ? base.substring(0, dot) : base)
      .replaceAll(RegExp('[_-]+'), ' ')
      .trim();
  if (stem.isEmpty) return 'Untitled model';
  return stem.length > 80 ? stem.substring(0, 80).trim() : stem;
}

typedef _Result = ({SourceFormat? format, int triangles, String? refusal});

Future<_Result> _inspect(Uint8List bytes, String name) async {
  if (isProjectFile(bytes)) {
    return switch (readProject(bytes)) {
      ProjectOpened(:final project) => (
        format: SourceFormat.project,
        triangles: project.triangleCount,
        refusal: null,
      ),
      ProjectRefused(:final because) => (
        format: null,
        triangles: 0,
        refusal: because,
      ),
    };
  }

  final format = _sniff(bytes);
  try {
    final document = await decodeModelBytes(
      ModelLoadRequest(
        source: _Upload(name, bytes),
        // Named from the bytes rather than left to the suffix, so that a GLB
        // renamed to `.obj` is read as what it is instead of failing as what
        // its name claims.
        format: switch (format) {
          SourceFormat.glb || SourceFormat.gltf => ModelFormat.gltf,
          SourceFormat.obj => ModelFormat.obj,
          SourceFormat.f3d || SourceFormat.project => ModelFormat.f3d,
        },
      ),
      bytes,
      _embeddedOnly,
    );
    // The OBJ reader accepts any text and answers with an empty document, so a
    // photograph renamed to `.obj` decodes without complaint. Empty is a
    // refusal here for the same reason the modeller refuses to open it.
    if (document.surfaces.isEmpty && document.nodes.isEmpty) {
      return (
        format: null,
        triangles: 0,
        refusal:
            'There is nothing in $name that could be read as a model: no '
            'meshes and no nodes came out of it.',
      );
    }
    return (format: format, triangles: document.triangleCount, refusal: null);
  } catch (error) {
    return (
      format: null,
      triangles: 0,
      refusal: '$name could not be read: $error',
    );
  }
}

SourceFormat _sniff(Uint8List bytes) {
  if (isF3dFile(bytes)) return SourceFormat.f3d;
  if (bytes.length >= 4 &&
      ByteData.sublistView(bytes).getUint32(0, Endian.little) == 0x46546C67) {
    return SourceFormat.glb;
  }
  // A `.gltf` is JSON, so its first meaningful byte is a brace. Whitespace and
  // a UTF-8 byte order mark may come before it.
  const skipped = {0x20, 0x09, 0x0A, 0x0D, 0xEF, 0xBB, 0xBF};
  final first = bytes.take(64).where((b) => !skipped.contains(b)).firstOrNull;
  return first == 0x7B ? SourceFormat.gltf : SourceFormat.obj;
}

/// Only what is inside the file itself.
///
/// A `.gltf` that points at a `.bin` beside it cannot be uploaded as one file,
/// and guessing would store a model that opens without its geometry.
Future<Uint8List> _embeddedOnly(AssetRequest request) async {
  if (request.uri.startsWith('data:')) return decodeDataUri(request.uri);
  throw StateError(
    'it refers to "${request.uri}", a separate file. Upload a .glb, or a .gltf '
    'with its buffers and images embedded.',
  );
}

final class _Upload extends AssetSource {
  const _Upload(this._name, this._bytes);

  final String _name;
  final Uint8List _bytes;

  @override
  String get key => 'upload:$_name';

  @override
  Future<Uint8List> read() async => _bytes;

  @override
  AssetUriResolver get resolveUri => _embeddedOnly;
}
