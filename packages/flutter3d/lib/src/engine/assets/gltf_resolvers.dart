import 'dart:io';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'asset_resolver.dart';
import 'gltf/glb_container.dart';

/// Resolves asset URIs relative to a directory on disk.
///
/// Separated from the parser because `dart:io` is unavailable on web, and
/// because a `.gltf` file's `uri` fields are percent-encoded relative paths that
/// must not be handed to the filesystem verbatim.
AssetUriResolver fileUriResolver(String baseDirectory) {
  return (String uri) async {
    if (uri.startsWith('data:')) return decodeDataUri(uri);

    final relative = Uri.decodeComponent(uri);
    if (_escapesBase(relative)) {
      throw ArgumentError(
        'Refusing to load "$uri": it escapes the asset directory.',
      );
    }

    final file = File('$baseDirectory/$relative');
    if (!await file.exists()) {
      throw FileSystemException('glTF resource not found', file.path);
    }
    return file.readAsBytes();
  };
}

/// Resolves asset URIs against the Flutter asset bundle.
AssetUriResolver assetUriResolver(
  String baseAssetPath, {
  AssetBundle? bundle,
}) {
  final source = bundle ?? rootBundle;
  return (String uri) async {
    if (uri.startsWith('data:')) return decodeDataUri(uri);

    final relative = Uri.decodeComponent(uri);
    if (_escapesBase(relative)) {
      throw ArgumentError(
        'Refusing to load "$uri": it escapes the asset directory.',
      );
    }

    final data = await source.load('$baseAssetPath/$relative');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  };
}

/// A glTF `uri` is always relative to the document. An absolute path or a `..`
/// segment means the file is trying to read outside the asset directory, which
/// is worth refusing rather than resolving.
bool _escapesBase(String relative) {
  if (relative.startsWith('/') || relative.startsWith(r'\')) return true;
  if (relative.contains('://')) return true;
  return relative.split(RegExp(r'[/\\]')).contains('..');
}
