/// `WebGpuDevice.dispose()` actually releases what it holds, and the frame
/// arenas do not grow while a frame repeats.
///
///     flutter test --platform chrome test/dispose_test.dart
///
/// **Written before this backend drew anything**, which is the same order the
/// WebGL2 backend arrived in and for the same reason: a `GPUTexture` and a
/// `GPUBuffer` are real allocations with an explicit `destroy`, so a device
/// that never called one leaked for the life of the tab — and nothing about a
/// leak shows up in a picture. `debugTrackedResourceCount` and
/// `debugDrainErrors` are the pair that made the WebGL2 leaks observable in a
/// browser, and they exist here from the first commit rather than after the
/// first leak.
///
/// The second half of the file is about the arenas, which are the piece of this
/// backend with no counterpart anywhere else. The WebGL2 backend makes a buffer
/// per transient binding and deletes it when the pass ends — the handoff
/// measured 1552 in one frame — and that shape is not available here. What
/// replaces it is a bump allocator reset at `beginFrame`, and the property that
/// makes it worth having is that a frame drawn twice allocates nothing the
/// second time. Nothing else would notice if it stopped being true: the picture
/// would be identical and the buffer count would climb.
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgpu/flutter3d_webgpu_web.dart';
import 'package:flutter_test/flutter_test.dart';

import 'quad_stages.dart';

const int _width = 32;
const int _height = 32;

Future<WebGpuDevice?> _open() =>
    WebGpuDevice.create(width: _width, height: _height, stages: quadStages);

ByteData _rgba(int width, int height) =>
    ByteData(width * height * 4); // all zero is a valid pixel buffer

const RenderTargetSpec _target = RenderTargetSpec(
  width: _width,
  height: _height,
  format: TextureFormat.r8g8b8a8UNormInt,
);

void main() {
  test('a fresh device holds its own scratch and says how much', () async {
    final device = await _open();
    if (device == null) {
      markTestSkipped('no WebGPU in this browser');
      return;
    }
    // Three arena buffers and the zeroed block behind an unbound uniform. Not
    // zero, unlike the WebGL2 backend's count of the same name, and the
    // difference is a fact about the two APIs: this one allocates before it is
    // asked for anything. No modules yet — the shader library compiles a stage
    // when a name is first asked for, and nothing has asked. What matters is
    // that the number is stated rather than discovered.
    expect(device.debugTrackedResourceCount, 4);
    expect(device.shaders['QuadVertex'], isNotNull);
    expect(
      device.debugTrackedResourceCount,
      5,
      reason: 'asking for a stage is what compiles it',
    );
    expect(await device.debugDrainErrors('opening'), isNull);
    device.dispose();
  });

  test('every texture, cube and geometry buffer is tracked', () async {
    final device = await _open();
    if (device == null) {
      markTestSkipped('no WebGPU in this browser');
      return;
    }
    final before = device.debugTrackedResourceCount;

    device.createTexture(_target);
    expect(device.debugTrackedResourceCount, before + 1);

    device.createTextureFromPixels(
      width: 4,
      height: 4,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: _rgba(4, 4),
    );
    expect(device.debugTrackedResourceCount, before + 2);

    device.createCubeTextureFromPixels(
      size: 2,
      format: TextureFormat.r8g8b8a8UNormInt,
      faces: List<ByteData>.generate(6, (_) => _rgba(2, 2)),
    );
    expect(device.debugTrackedResourceCount, before + 3);

    device.uploadGeometry(quadIndices(), GeometryUsage.indices);
    expect(device.debugTrackedResourceCount, before + 4);

    expect(await device.debugDrainErrors('allocating'), isNull);
    device.dispose();
  });

  test('dispose releases everything and the browser accepts it', () async {
    final device = await _open();
    if (device == null) {
      markTestSkipped('no WebGPU in this browser');
      return;
    }
    device
      ..createTexture(_target)
      ..createTexture(
        const RenderTargetSpec(
          width: _width,
          height: _height,
          format: TextureFormat.r8g8b8a8UNormInt,
          sampleCount: 4,
        ),
      )
      ..uploadGeometry(quadVertices(), GeometryUsage.vertices);
    // Drained first, so a leftover complaint from setup is not blamed on
    // dispose.
    await device.debugDrainErrors('setup');

    device.dispose();

    expect(device.debugTrackedResourceCount, 0);
    expect(
      await device.debugDrainErrors('dispose'),
      isNull,
      reason:
          'destroying a texture or a buffer twice, or one this device never '
          'made, is a validation error — which is what the error scopes are '
          'here to turn into a sentence',
    );
  });

  test('disposing twice is refused rather than silently accepted', () async {
    final device = await _open();
    if (device == null) {
      markTestSkipped('no WebGPU in this browser');
      return;
    }
    device.dispose();
    expect(device.dispose, throwsStateError);
  });

  group('one at a time', () {
    test('a released texture stops being tracked', () async {
      // **`dispose` was the only release there was on the second backend**, and
      // a renderer does not dispose — it reallocates. A resize remakes six or
      // seven full-screen targets; without this they stay for as long as the
      // tab is open.
      //
      // Mutation: make `releaseTexture` a no-op. The count stays at one above
      // the device's own scratch.
      final device = await _open();
      if (device == null) {
        markTestSkipped('no WebGPU in this browser');
        return;
      }
      final before = device.debugTrackedResourceCount;
      final texture = device.createTexture(_target);
      expect(device.debugTrackedResourceCount, before + 1);
      await device.debugDrainErrors('setup');

      device.releaseTexture(texture);

      expect(device.debugTrackedResourceCount, before);
      expect(await device.debugDrainErrors('releaseTexture'), isNull);
      device.dispose();
    });

    test(
      'releasing the same one twice destroys nothing the second time',
      () async {
        // The guard that makes the ring in the renderer safe to get wrong: a
        // handle released twice must not become a second `destroy` on an
        // allocation the browser may already have reissued.
        final device = await _open();
        if (device == null) {
          markTestSkipped('no WebGPU in this browser');
          return;
        }
        final before = device.debugTrackedResourceCount;
        final texture = device.createTexture(_target);
        device.releaseTexture(texture);
        await device.debugDrainErrors('first release');

        device.releaseTexture(texture);

        expect(device.debugTrackedResourceCount, before);
        expect(await device.debugDrainErrors('second release'), isNull);
        device.dispose();
      },
    );

    test('and a released geometry buffer goes the same way', () async {
      final device = await _open();
      if (device == null) {
        markTestSkipped('no WebGPU in this browser');
        return;
      }
      final before = device.debugTrackedResourceCount;
      final geometry = device.uploadGeometry(
        quadIndices(),
        GeometryUsage.indices,
      );
      expect(device.debugTrackedResourceCount, before + 1);
      await device.debugDrainErrors('setup');

      device.releaseGeometry(geometry);

      expect(device.debugTrackedResourceCount, before);
      expect(await device.debugDrainErrors('releaseGeometry'), isNull);
      device.dispose();
    });
  });

  group('the frame arenas', () {
    test(
      'rewind at beginFrame, so a repeated frame allocates nothing',
      () async {
        final device = await _open();
        if (device == null) {
          markTestSkipped('no WebGPU in this browser');
          return;
        }
        final bytes = ByteData(1024);

        device.beginFrame();
        for (var i = 0; i < 8; i++) {
          device.uniformArena.write(bytes);
        }
        final afterOneFrame = device.uniformArena.peakBytes;
        expect(afterOneFrame, greaterThan(0));

        // Twenty more frames of exactly the same shape. Without the rewind the
        // cursor walks past the arena's 64 KiB and the buffer count climbs;
        // with it, the high-water mark never moves again.
        for (var frame = 0; frame < 20; frame++) {
          device.beginFrame();
          for (var i = 0; i < 8; i++) {
            device.uniformArena.write(bytes);
          }
        }
        expect(device.uniformArena.peakBytes, afterOneFrame);
        expect(device.uniformArena.bufferCount, 1);
        expect(await device.debugDrainErrors('arena'), isNull);
        device.dispose();
      },
    );

    test(
      'grow by retiring rather than destroying what a pass may be reading',
      () async {
        // A bind group made earlier in this frame names the buffer it was made
        // against and a submitted pass is reading it, so an arena that outgrows
        // itself cannot free the old one — it keeps it until the device goes.
        // Doubling is what makes that list short.
        final device = await _open();
        if (device == null) {
          markTestSkipped('no WebGPU in this browser');
          return;
        }
        expect(device.uniformArena.bufferCount, 1);
        device.uniformArena.write(ByteData(1 << 18));
        expect(device.uniformArena.bufferCount, 2);
        expect(await device.debugDrainErrors('growth'), isNull);

        device.dispose();
        expect(device.debugTrackedResourceCount, 0);
      },
    );
  });
}
