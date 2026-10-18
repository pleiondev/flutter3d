import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hub/flutter3d_hub.dart';
import 'package:test/test.dart';

const _uuid = '0f8b5c2e-7a41-4d3b-9c6e-2a1f8e4d7b90';
const _hash =
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

/// A source written outside the engine, against 1.0: it owes [key], [read]
/// and [resolveUri] and nothing else.
final class _PlainSource extends AssetSource {
  const _PlainSource();

  @override
  String get key => 'plain:model.glb';

  @override
  Future<Uint8List> read(AssetRead request) async => Uint8List(0);

  @override
  AssetUriResolver get resolveUri =>
      (AssetRequest request) async => Uint8List(0);
}

/// A versioned source: its version is part of its key.
final class _VersionedSource extends AssetSource {
  const _VersionedSource(this.version);

  @override
  final int version;

  @override
  String get contentHash => _hash;

  @override
  String get key => 'store:chair@$version';

  @override
  Future<Uint8List> read(AssetRead request) async => Uint8List(0);

  @override
  AssetUriResolver get resolveUri =>
      (AssetRequest request) async => Uint8List(0);
}

void main() {
  group('AssetSource identity', () {
    test('a source that says nothing has no hash and no version', () {
      const source = _PlainSource();
      expect(source.contentHash, isNull);
      expect(source.version, isNull);
      expect(const FileAssetSource('a/b.glb').version, isNull);
      expect(const FileAssetSource('a/b.glb').contentHash, isNull);
    });

    test('a source may carry both, and two versions are two keys', () {
      const one = _VersionedSource(1);
      const two = _VersionedSource(2);
      expect(one.contentHash, _hash);
      expect(one.version, 1);
      expect(one.key == two.key, isFalse);
    });
  });

  group('HubAssetSource', () {
    final reference = HubReference.parse('$_uuid@3#sha256=$_hash');

    test('is an asset source with the reference as its identity', () {
      final source = HubAssetSource(reference);
      expect(source, isA<AssetSource>());
      expect(source.version, 3);
      expect(source.contentHash, _hash);
      expect(source.cache, HubCachePolicy.standard);
    });

    test('its key names the model and the version, not the checksum', () {
      final pinned = HubAssetSource(reference);
      final loose = HubAssetSource(reference.withoutChecksum);
      final next = HubAssetSource(HubReference.parse('$_uuid@4'));
      expect(pinned.key, 'hub:$_uuid@3');
      expect(loose.key, pinned.key);
      expect(next.key == pinned.key, isFalse);
    });

    test('a reference without a checksum has no content hash', () {
      expect(HubAssetSource(reference.withoutChecksum).contentHash, isNull);
    });

    test('reading refuses with offline: this release has no client', () async {
      await expectLater(
        HubAssetSource(reference).read(AssetRead.whole),
        throwsA(
          isA<HubRefusedException>()
              .having((e) => e.reason, 'reason', HubRefusal.offline)
              .having((e) => e.reference, 'reference', reference)
              .having(
                (e) => e.message,
                'message',
                contains('Vendor the model'),
              ),
        ),
      );
    });

    test(
      'a hub model is one file: a sibling is refused, a data URI is not',
      () async {
        final resolve = HubAssetSource(reference).resolveUri;
        expect(
          await resolve(
            const AssetRequest('data:application/octet-stream;base64,AQI='),
          ),
          <int>[1, 2],
        );
        await expectLater(
          resolve(const AssetRequest('chair.bin')),
          throwsA(
            isA<HubRefusedException>().having(
              (e) => e.message,
              'message',
              contains('chair.bin'),
            ),
          ),
        );
      },
    );

    test(
      'is sendable, as a source must be to reach the decoding isolate',
      () async {
        final source = HubAssetSource(reference, cache: HubCachePolicy.offline);
        final back = await Isolate.run(() => source);
        expect(back.key, source.key);
        expect(back.reference, reference);
        expect(back.cache, HubCachePolicy.offline);
      },
    );
  });
}
