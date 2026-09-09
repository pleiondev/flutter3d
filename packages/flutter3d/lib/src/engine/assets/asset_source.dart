import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter3d_formats/flutter3d_formats.dart';

// `AssetSource` itself is `flutter3d_formats`, along with the decoders that
// read through one. What is left here is the two places this engine knows how
// to read from — and each of them is exactly why the split exists: one names
// Flutter's asset bundle, the other names `dart:io`, and a decoder that has to
// resolve without either had both of them behind it.
export 'package:flutter3d_formats/flutter3d_formats.dart' show AssetSource;

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
    return (request) async {
      final uri = request.uri;
      if (uri.startsWith('data:')) return decodeDataUri(uri);
      final data = await rootBundle.load(
        '$directory/${safeRelativeAssetPath(uri)}',
      );
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
    return (request) async {
      final uri = request.uri;
      if (uri.startsWith('data:')) return decodeDataUri(uri);
      final relative = safeRelativeAssetPath(uri);
      final file = File('$directory/$relative');
      // Synchronous: see the note in `gltf_resolvers.dart`. This runs on an
      // isolate of its own, so there is nothing here for it to block.
      if (!file.existsSync()) {
        throw FileSystemException('Referenced file not found', file.path);
      }
      return file.readAsBytes();
    };
  }
}
