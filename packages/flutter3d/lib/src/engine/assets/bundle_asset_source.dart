import 'dart:typed_data';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show AssetNotFoundException;

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
  ///
  /// A key the bundle does not hold is an [AssetNotFoundException] naming it, with
  /// the platform's own `FlutterError` as its cause — readiness review
  /// §2.2.6 — so a caller that catches the engine's root catches this too.
  @override
  Future<Uint8List> read() => _load(assetPath);

  @override
  AssetUriResolver get resolveUri {
    final slash = assetPath.lastIndexOf('/');
    final directory = slash < 0 ? '' : assetPath.substring(0, slash);
    return (request) async {
      final uri = request.uri;
      if (uri.startsWith('data:')) return decodeDataUri(uri);
      return _load('$directory/${safeRelativeAssetPath(uri)}');
    };
  }

  static Future<Uint8List> _load(String key) async {
    final ByteData data;
    try {
      data = isGeneratedAsset(key)
          ? await loadRevalidatedAsset(key)
          : await rootBundle.load(key);
    } on FlutterError catch (error) {
      // The message, not the error: a `FlutterError` carries diagnostics
      // that need not cross the isolate a model is decoded on.
      throw AssetNotFoundException(
        key,
        detail:
            'the asset bundle does not hold it; declare it under '
            '`flutter: assets:` in pubspec.yaml',
        cause: error.message,
      );
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}
