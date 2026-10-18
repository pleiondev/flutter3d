/// `revalidated_asset.dart` off the web: the asset bundle is inside the
/// application, so there is nothing to revalidate and nothing to reload.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

/// Whether this is the browser implementation; false here, which picks the
/// native advice for a stale bundle.
const bool isWeb = false;

/// [key]'s bytes from `rootBundle`; [contentHash] is ignored, since a bundle
/// inside the application cannot be stale. A missing key throws the
/// `FlutterError` `rootBundle.load` throws.
Future<ByteData> loadAsset(String key, {String? contentHash}) =>
    rootBundle.load(key);

/// [key] as text from `rootBundle`, [contentHash] ignored as in [loadAsset].
Future<String> loadAssetString(String key, {String? contentHash}) =>
    rootBundle.loadString(key);

/// Always false: there is no page to reload off the web.
bool canRefreshForStale(String asset) => false;

/// Does nothing: there is no page to reload off the web.
void refreshForStale(String asset, String message) {}

/// Does nothing: no reload was ever remembered off the web.
void forgetStaleRefresh(String asset) {}
