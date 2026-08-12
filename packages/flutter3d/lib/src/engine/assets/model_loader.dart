import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../geometry/geometry.dart';
import 'f3d/f3d.dart';
import 'gltf/gltf.dart';
import 'obj/obj.dart';

/// Where a model and its sibling files live.
///
/// A sendable *description* rather than a resolver closure, because that is what
/// crosses an isolate boundary: the background isolate reconstructs the resolver
/// from this instead of receiving a callback that closes over the asset bundle.
sealed class AssetSource {
  const AssetSource();

  /// Stable identity, used as the cache key.
  String get key;

  /// The model file itself.
  Future<Uint8List> read();

  /// Resolves files referenced from inside the model, relative to its directory.
  AssetUriResolver get resolveUri;

  /// Everything after the last path separator.
  String get fileName {
    final path = key;
    final slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }
}

/// A model in the Flutter asset bundle.
///
/// Reading the bundle from a background isolate needs the platform channel to be
/// wired up there; [decodeModelInIsolate] passes the root isolate token that makes
/// that possible.
final class BundleAssetSource extends AssetSource {
  const BundleAssetSource(this.assetPath);

  final String assetPath;

  @override
  String get key => 'bundle:$assetPath';

  @override
  Future<Uint8List> read() async {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  @override
  AssetUriResolver get resolveUri {
    final slash = assetPath.lastIndexOf('/');
    final directory = slash < 0 ? '' : assetPath.substring(0, slash);
    return (uri) async {
      if (uri.startsWith('data:')) return decodeDataUri(uri);
      final data = await rootBundle.load('$directory/${_safeRelative(uri)}');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    };
  }
}


/// A model on the filesystem. Unavailable on web, which is why it is a separate
/// source rather than a flag.
final class FileAssetSource extends AssetSource {
  const FileAssetSource(this.path);

  final String path;

  @override
  String get key => 'file:$path';

  @override
  Future<Uint8List> read() => File(path).readAsBytes();

  @override
  AssetUriResolver get resolveUri {
    final directory = File(path).parent.path;
    return (uri) async {
      if (uri.startsWith('data:')) return decodeDataUri(uri);
      final relative = _safeRelative(uri);
      final file = File('$directory/$relative');
      if (!await file.exists()) {
        throw FileSystemException('Referenced file not found', file.path);
      }
      return file.readAsBytes();
    };
  }
}

/// A reference inside a model is always relative to the model. An absolute path or
/// a `..` segment means the file is reaching outside its directory, which is worth
/// refusing rather than resolving.
String _safeRelative(String uri) {
  final relative = Uri.decodeComponent(uri);
  if (relative.startsWith('/') ||
      relative.startsWith(r'\') ||
      relative.contains('://') ||
      relative.split(RegExp(r'[/\\]')).contains('..')) {
    throw ArgumentError('Refusing to load "$uri": it escapes the asset directory.');
  }
  return relative;
}

/// Which decoder to use.
enum ModelFormat {
  /// Pick from the file extension, falling back to sniffing the bytes.
  auto,
  gltf,
  obj,

  /// The engine's own container, produced by `tool/convert_asset.dart`.
  f3d,
}

/// Everything a decode needs, in one sendable object.
final class ModelLoadRequest {
  const ModelLoadRequest({
    required this.source,
    this.format = ModelFormat.auto,
    this.layout = VertexLayout.standard,
    this.objNormals = ObjNormals.smooth,
  });

  final AssetSource source;
  final ModelFormat format;
  final VertexLayout layout;
  final ObjNormals objNormals;
}

/// Decodes a model on a background isolate.
///
/// The asset layer was kept free of the graphics backend, `dart:ui` and direct file access
/// precisely so this would be possible: the decoders are pure Dart and take their
/// sibling files through a callback.
///
/// Why it matters: decoding the 71 KB Utah teapot costs 5.39 ms of CPU, a third of
/// a 60 Hz frame, and a real model runs into tens of milliseconds. That is jank on
/// the UI isolate however fast the parser is — which is also why FFI would not have
/// fixed it (see docs/FFI-analysis.md).
///
/// **File reads stay on this isolate.** The obvious alternative — wire the platform
/// channel into the background isolate with `BackgroundIsolateBinaryMessenger` —
/// does not work for assets: it grants a channel but creates no `ServicesBinding`,
/// so `rootBundle` throws "Binding has not yet been initialized", and routing the
/// `flutter/assets` channel by hand makes Flutter's own reply handler fail a cast.
/// Reading here is also the better split: I/O is cheap, parsing is what blocks.
///
/// Sibling files are requested back over a port, so a `.gltf` referencing an
/// external `.bin` works exactly as it does synchronously.
Future<ModelDocument> decodeModelInIsolate(ModelLoadRequest request) async {
  // The web has no isolates. `dart:isolate` compiles there — it is a stub — so
  // this fails at run time rather than at build time, with
  // `ReceivePort.listen` unsupported, several seconds into loading a model.
  //
  // Decoding on the main thread instead, which is what the name promises not to
  // do and the only thing available. A parse that janks is worse than one that
  // does not; a parse that throws is worse than both.
  if (kIsWeb) return decodeModel(request);

  // An async span, not startSync/finishSync: the read and the isolate round trip
  // both suspend, and a synchronous span would close on the first await and
  // report a fraction of the real cost.
  final task = developer.TimelineTask()
    ..start('decodeModelInIsolate', arguments: <String, Object?>{
      'source': request.source.key,
    });
  try {
    return await _decodeModelInIsolate(request, task);
  } finally {
    task.finish();
  }
}

Future<ModelDocument> _decodeModelInIsolate(
  ModelLoadRequest request,
  developer.TimelineTask task,
) async {
  task.instant('read');
  final primary = await request.source.read();
  final resolve = request.source.resolveUri;

  final requests = ReceivePort();
  final subscription = requests.listen((Object? message) async {
    final envelope = message as List<Object?>;
    final uri = envelope[0] as String;
    final reply = envelope[1] as SendPort;
    try {
      reply.send(await resolve(uri));
    } catch (error) {
      // Errors cannot be thrown across a port, so they travel as a value and are
      // rethrown on the far side.
      reply.send(<Object?>['error', error.toString()]);
    }
  });

  final servicePort = requests.sendPort;
  try {
    task.instant('decode');
    return await Isolate.run(
      () => decodeModelBytes(request, primary, _portResolver(servicePort)),
    );
  } finally {
    await subscription.cancel();
    requests.close();
  }
}

/// A resolver that asks the spawning isolate to read a file.
AssetUriResolver _portResolver(SendPort servicePort) {
  return (uri) async {
    final reply = ReceivePort();
    try {
      servicePort.send(<Object?>[uri, reply.sendPort]);
      final response = await reply.first;
      if (response is Uint8List) return response;
      if (response is List && response.length == 2 && response[0] == 'error') {
        throw StateError('Could not read "$uri": ${response[1]}');
      }
      throw StateError('Unexpected reply reading "$uri": $response');
    } finally {
      reply.close();
    }
  };
}

/// Decodes a model on the calling isolate.
///
/// Exposed for tests and for callers that already run off the UI thread; regular
/// code should prefer [decodeModelInIsolate].
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
  final format = _resolveFormat(request, bytes);
  // Named after the format so the background isolate's span says which decoder
  // the time went into, rather than just "decode".
  final task = developer.TimelineTask()
    ..start('decode ${format.name}', arguments: <String, Object?>{
      'bytes': bytes.length,
    });

  final Future<ModelDocument> decoded;
  switch (format) {
    case ModelFormat.f3d:
      // Synchronous and essentially free: the header is read and everything
      // else becomes a view over these bytes when it is asked for.
      decoded = Future<ModelDocument>.value(F3dDocument.parse(bytes));

    case ModelFormat.obj:
      decoded = ObjLoader(
        layout: request.layout,
        normals: request.objNormals,
      ).load(bytes, resolveUri: resolveUri);

    case ModelFormat.gltf:
    case ModelFormat.auto:
      decoded = GltfLoader(layout: request.layout)
          .load(bytes, resolveUri: resolveUri);
  }
  return decoded.whenComplete(task.finish);
}

/// Chooses a decoder from the file name, then from the bytes.
///
/// Extension first because it is what the author intended; sniffing is the
/// fallback for names that carry no useful suffix.
ModelFormat _resolveFormat(ModelLoadRequest request, Uint8List bytes) {
  if (request.format != ModelFormat.auto) return request.format;

  final name = request.source.fileName.toLowerCase();
  if (name.endsWith('.f3d')) return ModelFormat.f3d;
  if (name.endsWith('.obj')) return ModelFormat.obj;
  if (name.endsWith('.gltf') || name.endsWith('.glb')) return ModelFormat.gltf;

  return sniffModelFormat(bytes);
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

  return ModelFormat.obj;
}
