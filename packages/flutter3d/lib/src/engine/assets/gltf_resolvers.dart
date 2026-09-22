import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter3d_core/flutter3d_core.dart';

/// Resolves asset URIs against the Flutter asset bundle.
///
/// **The one half of this file that still names Flutter (mcp-03n).**
/// `fileUriResolver`, the `dart:io` half this used to sit beside, moved to
/// `flutter3d_core`, along with `escapesAssetBase` — the check both halves
/// need and only one of them can still call by its old, private name.
AssetUriResolver assetUriResolver(String baseAssetPath, {AssetBundle? bundle}) {
  final source = bundle ?? rootBundle;
  return (AssetRequest request) async {
    final uri = request.uri;
    if (uri.startsWith('data:')) return decodeDataUri(uri);

    final relative = Uri.decodeComponent(uri);
    if (escapesAssetBase(relative)) {
      throw ArgumentError(
        'Refusing to load "$uri": it escapes the asset directory.',
      );
    }

    final data = await source.load('$baseAssetPath/$relative');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  };
}
