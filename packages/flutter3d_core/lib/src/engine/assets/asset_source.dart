import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';

import '../platform/files.dart';

// `AssetSource` itself is `flutter3d_formats`, along with the decoders that
// read through one. What is left here is the one place this package can read
// from without the Flutter SDK — `dart:io` — and no more: a bundle-backed
// source names `rootBundle`, which is `BundleAssetSource` in `flutter3d`
// (mcp-03n) instead, next to the one call in this whole engine that still
// needs one.
export 'package:flutter3d_core/formats.dart' show AssetSource;

/// A model on the filesystem. Unavailable on web, which is why it is a separate
/// source rather than a flag.
final class FileAssetSource extends AssetSource {
  const FileAssetSource(this.path);

  final String path;

  @override
  String get key => 'file:$path';

  @override
  Future<Uint8List> read() => readFileBytes(path);

  @override
  AssetUriResolver get resolveUri {
    final directory = parentDirectoryOf(path);
    return (request) async {
      final uri = request.uri;
      if (uri.startsWith('data:')) return decodeDataUri(uri);
      final relative = safeRelativeAssetPath(uri);
      // This runs on an isolate of its own, so the synchronous check
      // `readReferencedFile` makes has nothing here to block.
      return readReferencedFile(
        '$directory/$relative',
        'Referenced file not found',
      );
    };
  }
}
