import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'gltf/gltf.dart';

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
      // Synchronous: see the note in `gltf_resolvers.dart`. This runs on an
      // isolate of its own, so there is nothing here for it to block.
      if (!file.existsSync()) {
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
