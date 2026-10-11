import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_hub/flutter3d_hub.dart';

/// A model on the hub, models.pleion.dev, named by its reference.
///
/// ```dart
/// final chair = HubAssetSource(
///   HubReference.parse('0f8b5c2e-7a41-4d3b-9c6e-2a1f8e4d7b90@3'),
/// );
/// ```
///
/// **Its identity is the reference.** [key] is `hub:<uuid>@<n>`, so the
/// version is part of it and two versions never share a cache entry; the
/// checksum is not, because a version on the hub is immutable and a
/// reference with a checksum names the same file as one without.
/// [contentHash] is the reference's checksum and [version] its version.
///
/// **Sendable**: the reference and the policy are plain data, so the source
/// travels with a `ModelLoadRequest` to the decoding isolate like any other.
///
/// **No client in this release.** [read] refuses with
/// `HubRefusal.offline` and says so; the client that downloads, checks the
/// hash and caches arrives as an addition in `flutter3d_hub`, and a program
/// written against this source then loads the model with no change. Until
/// then a model is vendored into `assets/` and loaded from the bundle.
final class HubAssetSource extends AssetSource {
  /// The hub model [reference], fetched and kept as [cache] allows.
  const HubAssetSource(this.reference, {this.cache = HubCachePolicy.standard});

  /// The model and version, with the checksum to hold its bytes to if the
  /// reference carries one.
  final HubReference reference;

  /// Where the model may come from and whether it is kept.
  final HubCachePolicy cache;

  @override
  String get key => 'hub:${reference.withoutChecksum}';

  @override
  String? get contentHash => reference.sha256;

  @override
  int get version => reference.version;

  @override
  Future<Uint8List> read() async => throw HubRefusedException(
    HubRefusal.offline,
    reference: reference,
    detail:
        'this release of flutter3d has no hub client yet. Vendor the model '
        'into assets/ and load it with BundleAssetSource.',
  );

  /// **A hub model is one self-contained file** (a `.glb` or an `.f3d`), so
  /// the only thing it may reference is a `data:` URI inside itself.
  @override
  AssetUriResolver get resolveUri => (AssetRequest request) async {
    final uri = request.uri;
    if (uri.startsWith('data:')) return decodeDataUri(uri);
    throw HubRefusedException(
      HubRefusal.notFound,
      reference: reference,
      detail:
          'a hub model is one self-contained file, and this one names "$uri" '
          'beside it.',
    );
  };
}
