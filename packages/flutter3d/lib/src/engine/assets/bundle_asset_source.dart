import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter3d_core/flutter3d_core.dart';

import 'revalidated_asset.dart';

/// A model in the Flutter asset bundle.
///
/// Reading the bundle from a background isolate needs the platform channel to be
/// wired up there; [decodeModelInIsolate] passes the root isolate token that makes
/// that possible.
///
/// **Named Flutter, which is why it lives here rather than in
/// `flutter3d_core` (mcp-03n).** `FileAssetSource`, its `dart:io` sibling, made
/// the move; this is the one `AssetSource` that could not.
final class BundleAssetSource extends AssetSource {
  const BundleAssetSource(this.assetPath);

  final String assetPath;

  @override
  String get key => 'bundle:$assetPath';

  /// A generated file ([isGeneratedAsset]) is read with
  /// [loadRevalidatedAsset], so on the web a cached copy from an older
  /// deploy is never paired with newer code — `A4.18`.
  @override
  Future<Uint8List> read() async {
    final data = isGeneratedAsset(assetPath)
        ? await loadRevalidatedAsset(assetPath)
        : await rootBundle.load(assetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  @override
  AssetUriResolver get resolveUri {
    final slash = assetPath.lastIndexOf('/');
    final directory = slash < 0 ? '' : assetPath.substring(0, slash);
    return (request) async {
      final uri = request.uri;
      if (uri.startsWith('data:')) return decodeDataUri(uri);
      final key = '$directory/${safeRelativeAssetPath(uri)}';
      final data = isGeneratedAsset(key)
          ? await loadRevalidatedAsset(key)
          : await rootBundle.load(key);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    };
  }
}
