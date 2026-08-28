/// Filtering and addressing: how a sampler reads a texture, translated to and
/// from flutter_gpu's vocabulary, plus the cache that keeps [SamplerOptions]
/// from allocating a native object on every bind.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

/// Maps the engine's [MinMagFilter] to its `package:flutter_gpu` equivalent.
extension MinMagFilterToGpu on MinMagFilter {
  gpu.MinMagFilter toGpu() => switch (this) {
    MinMagFilter.nearest => gpu.MinMagFilter.nearest,
    MinMagFilter.linear => gpu.MinMagFilter.linear,
  };
}

/// Maps `package:flutter_gpu`'s min/mag filter back to the engine's
/// [MinMagFilter].
extension MinMagFilterFromGpu on gpu.MinMagFilter {
  MinMagFilter toEngine() => switch (this) {
    gpu.MinMagFilter.nearest => MinMagFilter.nearest,
    gpu.MinMagFilter.linear => MinMagFilter.linear,
  };
}

/// Maps the engine's [MipFilter] to its `package:flutter_gpu` equivalent.
extension MipFilterToGpu on MipFilter {
  gpu.MipFilter toGpu() => switch (this) {
    MipFilter.nearest => gpu.MipFilter.nearest,
    MipFilter.linear => gpu.MipFilter.linear,
  };
}

/// Maps `package:flutter_gpu`'s mip filter back to the engine's [MipFilter].
extension MipFilterFromGpu on gpu.MipFilter {
  MipFilter toEngine() => switch (this) {
    gpu.MipFilter.nearest => MipFilter.nearest,
    gpu.MipFilter.linear => MipFilter.linear,
  };
}

/// Maps the engine's [SamplerAddressMode] to its `package:flutter_gpu`
/// equivalent.
extension SamplerAddressModeToGpu on SamplerAddressMode {
  gpu.SamplerAddressMode toGpu() => switch (this) {
    SamplerAddressMode.clampToEdge => gpu.SamplerAddressMode.clampToEdge,
    SamplerAddressMode.repeat => gpu.SamplerAddressMode.repeat,
    SamplerAddressMode.mirror => gpu.SamplerAddressMode.mirror,
  };
}

/// Maps `package:flutter_gpu`'s address mode back to the engine's
/// [SamplerAddressMode].
extension SamplerAddressModeFromGpu on gpu.SamplerAddressMode {
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
/// nothing; [SamplerOptions] is immutable and has value equality precisely so
/// this map can exist.
///
/// It never evicts and does not need to: five enum fields of two, two, two,
/// three and three values bound it at seventy-two entries however many models a
/// session loads. Sharing one object between call sites is safe too —
/// `bindTexture` reads the fields into integers on every call and retains
/// nothing.
final Map<SamplerOptions, gpu.SamplerOptions> _samplerCache =
    <SamplerOptions, gpu.SamplerOptions>{};

/// Maps [SamplerOptions] to its `package:flutter_gpu` equivalent, served from
/// the cache above rather than built per call — see the note on the cache.
extension SamplerOptionsToGpu on SamplerOptions {
  gpu.SamplerOptions toGpu() => _samplerCache[this] ??= gpu.SamplerOptions(
    minFilter: minFilter.toGpu(),
    magFilter: magFilter.toGpu(),
    mipFilter: mipFilter.toGpu(),
    widthAddressMode: widthAddressMode.toGpu(),
    heightAddressMode: heightAddressMode.toGpu(),
  );
}

/// Maps `package:flutter_gpu`'s sampler options back to the engine's
/// [SamplerOptions], built fresh each call — the cache above is keyed the
/// other way.
extension SamplerOptionsFromGpu on gpu.SamplerOptions {
  SamplerOptions toEngine() => SamplerOptions(
    minFilter: minFilter.toEngine(),
    magFilter: magFilter.toEngine(),
    mipFilter: mipFilter.toEngine(),
    widthAddressMode: widthAddressMode.toEngine(),
    heightAddressMode: heightAddressMode.toEngine(),
  );
}
