/// A handle says its shape once: `type` and `sliceCount` are read from
/// `dimension`, and `hostReadable` from `usage`, so a backend that sets only
/// the 1.0 field is read the same way by the engine and by conformance.
library;

import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';

TextureHandle _texture({TextureType? type, TextureDimension? dimension}) =>
    wrapTexture(
      backend: Object(),
      width: 4,
      height: 4,
      format: TextureFormat.r8g8b8a8UNormInt,
      type: type,
      dimension: dimension,
    );

void main() {
  group('a texture handle', () {
    test('a cube said by its dimension alone is a cube everywhere', () {
      // Mutation: `type` stored as given (texture2D by default) leaves a
      // backend that says `dimension: cube` with a handle the sky pass and
      // the conformance checks read as a flat texture of one slice.
      final cube = _texture(dimension: TextureDimension.cube);
      expect(cube.type, TextureType.textureCube);
      expect(cube.sliceCount, 6);
      expect(cube.depthOrArrayLayers, 6);
    });

    test('a cube array is a cube too', () {
      final cubes = wrapTexture(
        backend: Object(),
        width: 4,
        height: 4,
        format: TextureFormat.r8g8b8a8UNormInt,
        dimension: TextureDimension.cubeArray,
        depthOrArrayLayers: 12,
      );
      expect(cubes.type, TextureType.textureCube);
      expect(cubes.sliceCount, 6);
      expect(cubes.depthOrArrayLayers, 12);
    });

    test('the pre-1.0 type alone still means its shape', () {
      final cube = _texture(type: TextureType.textureCube);
      expect(cube.dimension, TextureDimension.cube);
      expect(cube.sliceCount, 6);
      final flat = _texture();
      expect(flat.type, TextureType.texture2D);
      expect(flat.dimension, TextureDimension.d2);
      expect(flat.sliceCount, 1);
    });

    test('a 3D texture is not a cube, whatever its depth', () {
      final volume = _texture(dimension: TextureDimension.d3);
      expect(volume.type, TextureType.texture2D);
      expect(volume.sliceCount, 1);
    });

    test('a type and a dimension that disagree are refused', () {
      // Mutation: the agreement check removed lets a handle carry a cube
      // type over a 2D dimension, and the engine reads one shape while the
      // binding reads another.
      expect(
        () => _texture(
          type: TextureType.textureCube,
          dimension: TextureDimension.d2,
        ),
        throwsArgumentError,
      );
      expect(
        () => _texture(
          type: TextureType.texture2D,
          dimension: TextureDimension.cube,
        ),
        throwsArgumentError,
      );
    });
  });

  group('a storage buffer handle', () {
    test('host readability is read from the usage', () {
      // Mutation: `hostReadable` stored from its own parameter answers false
      // for a backend that set the usage bit alone, and `readBuffer` refuses
      // a buffer that was made to be read.
      final buffer = wrapStorageBuffer(
        backend: Object(),
        lengthInBytes: 16,
        usage: BufferUsage.standardStorage | BufferUsage.hostReadable,
      );
      expect(buffer.hostReadable, isTrue);
    });

    test('the pre-1.0 bool alone still sets the usage bit', () {
      final buffer = wrapStorageBuffer(
        backend: Object(),
        lengthInBytes: 16,
        hostReadable: true,
      );
      expect(buffer.usage.contains(BufferUsage.hostReadable), isTrue);
      expect(buffer.usage.contains(BufferUsage.storage), isTrue);
      final plain = wrapStorageBuffer(backend: Object(), lengthInBytes: 16);
      expect(plain.hostReadable, isFalse);
      expect(plain.usage, BufferUsage.standardStorage);
    });

    test('a bool and a usage that disagree are refused', () {
      expect(
        () => wrapStorageBuffer(
          backend: Object(),
          lengthInBytes: 16,
          hostReadable: true,
          usage: BufferUsage.standardStorage,
        ),
        throwsArgumentError,
      );
    });
  });
}
