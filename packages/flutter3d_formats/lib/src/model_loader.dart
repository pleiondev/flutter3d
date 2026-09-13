import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter3d_geometry/flutter3d_geometry.dart';

import 'asset_source.dart';
import 'f3d/f3d.dart';
import 'gltf/gltf.dart';
import 'obj/obj.dart';
import 'stl/stl.dart';

// **This is the half of loading a model that needs nothing from Flutter**, and
// the other half is `flutter3d`'s `model_loader.dart`: `decodeModelInIsolate`,
// which reads the asset bundle, spawns an isolate and answers `kIsWeb`. What is
// here decodes bytes that somebody else has already read, which is what a
// modeller, a server and a test all want and none of them wanted an SDK for.
export 'asset_source.dart';

/// Which decoder to use.
enum ModelFormat {
  /// Pick from the file extension, falling back to sniffing the bytes.
  auto,
  gltf,
  obj,

  /// The engine's own container, produced by `dart run flutter3d_build:convert`.
  f3d,

  stl,
}

/// A decoder for a format the engine does not ship.
///
/// **The plugin boundary for reading, and it is one interface wide.** The engine
/// knows glTF, OBJ and its own container; anything else — a studio's internal
/// format, a compressed variant, a format that has not been invented yet —
/// arrives as one of these and needs no change to this package.
///
/// Consulted before the built-in decoders, so an application can also *replace*
/// one: a project with its own glTF reader gets its own glTF reader.
///
/// **Implementations must be sendable**, and that is not a formality — see
/// [ModelLoadRequest.decoders] for the isolate that makes it one.
abstract interface class ModelDecoder {
  /// Whether this decoder wants the file. [fileName] may be empty; [bytes] is
  /// the whole file, so a decoder with no useful suffix can sniff its magic.
  bool handles(String fileName, Uint8List bytes);

  /// Reads [bytes] into a document.
  ///
  /// [resolveUri] fetches a sibling file — a `.gltf`'s buffer, an `.obj`'s
  /// material library — and is the only way to reach the file system from here:
  /// this runs on a background isolate that has none.
  Future<ModelDocument> decode(
    Uint8List bytes,
    ModelLoadRequest request,
    AssetUriResolver resolveUri,
  );
}

/// Everything a decode needs, in one sendable object.
final class ModelLoadRequest {
  const ModelLoadRequest({
    required this.source,
    this.format = ModelFormat.auto,
    this.layout = VertexLayout.standard,
    this.objNormals = ObjNormals.smooth,
    this.stlNormals = StlNormals.fromFile,
    this.decoders = const <ModelDecoder>[],
  });

  final AssetSource source;
  final ModelFormat format;
  final VertexLayout layout;
  final ObjNormals objNormals;
  final StlNormals stlNormals;

  /// An application's own decoders, tried in order before the built-in ones.
  ///
  /// **Carried on the request rather than kept in a registry, and the isolate is
  /// why.** Decoding runs on a background isolate, and statics are not shared
  /// across isolates in Dart: a registry filled at startup in the main isolate
  /// is empty in the one that does the reading. It would work in a test that
  /// decoded on the main isolate and fail in the application, which is the worst
  /// shape a bug can have.
  ///
  /// Travelling with the request means they are sent, so each must be sendable:
  /// a plain object holding plain data. A decoder that closes over a texture, a
  /// device or a port cannot cross and will say so at run time.
  final List<ModelDecoder> decoders;
}

/// Decodes a model on the calling isolate.
///
/// Exposed for tests and for callers that already run off the UI thread; an
/// application drawing a frame should prefer `decodeModelInIsolate`, which is
/// `flutter3d`'s and takes the read off the UI thread as well.
Future<ModelDocument> decodeModel(ModelLoadRequest request) async {
  final bytes = await request.source.read();
  return decodeModelBytes(request, bytes, request.source.resolveUri);
}

/// Decodes already-read bytes with an explicit resolver.
///
/// The seam the isolate path uses: bytes and a resolver are both sendable-friendly,
/// while an [AssetSource] that reaches for the asset bundle is not usable off the UI
/// isolate.
Future<ModelDocument> decodeModelBytes(
  ModelLoadRequest request,
  Uint8List bytes,
  AssetUriResolver resolveUri,
) {
  // An application's own decoders first, so it can add a format and replace one.
  // Asked before the format is resolved at all: a decoder that recognises its
  // own file is a better authority than a suffix table this package wrote.
  for (final decoder in request.decoders) {
    if (!decoder.handles(request.source.fileName.toLowerCase(), bytes)) {
      continue;
    }
    final task = developer.TimelineTask()
      ..start(
        'decode ${decoder.runtimeType}',
        arguments: <String, Object?>{'bytes': bytes.length},
      );
    return decoder.decode(bytes, request, resolveUri).whenComplete(task.finish);
  }

  final format = _resolveFormat(request, bytes);
  // Named after the format so the background isolate's span says which decoder
  // the time went into, rather than just "decode".
  final task = developer.TimelineTask()
    ..start(
      'decode ${format.name}',
      arguments: <String, Object?>{'bytes': bytes.length},
    );

  return builtInModelDecoder(
    format,
    request,
  ).decode(bytes, request, resolveUri).whenComplete(task.finish);
}

/// The decoder this package ships for [format], configured from [request].
///
/// **The built-in readers are [ModelDecoder]s too**, and this is the one place
/// they are made: [decodeModelBytes] reaches them here after an application's
/// own decoders have passed, and anything else that wants "what this package
/// would read this with" — a converter, a drop target — asks the same
/// function rather than keeping a `switch` of its own that could fall behind.
/// An application that wants a built-in reader configured differently puts
/// one in [ModelLoadRequest.decoders], where it is asked first.
ModelDecoder builtInModelDecoder(ModelFormat format, ModelLoadRequest request) =>
    switch (format) {
      // Synchronous and essentially free: the header is read and everything
      // else becomes a view over these bytes when it is asked for.
      ModelFormat.f3d => const F3dDecoder(),
      ModelFormat.obj => ObjLoader(
        layout: request.layout,
        normals: request.objNormals,
      ),
      ModelFormat.stl => StlLoader(
        layout: request.layout,
        normals: request.stlNormals,
      ),
      ModelFormat.gltf || ModelFormat.auto => GltfLoader(layout: request.layout),
    };

/// Every file suffix a built-in reader answers to, and which reader.
///
/// Read by [recognizedModelFormat] and by `flutter3d_build`'s converter, which
/// walks a directory for the files it can convert — two readers of one list,
/// where there used to be two lists.
const Map<String, ModelFormat> builtInModelExtensions = <String, ModelFormat>{
  '.f3d': ModelFormat.f3d,
  '.obj': ModelFormat.obj,
  '.stl': ModelFormat.stl,
  '.gltf': ModelFormat.gltf,
  '.glb': ModelFormat.gltf,
};

/// Whether a file called [fileName] is one [decodeModelBytes] would read on
/// its name alone — a built-in suffix, or one of [decoders] claiming it.
///
/// **By name, with no bytes**, because the callers are the ones that have not
/// read the file yet or should not trust what it starts with: a drop target
/// deciding whether to try at all, and a converter walking a directory. A
/// decoder that recognises its format only by magic answers false here, which
/// is the honest answer to a question asked without the bytes.
bool canDecodeFileName(
  String fileName, {
  List<ModelDecoder> decoders = const <ModelDecoder>[],
}) {
  if (recognizedModelFormat(fileName) != null) return true;
  final name = fileName.toLowerCase();
  final nothing = Uint8List(0);
  return decoders.any((ModelDecoder decoder) => decoder.handles(name, nothing));
}

/// Chooses a decoder from the file name, then from the bytes.
///
/// Extension first because it is what the author intended; sniffing is the
/// fallback for names that carry no useful suffix.
ModelFormat _resolveFormat(ModelLoadRequest request, Uint8List bytes) {
  if (request.format != ModelFormat.auto) return request.format;
  return recognizedModelFormat(request.source.fileName) ??
      sniffModelFormat(bytes);
}

/// The format [fileName]'s own extension names, or null when it names none
/// of the four this package reads.
///
/// **Read off [builtInModelExtensions], the one place this package's own list
/// of extensions is written down.** `_resolveFormat` reads it for the same
/// reason a drop target does — `ui-31n`'s own "drop неизвестного расширения":
/// a caller deciding whether a dropped file is one this application can open
/// needs the same answer `decodeModel` itself would give, not a second list
/// of suffixes kept beside this one that could name a fifth format this
/// package still could not read. A caller with decoders of its own asks
/// [canDecodeFileName] instead.
ModelFormat? recognizedModelFormat(String fileName) {
  final name = fileName.toLowerCase();
  for (final MapEntry<String, ModelFormat> each
      in builtInModelExtensions.entries) {
    if (name.endsWith(each.key)) return each.value;
  }
  return null;
}

/// Guesses a format from the leading bytes.
ModelFormat sniffModelFormat(Uint8List bytes) {
  if (isF3dFile(bytes)) return ModelFormat.f3d;

  // 'glTF' little-endian magic marks a GLB container.
  if (bytes.length >= 4 &&
      bytes[0] == 0x67 &&
      bytes[1] == 0x6C &&
      bytes[2] == 0x54 &&
      bytes[3] == 0x46) {
    return ModelFormat.gltf;
  }

  // Skip whitespace, then a '{' means JSON, i.e. a .gltf document.
  for (var i = 0; i < bytes.length && i < 64; i++) {
    final byte = bytes[i];
    if (byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D) continue;
    if (byte == 0x7B) return ModelFormat.gltf;
    break;
  }

  // Checked ahead of the OBJ default, and after everything above: a binary
  // STL's own size is decisive regardless of what its header text says (see
  // `isBinaryStl`), and an ASCII one is the one format here that looks like
  // plain text the way OBJ does, so it needs its own check rather than
  // falling into that default by looking similar enough.
  if (isBinaryStl(bytes) || looksLikeAsciiStl(bytes)) return ModelFormat.stl;

  return ModelFormat.obj;
}
