/// Filtering and addressing: how a sampler reads a texture, translated to and
/// from flutter_gpu's vocabulary, plus the cache that keeps [SamplerDescriptor]
/// from allocating a native object on every bind.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'gpu_refusal.dart' show impellerRefusal;

/// Maps the engine's [MinMagFilter] to its `package:flutter_gpu` equivalent.
extension MinMagFilterToGpu on MinMagFilter {
  /// Returns flutter_gpu's min/mag filter of the same name. Throws a
  /// [DeviceResourceException] for a value flutter_gpu has none for.
  gpu.MinMagFilter toGpu() => switch (this) {
    MinMagFilter.nearest => gpu.MinMagFilter.nearest,
    MinMagFilter.linear => gpu.MinMagFilter.linear,
    _ => throw impellerRefusal('toGpu', 'flutter_gpu has no filter for $this'),
  };
}

/// Maps `package:flutter_gpu`'s min/mag filter back to the engine's
/// [MinMagFilter].
extension MinMagFilterFromGpu on gpu.MinMagFilter {
  /// Returns the engine's min/mag filter of the same name; every value has one.
  MinMagFilter toEngine() => switch (this) {
    gpu.MinMagFilter.nearest => MinMagFilter.nearest,
    gpu.MinMagFilter.linear => MinMagFilter.linear,
  };
}

/// Maps the engine's [MipFilter] to its `package:flutter_gpu` equivalent.
extension MipFilterToGpu on MipFilter {
  /// Returns flutter_gpu's mip filter of the same name. Throws a
  /// [DeviceResourceException] for a value flutter_gpu has none for.
  gpu.MipFilter toGpu() => switch (this) {
    MipFilter.nearest => gpu.MipFilter.nearest,
    MipFilter.linear => gpu.MipFilter.linear,
    _ => throw impellerRefusal(
      'toGpu',
      'flutter_gpu has no mip filter for $this',
    ),
  };
}

/// Maps `package:flutter_gpu`'s mip filter back to the engine's [MipFilter].
extension MipFilterFromGpu on gpu.MipFilter {
  /// Returns the engine's mip filter of the same name; every value has one.
  MipFilter toEngine() => switch (this) {
    gpu.MipFilter.nearest => MipFilter.nearest,
    gpu.MipFilter.linear => MipFilter.linear,
  };
}

/// Maps the engine's [SamplerAddressMode] to its `package:flutter_gpu`
/// equivalent.
extension SamplerAddressModeToGpu on SamplerAddressMode {
  /// Returns flutter_gpu's address mode of the same name. Throws a
  /// [DeviceResourceException] for `clampToBorder`, which flutter_gpu lacks,
  /// and for any other value it has none for.
  gpu.SamplerAddressMode toGpu() => switch (this) {
    SamplerAddressMode.clampToEdge => gpu.SamplerAddressMode.clampToEdge,
    SamplerAddressMode.repeat => gpu.SamplerAddressMode.repeat,
    SamplerAddressMode.mirror => gpu.SamplerAddressMode.mirror,
    // Not reached through a bind: the encoder refuses a border axis by
    // `DeviceFeature.samplerBorderColor` before a sampler is made.
    SamplerAddressMode.clampToBorder => throw impellerRefusal(
      'toGpu',
      'flutter_gpu has no clamp-to-border address mode',
    ),
    _ => throw impellerRefusal(
      'toGpu',
      'flutter_gpu has no address mode for $this',
    ),
  };
}

/// Maps `package:flutter_gpu`'s address mode back to the engine's
/// [SamplerAddressMode].
extension SamplerAddressModeFromGpu on gpu.SamplerAddressMode {
  /// Returns the engine's address mode of the same name; every value has one.
  SamplerAddressMode toEngine() => switch (this) {
    gpu.SamplerAddressMode.clampToEdge => SamplerAddressMode.clampToEdge,
    gpu.SamplerAddressMode.repeat => SamplerAddressMode.repeat,
    gpu.SamplerAddressMode.mirror => SamplerAddressMode.mirror,
  };
}

/// flutter_gpu sampler objects, one per distinct description.
///
/// `bindTexture` is called several times per draw and there are hundreds of
/// draws in a frame, but the engine only ever uses a handful of distinct
/// samplers. Building a fresh `gpu.SamplerOptions` per bind would allocate for
/// nothing; [SamplerDescriptor] is immutable and has value equality precisely so
/// this map can exist.
///
/// It evicts only when told to, by `GraphicsDevice.releaseSampler`
/// ([forgetGpuSampler]), and does not otherwise need to: five enum fields of two, two, two,
/// three and three values bound the isotropic samplers at seventy-two entries
/// however many models a session loads, and the anisotropy field — an integer
/// the engine only ever sets from `min(8, maxAnisotropy)` or a setting —
/// multiplies that by the handful of levels anything asks for. Sharing one
/// object between call sites is safe too — `bindTexture` reads the fields
/// into integers on every call and retains nothing.
final Map<SamplerDescriptor, gpu.SamplerOptions> _samplerCache =
    <SamplerDescriptor, gpu.SamplerOptions>{};

/// Drops the cached options for [sampler] — `GraphicsDevice.releaseSampler`
/// on this backend. The next bind of an equal description builds them again.
void forgetGpuSampler(SamplerDescriptor sampler) =>
    _samplerCache.remove(sampler);

/// How many descriptions the cache holds, for a test.
int get debugGpuSamplerCount => _samplerCache.length;

/// Maps [SamplerDescriptor] to its `package:flutter_gpu` equivalent, served from
/// the cache above rather than built per call — see the note on the cache.
extension SamplerOptionsToGpu on SamplerDescriptor {
  /// Returns the cached flutter_gpu options for this description, building and
  /// caching them on the first call. Throws as the field translations do for a
  /// value flutter_gpu has none for.
  gpu.SamplerOptions toGpu() => _samplerCache[this] ??= gpu.SamplerOptions(
    minFilter: minFilter.toGpu(),
    magFilter: magFilter.toGpu(),
    mipFilter: mipFilter.toGpu(),
    widthAddressMode: widthAddressMode.toGpu(),
    heightAddressMode: heightAddressMode.toGpu(),
    // Not clamped here: flutter_gpu clamps to `maxSamplerAnisotropy` inside
    // `bindTexture`, and a value it has already promised to clamp is not
    // one this layer has to second-guess. The linear-filter requirement is
    // the engine's own constructor's, asserted before this is ever reached.
    maxAnisotropy: anisotropy,
  );
}

/// Maps `package:flutter_gpu`'s sampler options back to the engine's
/// [SamplerDescriptor], built fresh each call — the cache above is keyed the
/// other way.
///
/// `maxAnisotropy` comes across only where the engine's constructor would
/// accept it — all three filters linear. flutter_gpu's options are mutable
/// and check nothing when built, so a nearest filter beside `maxAnisotropy:
/// 8` is a value that exists and that its `bindTexture` then throws on; a
/// conversion is not the place for that throw, and one tap is the only
/// sampler such options can describe without it.
extension SamplerOptionsFromGpu on gpu.SamplerOptions {
  /// Returns a new descriptor with every field translated back, keeping
  /// `maxAnisotropy` only when all three filters are linear.
  SamplerDescriptor toEngine() => SamplerDescriptor(
    minFilter: minFilter.toEngine(),
    magFilter: magFilter.toEngine(),
    mipFilter: mipFilter.toEngine(),
    widthAddressMode: widthAddressMode.toEngine(),
    heightAddressMode: heightAddressMode.toEngine(),
    anisotropy: _isTrilinear ? maxAnisotropy : 1,
  );

  bool get _isTrilinear =>
      minFilter == gpu.MinMagFilter.linear &&
      magFilter == gpu.MinMagFilter.linear &&
      mipFilter == gpu.MipFilter.linear;
}
