/// `WebGlDevice.dispose()` actually deletes the GL objects it tracks.
///
///     flutter test --platform chrome test/dispose_test.dart
///
/// WebGL2 objects are explicitly deletable — unlike flutter_gpu's `Texture`,
/// which has no native dispose and relies on the garbage collector, see the
/// note on `GpuRenderBackend.supportsCubeTextures` — so a `WebGlDevice` that
/// never called `gl.deleteTexture`/`gl.deleteBuffer`/`gl.deleteRenderbuffer`
/// for anything [WebGlDevice.createTexture], [WebGlDevice.createTextureFromPixels],
/// [WebGlDevice.createCubeTextureFromPixels] or [WebGlDevice.uploadGeometry]
/// handed out was a real leak on this backend, not a documented design choice.
///
/// This is checked two ways. `debugTrackedResourceCount` says the device
/// stopped considering the objects its own; `debugDrainErrors` after the
/// deletes says the driver accepted every one of them — a `gl.deleteTexture`
/// on a value that was never a valid texture raises `INVALID_VALUE`, so a
/// tracking bug that deleted the wrong handle, or the same handle twice,
/// would show up here rather than passing silently.
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgl/engine_shaders.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';
import 'package:flutter_test/flutter_test.dart';

const int _width = 32;
const int _height = 32;

WebGlDevice _makeDevice() {
  final device = WebGlDevice.create(
    width: _width,
    height: _height,
    sources: engineShaders,
  );
  if (device == null) fail('no WebGL2 context in this browser');
  return device;
}

ByteData _rgba(int width, int height) =>
    ByteData(width * height * 4); // all zero is a valid pixel buffer

void main() {
  test('a fresh device tracks nothing', () {
    final device = _makeDevice();
    expect(device.debugTrackedResourceCount, 0);
    device.dispose();
  });

  test('every persistent texture, cube and buffer is tracked', () {
    final device = _makeDevice();

    device.createTexture(
      const RenderTargetSpec(
        width: _width,
        height: _height,
        format: TextureFormat.r8g8b8a8UNormInt,
      ),
    );
    expect(device.debugTrackedResourceCount, 1);

    device.createTextureFromPixels(
      width: 4,
      height: 4,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: _rgba(4, 4),
    );
    expect(device.debugTrackedResourceCount, 2);

    device.createCubeTextureFromPixels(
      size: 2,
      format: TextureFormat.r8g8b8a8UNormInt,
      faces: List<ByteData>.generate(6, (_) => _rgba(2, 2)),
    );
    expect(device.debugTrackedResourceCount, 3);

    device.uploadGeometry(
      ByteData(4 * 3), // one triangle's worth of nonsense floats
      GeometryUsage.vertices,
    );
    expect(device.debugTrackedResourceCount, 4);

    device.dispose();
  });

  test('dispose deletes every tracked object and the driver accepts it', () {
    final device = _makeDevice();

    device.createTexture(
      const RenderTargetSpec(
        width: _width,
        height: _height,
        format: TextureFormat.r8g8b8a8UNormInt,
      ),
    );
    // A renderbuffer path: multisampled targets are renderbuffers rather than
    // textures — see the note on WebGlTexture — and dispose has to reach both.
    device.createTexture(
      const RenderTargetSpec(
        width: _width,
        height: _height,
        format: TextureFormat.r8g8b8a8UNormInt,
        sampleCount: 4,
      ),
    );
    device.uploadGeometry(ByteData(4 * 3), GeometryUsage.indices);
    expect(device.debugTrackedResourceCount, 3);

    // Drained first, so a leftover error from setup is not blamed on dispose.
    device.debugDrainErrors('setup');

    device.dispose();

    expect(device.debugTrackedResourceCount, 0);
    expect(
      device.debugDrainErrors('dispose'),
      isNull,
      reason:
          'gl.delete* on the tracked handles should not raise an error; '
          'INVALID_VALUE here would mean the wrong handle, or the same '
          'handle twice, was deleted',
    );
  });

  test('disposing twice is refused rather than silently accepted', () {
    final device = _makeDevice();
    device.dispose();
    expect(device.dispose, throwsStateError);
  });

  group('one at a time', () {
    test('a released texture stops being tracked, and the driver agrees', () {
      // **`dispose` was the only release there was**, and a renderer does not
      // dispose — it reallocates. A resize remakes six or seven full-screen
      // targets and a change of `cubeResolution` remakes two atlases of 75 MB
      // each, all of them replaced by assigning over a field. That is a free
      // where the collector does the work and a leak here, growing for as long
      // as the tab is open.
      //
      // Mutation: make `releaseTexture` a no-op. The count stays at one.
      final device = _makeDevice();
      final texture = device.createTexture(
        const RenderTargetSpec(
          width: _width,
          height: _height,
          format: TextureFormat.r8g8b8a8UNormInt,
        ),
      );
      expect(device.debugTrackedResourceCount, 1);
      device.debugDrainErrors('setup');

      device.releaseTexture(texture);

      expect(device.debugTrackedResourceCount, 0);
      expect(
        device.debugDrainErrors('releaseTexture'),
        isNull,
        reason: 'INVALID_VALUE here would mean the wrong handle was deleted',
      );
      device.dispose();
    });

    test('releasing the same one twice deletes nothing the second time', () {
      // The guard that makes the ring in the renderer safe to get wrong: a
      // handle released twice must not become a second `gl.deleteTexture` on
      // an id the driver may already have reissued.
      final device = _makeDevice();
      final texture = device.createTexture(
        const RenderTargetSpec(
          width: _width,
          height: _height,
          format: TextureFormat.r8g8b8a8UNormInt,
        ),
      );
      device.releaseTexture(texture);
      device.debugDrainErrors('first release');

      device.releaseTexture(texture);

      expect(device.debugTrackedResourceCount, 0);
      expect(device.debugDrainErrors('second release'), isNull);
      device.dispose();
    });

    test('and a released geometry buffer goes the same way', () {
      final device = _makeDevice();
      final geometry = device.uploadGeometry(
        ByteData(4 * 3),
        GeometryUsage.indices,
      );
      expect(device.debugTrackedResourceCount, 1);
      device.debugDrainErrors('setup');

      device.releaseGeometry(geometry);

      expect(device.debugTrackedResourceCount, 0);
      expect(device.debugDrainErrors('releaseGeometry'), isNull);
      device.dispose();
    });
  });
}
