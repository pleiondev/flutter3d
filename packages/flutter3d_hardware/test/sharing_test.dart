// Sharing between two devices: the copy through host memory every pair
// has, and the refusal, with the half that is missing, where zero copy is
// demanded and neither side can give it.
import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show UnsupportedCapabilityException;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

const TextureDescriptor _square = TextureDescriptor(
  width: 2,
  height: 2,
  format: TextureFormat.r8g8b8a8UNormInt,
);

void main() {
  test('two devices without sharing copy through host memory', () async {
    // Mutation: publish without overwriting the consumer's texture, and the
    // consumer samples what it was made with.
    final producer = FakeBackend()
      ..answerReadback = (TextureHandle t, ScreenRect r) =>
          ByteData.sublistView(Uint8List.fromList(List<int>.filled(16, 7)));
    final consumer = FakeBackend();
    final shared = SharedTexture.create(
      producer: producer,
      consumer: consumer,
      descriptor: _square,
    );
    expect(shared.mode, SharingMode.hostCopy);
    expect(shared.fence, isNull);
    await shared.publish();
    expect(producer.readbacks.single.texture, same(shared.producerTexture));
    expect(consumer.overwrittenTextures, hasLength(1));
    expect(shared.published, 1);
    shared.dispose();
  });

  test('zero copy demanded where neither side shares is refused', () {
    // Mutation: fall back to the copy under a demand, and a caller that
    // needs the texture in place gets a copy it did not ask for.
    expect(
      () => SharedTexture.create(
        producer: FakeBackend(),
        consumer: FakeBackend(),
        descriptor: _square,
        demand: SharingMode.zeroCopy,
      ),
      throwsA(
        isA<SharingException>()
            .having((e) => e.mode, 'mode', SharingMode.zeroCopy)
            .having((e) => e.reason, 'reason', contains('cannot export')),
      ),
    );
  });

  test('a device without the features refuses each sharing call', () {
    // Mutation: give a default body that answers, and conformance cannot
    // tell a device that shares from one that pretends to.
    final device = FakeBackend();
    final texture = device.createTexture(_square);
    expect(device.shareableKinds, isEmpty);
    Matcher refusal(DeviceFeature feature) => throwsA(
      isA<UnsupportedCapabilityException>().having(
        (e) => e.feature,
        'feature',
        feature,
      ),
    );
    expect(
      () => device.exportTexture(texture),
      refusal(DeviceFeature.sharedTextures),
    );
    expect(
      () => device.importTexture(
        const NativeHandle(NativeHandleKind.metalTexture, 0x1000),
        _square,
      ),
      refusal(DeviceFeature.sharedTextures),
    );
    expect(device.createFence, refusal(DeviceFeature.sharedFences));
  });

  test('the sharing sets are open, with stable names', () {
    expect(
      NativeHandleKind.byName('ioSurface'),
      same(NativeHandleKind.ioSurface),
    );
    expect(NativeHandleKind.byName('a kind from a newer version'), isNull);
    expect(SharingMode.values.map((m) => m.name), <String>[
      'zeroCopy',
      'hostCopy',
    ]);
    expect(
      const NativeHandle(NativeHandleKind.metalTexture, 16),
      const NativeHandle(NativeHandleKind.metalTexture, 16),
    );
  });
}
