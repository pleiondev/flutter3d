import 'dart:io';

import 'package:flutter3d_formats/flutter3d_formats.dart';

/// Resolves asset URIs relative to a directory on disk.
///
/// Separated from the parser because `dart:io` is unavailable on web, and
/// because a `.gltf` file's `uri` fields are percent-encoded relative paths that
/// must not be handed to the filesystem verbatim.
AssetUriResolver fileUriResolver(String baseDirectory) {
  return (AssetRequest request) async {
    final uri = request.uri;
    if (uri.startsWith('data:')) return decodeDataUri(uri);

    final relative = Uri.decodeComponent(uri);
    if (escapesAssetBase(relative)) {
      throw ArgumentError(
        'Refusing to load "$uri": it escapes the asset directory.',
      );
    }

    final file = File('$baseDirectory/$relative');
    // Synchronous, because an async `exists` is a round trip through the
    // event loop to answer a question the filesystem answers immediately —
    // and this one is asked once per referenced buffer and image.
    if (!file.existsSync()) {
      throw FileSystemException('glTF resource not found', file.path);
    }
    return file.readAsBytes();
  };
}

/// A glTF `uri` is always relative to the document. An absolute path or a `..`
/// segment means the file is trying to read outside the asset directory, which
/// is worth refusing rather than resolving.
///
/// Public — rather than the private helper it was before mcp-03n split this
/// file — because `flutter3d`'s own `assetUriResolver` (the asset-bundle
/// half of this file, which names Flutter and stayed there) asks the same
/// question of the same kind of `uri` and has to give the same answer.
bool escapesAssetBase(String relative) {
  if (relative.startsWith('/') || relative.startsWith(r'\')) return true;
  if (relative.contains('://')) return true;
  return relative.split(RegExp(r'[/\\]')).contains('..');
}
