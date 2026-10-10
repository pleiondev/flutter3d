/// `revalidated_asset.dart` in the browser: `fetch` with the cache mode said
/// out loud, and a reload remembered in `sessionStorage` so it happens once.
///
/// Its own few lines of interop rather than `package:web`, which this
/// package does not otherwise need.
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart' show FlutterError;

const bool isWeb = true;

extension type _RequestInit._(JSObject _) implements JSObject {
  external factory _RequestInit({String cache});
}

extension type _Response._(JSObject _) implements JSObject {
  external bool get ok;
  external int get status;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

@JS('fetch')
external JSPromise<_Response> _fetch(JSString url, _RequestInit init);

extension type _Storage._(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

@JS('sessionStorage')
external _Storage get _sessionStorage;

/// `history.go(0)`: the current page fetched again, hash route and all.
@JS('history.go')
external void _historyGo(int delta);

@JS('console.error')
external void _consoleError(JSString message);

String _urlOf(String key, String? contentHash) {
  final url = ui_web.assetManager.getAssetUrl(key);
  if (contentHash == null) return url;
  final separator = url.contains('?') ? '&' : '?';
  return '$url${separator}v=${Uri.encodeQueryComponent(contentHash)}';
}

Future<ByteData> loadAsset(String key, {String? contentHash}) async {
  final _Response response;
  try {
    response = await _fetch(
      _urlOf(key, contentHash).toJS,
      // With a hash the URL names the content and the ordinary cache is
      // right; without one, keep the copy but ask whether it is current.
      _RequestInit(cache: contentHash == null ? 'no-cache' : 'default'),
    ).toDart;
  } catch (error) {
    throw FlutterError('Unable to load asset: "$key" ($error).');
  }
  if (!response.ok) {
    throw FlutterError(
      'Unable to load asset: "$key". The server answered ${response.status}.',
    );
  }
  final buffer = (await response.arrayBuffer().toDart).toDart;
  return ByteData.view(buffer);
}

Future<String> loadAssetString(String key, {String? contentHash}) async {
  final data = await loadAsset(key, contentHash: contentHash);
  return utf8.decode(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}

String _mark(String asset) => 'flutter3d.staleRefresh:$asset';

bool canRefreshForStale(String asset) {
  try {
    return _sessionStorage.getItem(_mark(asset)) == null;
  } catch (_) {
    // Storage refused (a private window, a sandboxed frame): without a way
    // to remember the refresh, not refreshing is the one that cannot loop.
    return false;
  }
}

void refreshForStale(String asset, String message) {
  try {
    _sessionStorage.setItem(_mark(asset), '1');
  } catch (_) {
    return;
  }
  _consoleError(message.toJS);
  _historyGo(0);
}

void forgetStaleRefresh(String asset) {
  try {
    _sessionStorage.removeItem(_mark(asset));
  } catch (_) {
    // Nothing remembered, nothing to forget.
  }
}
