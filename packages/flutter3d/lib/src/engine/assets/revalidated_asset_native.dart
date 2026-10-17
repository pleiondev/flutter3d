/// `revalidated_asset.dart` off the web: the asset bundle is inside the
/// application, so there is nothing to revalidate and nothing to reload.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

const bool isWeb = false;

Future<ByteData> loadAsset(String key, {String? contentHash}) =>
    rootBundle.load(key);

Future<String> loadAssetString(String key, {String? contentHash}) =>
    rootBundle.loadString(key);

bool canRefreshForStale(String asset) => false;

void refreshForStale(String asset, String message) {}

void forgetStaleRefresh(String asset) {}
