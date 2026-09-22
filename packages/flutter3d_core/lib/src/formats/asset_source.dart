import 'dart:typed_data';

import 'asset_resolver.dart';

/// Where a model and its sibling files live.
///
/// A sendable *description* rather than a resolver closure, because that is what
/// crosses an isolate boundary: the background isolate reconstructs the resolver
/// from this instead of receiving a callback that closes over the asset bundle.
///
/// **Open, and without a registry.** A game whose assets live somewhere this
/// package has never heard of — inside an archive, behind a network cache, in a
/// database — writes its own source and passes it. Sealing said the engine has
/// the full list of places an asset can be, which was never true.
///
/// A registry was the obvious way to open it and is the wrong one here, for the
/// reason [ModelLoadRequest.decoders] is written down at length: decoding runs
/// on a background isolate, statics are not shared across isolates in Dart, and
/// a registry filled at startup in the main isolate is empty in the one that
/// does the reading. It would work in a test and fail in the application. So a
/// source travels with the request exactly as a decoder does — which means it
/// must be **sendable**: a plain object holding plain data. A source that
/// closes over a texture, a device or a port cannot cross and will say so at
/// run time.
///
/// **The two sources this repository ships are not here**, and the split is the
/// same one that made this a package: `BundleAssetSource` reads Flutter's asset
/// bundle and `FileAssetSource` reads `dart:io`, so both live in `flutter3d`,
/// which may name either. What is left is what a decoder actually needs — a
/// key, some bytes and a resolver — and it compiles wherever Dart does.
///
/// `base`: extend it, do not implement it, so a member added here later is
/// inherited rather than missing.
///
/// A subclass owes [key], [read] and [resolveUri]. [key] is the cache key, so
/// two sources naming the same file must agree on it and two naming different
/// files must not collide — prefix it the way the engine's two do.
abstract base class AssetSource {
  const AssetSource();

  /// Stable identity, used as the cache key.
  String get key;

  /// The model file itself.
  Future<Uint8List> read();

  /// Resolves files referenced from inside the model, relative to its directory.
  AssetUriResolver get resolveUri;

  /// Everything after the last path separator.
  String get fileName {
    final path = key;
    final slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }
}

/// A reference inside a model is always relative to the model. An absolute path
/// or a `..` segment means the file is reaching outside its directory, which is
/// worth refusing rather than resolving.
///
/// Public because the sources that need it are in another package now, and a
/// second copy of this check is a second chance to get it wrong.
String safeRelativeAssetPath(String uri) {
  final relative = Uri.decodeComponent(uri);
  if (relative.startsWith('/') ||
      relative.startsWith(r'\') ||
      relative.contains('://') ||
      relative.split(RegExp(r'[/\\]')).contains('..')) {
    throw ArgumentError(
      'Refusing to load "$uri": it escapes the asset directory.',
    );
  }
  return relative;
}
