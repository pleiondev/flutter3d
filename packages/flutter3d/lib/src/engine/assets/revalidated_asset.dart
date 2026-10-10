/// Generated assets read past a stale browser cache — `A4.18`.
///
/// **On the web the code and the files it reads are fetched separately**, and
/// a browser keeps either one as long as the server's headers let it. A
/// deploy that changes both can leave a returning visitor with the new
/// `main.dart.js` and yesterday's shader bundle, or the other way round, and
/// the pair was never built together. The engine's own shaders are compiled
/// into the code and cannot drift; a material's `.f3dshaders`, a converted
/// `.f3d` and the generated JSON beside them can.
///
/// So these files are fetched with `cache: 'no-cache'`, which keeps the
/// browser's copy but asks the server whether it is current — a `304` with
/// no body when it is. A build that knows a file's content hash can pass it
/// instead; the URL then names the content, and the ordinary cache is right.
///
/// **A mismatch that gets through anyway is caught by the bundle's version
/// stamp.** A bundle packed by a different flutter3d is refused as stale
/// (`ShaderBundleException.stale`); [loadShaderBundleBytes] turns that into a
/// page reload on the web — once, so a server that keeps serving the wrong
/// file cannot put the page in a loop — and a [ShaderBundleException] that says
/// which file and what to do, everywhere.
///
/// Natively the asset bundle is inside the application and cannot be out of
/// step with it, and these are `rootBundle` reads.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'revalidated_asset_native.dart'
    if (dart.library.js_interop) 'revalidated_asset_web.dart'
    as platform;

/// Whether [key] is a file the build generates — under `flutter3d_generated/`,
/// a shader bundle anywhere, or JSON — and so one the web reads with
/// [loadRevalidatedAsset]. Everything else an application ships by hand.
bool isGeneratedAsset(String key) =>
    key.startsWith('flutter3d_generated/') ||
    key.endsWith('.f3dshaders') ||
    key.endsWith('.json');

/// [key]'s bytes from the asset bundle, revalidated with the server on the
/// web.
///
/// [contentHash], when the build knows it, is put in the URL (`?v=`) instead
/// of asking the server, so an unchanged file costs no request at all. A
/// missing asset throws the `FlutterError` `rootBundle.load` throws, so a
/// caller's `on FlutterError` keeps meaning "not in the bundle".
Future<ByteData> loadRevalidatedAsset(String key, {String? contentHash}) =>
    platform.loadAsset(key, contentHash: contentHash);

/// [key] as UTF-8 text, read as [loadRevalidatedAsset] reads it.
Future<String> loadRevalidatedAssetString(String key, {String? contentHash}) =>
    platform.loadAssetString(key, contentHash: contentHash);

/// The shader bundle at [key], read with [loadRevalidatedAsset] and loaded
/// onto [device] through [loadShaderBundleBytes].
Future<LoadedShaderLibrary> loadShaderBundleAsset(
  GraphicsDevice device,
  String key, {
  String? contentHash,
}) async => loadShaderBundleBytes(
  device,
  await loadRevalidatedAsset(key, contentHash: contentHash),
  asset: key,
);

/// [bytes] loaded onto [device], with a stale bundle answered rather than
/// passed on as a bare refusal.
///
/// A bundle refused as stale — its version stamp is from a different
/// flutter3d than the code running — is thrown again as a
/// [ShaderBundleException] with [asset] and its [ShaderBundleException.advice]
/// filled in. On the web the page is reloaded first, once per [asset] per tab
/// session, which is what fetches code and bundle from the same deploy; the
/// exception still arrives, with [ShaderBundleException.refreshing] true, for a
/// caller to show while the page goes. Any other refusal is rethrown as it
/// was.
Future<LoadedShaderLibrary> loadShaderBundleBytes(
  GraphicsDevice device,
  ByteData bytes, {
  required String asset,
}) async {
  try {
    final library = await device.loadShaders(bytes);
    platform.forgetStaleRefresh(asset);
    return library;
  } on ShaderBundleException catch (refused) {
    if (!refused.stale) rethrow;
    final refreshing = platform.canRefreshForStale(asset);
    final stale = ShaderBundleException(
      name: refused.name,
      reason: refused.reason,
      stale: true,
      asset: asset,
      refreshing: refreshing,
      advice: _staleAdvice(refreshing: refreshing),
    );
    debugPrint('flutter3d: ${stale.message}');
    if (refreshing) platform.refreshForStale(asset, stale.message);
    throw stale;
  }
}

/// What a person does about a bundle from another build, which depends on
/// where the app runs and whether the page is already reloading.
String _staleAdvice({required bool refreshing}) => refreshing
    ? 'It was built for a different version of this app; refreshing the page '
          'to fetch files from the same build.'
    : platform.isWeb
    ? 'It was built for a different version of this app, and refreshing did '
          'not help: the server serves this file from another build. Deploy '
          'the app and its flutter3d_generated/ files together.'
    : 'It was built for a different version of this app. Rebuild the app; '
          'flutter3d_build repacks every bundle on the next build.';
