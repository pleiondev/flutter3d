// Sharing between two devices: the copy through host memory every pair
// has, and the refusal, with the half that is missing, where zero copy is
// demanded and neither side can give it.
import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show UnsupportedCapabilityException;
import 'package:flutter3d_hardware/backend.dart' show checkNativeImport;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

const TextureDescriptor _square = TextureDescriptor(
  width: 2,
  height: 2,
  format: TextureFormat.r8g8b8a8UNormInt,
);

/// A fake that makes the plain textures shared here: texture writes, and
/// no sharing feature.
FakeBackend _fake() => FakeBackend(
  extraFeatures: const <DeviceFeature>[DeviceFeature.textureWrites],
);

void main() {
  test('two devices without sharing copy through host memory', () async {
    // Mutation: publish without overwriting the consumer's texture, and the
    // consumer samples what it was made with.
    final producer = _fake()
      ..answerReadback = (TextureHandle t, ScreenRect r) =>
          ByteData.sublistView(Uint8List.fromList(List<int>.filled(16, 7)));
    final consumer = _fake();
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
        producer: _fake(),
        consumer: _fake(),
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
    final device = _fake();
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

  test('the Direct3D 12 kinds are named, one memory and one fence', () {
    // Mutation: drop either from `values`, and a report naming it reads
    // back as a kind from a newer version; mark the resource a fence, and
    // a texture could never be shared through it.
    expect(
      NativeHandleKind.byName('d3d12SharedResource'),
      same(NativeHandleKind.d3d12SharedResource),
    );
    expect(
      NativeHandleKind.byName('d3d12SharedFence'),
      same(NativeHandleKind.d3d12SharedFence),
    );
    expect(NativeHandleKind.d3d12SharedResource.isFence, isFalse);
    expect(NativeHandleKind.d3d12SharedFence.isFence, isTrue);
    expect(
      NativeHandleKind.values.where((k) => k.isFence).map((k) => k.name),
      unorderedEquals(<String>[
        'metalSharedEvent',
        'vulkanSemaphoreFd',
        'vulkanSemaphoreWin32',
        'd3d12SharedFence',
      ]),
    );
  });

  test('every device here refuses to import a Direct3D 12 handle', () {
    // No backend takes the D3D12 kinds yet. Mutation: give the default
    // import a body that answers, and a handle no device can open becomes
    // a texture over nothing.
    final device = _fake();
    Matcher refusal(DeviceFeature feature) => throwsA(
      isA<UnsupportedCapabilityException>().having(
        (e) => e.feature,
        'feature',
        feature,
      ),
    );
    expect(
      () => device.importTexture(
        const NativeHandle(NativeHandleKind.d3d12SharedResource, 0x40),
        _square,
      ),
      refusal(DeviceFeature.sharedTextures),
    );
    expect(
      () => device.importBuffer(
        const NativeHandle(NativeHandleKind.d3d12SharedResource, 0x40),
        const BufferDescriptor(lengthInBytes: 16, usage: BufferUsage.storage),
      ),
      refusal(DeviceFeature.sharedBuffers),
    );
    expect(
      () => device.importFence(
        const NativeHandle(NativeHandleKind.d3d12SharedFence, 0x44),
      ),
      refusal(DeviceFeature.sharedFences),
    );
  });

  group('checkNativeImport', () {
    const vulkanOnly = <NativeHandleKind>{
      NativeHandleKind.vulkanMemoryWin32,
      NativeHandleKind.vulkanSemaphoreWin32,
    };

    test('a Direct3D 12 handle is refused where only Vulkan is taken', () {
      // Both are Win32 handles. Mutation: accept any Win32 kind, and a
      // D3D12 resource is imported as Vulkan memory it never was.
      expect(
        () => checkNativeImport(
          const NativeHandle(NativeHandleKind.d3d12SharedResource, 0x40),
          accepts: vulkanOnly,
          fence: false,
          backend: 'a Vulkan device',
          operation: 'importTexture',
        ),
        throwsA(
          isA<DeviceResourceException>()
              .having((e) => e.operation, 'operation', 'importTexture')
              .having((e) => e.reason, 'reason', contains('d3d12'))
              .having((e) => e.reason, 'reason', contains('never read')),
        ),
      );
      expect(
        () => checkNativeImport(
          const NativeHandle(NativeHandleKind.d3d12SharedFence, 0x44),
          accepts: vulkanOnly,
          fence: true,
          backend: 'a Vulkan device',
          operation: 'importFence',
        ),
        throwsA(isA<DeviceResourceException>()),
      );
    });

    test('memory is never imported as a fence, nor a fence as memory', () {
      // Mutation: check the list alone, and a device listing both kinds
      // imports a fence handle as a texture.
      const both = <NativeHandleKind>{
        NativeHandleKind.d3d12SharedResource,
        NativeHandleKind.d3d12SharedFence,
      };
      expect(
        () => checkNativeImport(
          const NativeHandle(NativeHandleKind.d3d12SharedFence, 0x44),
          accepts: both,
          fence: false,
          backend: 'a D3D12 device',
          operation: 'importTexture',
        ),
        throwsA(
          isA<DeviceResourceException>().having(
            (e) => e.reason,
            'reason',
            contains('names a fence'),
          ),
        ),
      );
      expect(
        () => checkNativeImport(
          const NativeHandle(NativeHandleKind.d3d12SharedResource, 0x40),
          accepts: both,
          fence: true,
          backend: 'a D3D12 device',
          operation: 'importFence',
        ),
        throwsA(isA<DeviceResourceException>()),
      );
      checkNativeImport(
        const NativeHandle(NativeHandleKind.d3d12SharedResource, 0x40),
        accepts: both,
        fence: false,
        backend: 'a D3D12 device',
        operation: 'importTexture',
      );
      checkNativeImport(
        const NativeHandle(NativeHandleKind.d3d12SharedFence, 0x44),
        accepts: both,
        fence: true,
        backend: 'a D3D12 device',
        operation: 'importFence',
      );
    });
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
