/// A texture a Dart stage loads and stores texels of — a storage texture.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import 'cpu_texel_codec.dart';
import 'cpu_texture.dart';

/// One mip level of a texture, bound as a storage texture: what
/// `ComputeEncoder.bindStorageTexture` and `PassEncoder.bindStorageTexture`
/// hand a Dart stage, under the binding's name in `storageTextures`.
///
/// GLSL's `imageLoad` and `imageStore`, addressed by integer texel as they
/// are. **A store lands on what the format can hold** — clamped and rounded
/// to an eight-bit step, rounded to an integer, or to a half — because the
/// store underneath is four floats a texel whatever the format says, and a
/// stage writing 0.3 into an eight-bit texture would otherwise read back a
/// value no GPU could have kept. Out of range, a load reads nought and a
/// store does nothing, which is what robust access gives on hardware.
///
/// [access] is enforced: loading a write-only binding or storing into a
/// read-only one throws a [StateError], as a compiler would refuse it.
final class CpuStorageTexture {
  CpuStorageTexture(this.planes, this.format, this.access);

  /// Level [mipLevel] of [texture] as a storage binding, after every check
  /// the contract makes of one: the feature for [access], a format whose
  /// [support] says it may be stored to that way, and a texture made with
  /// `TextureUsage.storage`.
  factory CpuStorageTexture.bind(
    TextureHandle texture, {
    required int mipLevel,
    required StorageTextureAccess access,
    required DeviceFeatures features,
    required TextureFormatSupport support,
    required String backend,
  }) {
    features.require(
      DeviceFeature.storageTextures,
      backend: backend,
      reason: 'a storage texture binding needs it',
    );
    final readWrite = access == StorageTextureAccess.readWrite;
    if (readWrite) {
      features.require(
        DeviceFeature.readWriteStorageTextures,
        backend: backend,
        reason: 'a read-write storage texture binding needs it',
      );
    }
    if (!(readWrite ? support.storageReadWrite : support.storage)) {
      throw ArgumentError.value(
        texture.format,
        'texture.format',
        'cannot be bound as a ${access.name} storage texture here',
      );
    }
    if (!texture.usage.contains(TextureUsage.storage)) {
      throw ArgumentError.value(
        texture.usage,
        'texture.usage',
        'lacks TextureUsage.storage, which a storage texture binding needs',
      );
    }
    final cpu = texture.backend as CpuTexture;
    return CpuStorageTexture(
      <CpuTexture>[
        for (var z = 0; z < cpu.planeCount(mipLevel); z++)
          cpu.plane(mipLevel: mipLevel, z: z),
      ],
      texture.format,
      access,
    );
  }

  /// Every layer (or 3D slice) of the bound level, in order.
  final List<CpuTexture> planes;
  final TextureFormat format;
  final StorageTextureAccess access;

  int get width => planes.first.width;
  int get height => planes.first.height;

  /// Layers of an array, or slices of a 3D level; one otherwise.
  int get depth => planes.length;

  /// The texel at ([x], [y]) of layer or slice [z].
  Vector4 load(int x, int y, [int z = 0]) {
    if (access == StorageTextureAccess.writeOnly) {
      throw StateError('load from a write-only storage texture');
    }
    if (!_inside(x, y, z)) return Vector4.zero();
    final plane = planes[z];
    final at = (y * plane.width + x) * 4;
    final p = plane.pixels;
    return Vector4(p[at], p[at + 1], p[at + 2], p[at + 3]);
  }

  /// Writes [value] to ([x], [y]) of layer or slice [z], as [format] keeps
  /// it.
  void store(int x, int y, Vector4 value, [int z = 0]) {
    if (access == StorageTextureAccess.readOnly) {
      throw StateError('store into a read-only storage texture');
    }
    if (!_inside(x, y, z)) return;
    final plane = planes[z];
    final at = (y * plane.width + x) * 4;
    final p = plane.pixels;
    p[at] = value.x;
    p[at + 1] = value.y;
    p[at + 2] = value.z;
    p[at + 3] = value.w;
    settleTexel(format, p, at);
  }

  bool _inside(int x, int y, int z) =>
      z >= 0 &&
      z < planes.length &&
      x >= 0 &&
      y >= 0 &&
      x < width &&
      y < height;
}
