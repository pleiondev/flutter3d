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

/// Whether this is the browser implementation; true here, which picks the
/// web advice for a stale bundle.
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

/// [key]'s bytes fetched from the asset URL.
///
/// Without [contentHash] the fetch uses `cache: 'no-cache'`, so the server is
/// asked whether the cached copy is current; with one, the hash goes in the
/// URL as `?v=` and the ordinary cache is used. A failed fetch or a response
/// that is not ok throws a `FlutterError` naming [key], as `rootBundle.load`
/// does for a missing asset.
Future<ByteData> loadAsset(String key, {String? contentHash}) async {
  final _Response response;
  try {
    response = await _fetch(
      _urlOf(key, contentHash).toJS,
      // With a hash the URL names the content and the ordinary cache is
      // right; without one, keep the copy but ask whether it is current.
      _RequestInit(cache: contentHash == null ? 'no-cache' : 'default'),
    ).toDart;
  } catch (error, stack) {
    Error.throwWithStackTrace(
      FlutterError('Unable to load asset: "$key" ($error).'),
      stack,
    );
  }
  if (!response.ok) {
    throw FlutterError(
      'Unable to load asset: "$key". The server answered ${response.status}.',
    );
  }
  final buffer = (await response.arrayBuffer().toDart).toDart;
  return ByteData.view(buffer);
}

/// [key] as UTF-8 text, fetched as [loadAsset] fetches it.
Future<String> loadAssetString(String key, {String? contentHash}) async {
  final data = await loadAsset(key, contentHash: contentHash);
  return utf8.decode(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}

String _mark(String asset) => 'flutter3d.staleRefresh:$asset';

/// Whether the page may still be reloaded for a stale [asset]: true until
/// [refreshForStale] has marked it in this tab's `sessionStorage`.
///
/// False when the storage refuses access, since a reload that cannot be
/// remembered could repeat forever.
bool canRefreshForStale(String asset) {
  try {
    return _sessionStorage.getItem(_mark(asset)) == null;
  } catch (_) {
    // Storage refused (a private window, a sandboxed frame): without a way
    // to remember the refresh, not refreshing is the one that cannot loop.
    return false;
  }
}

/// Marks [asset] as refreshed in `sessionStorage`, logs [message] to the
/// console and reloads the page.
///
/// Does nothing when the mark cannot be stored.
void refreshForStale(String asset, String message) {
  try {
    _sessionStorage.setItem(_mark(asset), '1');
  } catch (_) {
    return;
  }
  _consoleError(message.toJS);
  _historyGo(0);
}

/// Clears the mark [refreshForStale] left for [asset], once its bundle has
/// loaded, so a later stale deploy may reload the page again.
void forgetStaleRefresh(String asset) {
  try {
    _sessionStorage.removeItem(_mark(asset));
  } catch (_) {
    // Nothing remembered, nothing to forget.
  }
}
