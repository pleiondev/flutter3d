/// Filtering and addressing: how a sampler reads a texture, translated to and
/// from flutter_gpu's vocabulary, plus the cache that keeps [SamplerOptions]
/// from allocating a native object on every bind.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

extension MinMagFilterToGpu on MinMagFilter {
  gpu.MinMagFilter toGpu() => switch (this) {
        MinMagFilter.nearest => gpu.MinMagFilter.nearest,
        MinMagFilter.linear => gpu.MinMagFilter.linear,
      };
}

extension MinMagFilterFromGpu on gpu.MinMagFilter {
  MinMagFilter toEngine() => switch (this) {
        gpu.MinMagFilter.nearest => MinMagFilter.nearest,
        gpu.MinMagFilter.linear => MinMagFilter.linear,
      };
}

extension MipFilterToGpu on MipFilter {
  gpu.MipFilter toGpu() => switch (this) {
        MipFilter.nearest => gpu.MipFilter.nearest,
        MipFilter.linear => gpu.MipFilter.linear,
      };
}

extension MipFilterFromGpu on gpu.MipFilter {
  MipFilter toEngine() => switch (this) {
        gpu.MipFilter.nearest => MipFilter.nearest,
        gpu.MipFilter.linear => MipFilter.linear,
      };
}

extension SamplerAddressModeToGpu on SamplerAddressMode {
  gpu.SamplerAddressMode toGpu() => switch (this) {
        SamplerAddressMode.clampToEdge => gpu.SamplerAddressMode.clampToEdge,
        SamplerAddressMode.repeat => gpu.SamplerAddressMode.repeat,
        SamplerAddressMode.mirror => gpu.SamplerAddressMode.mirror,
      };
}

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

extension SamplerOptionsToGpu on SamplerOptions {
  gpu.SamplerOptions toGpu() => _samplerCache[this] ??= gpu.SamplerOptions(
        minFilter: minFilter.toGpu(),
        magFilter: magFilter.toGpu(),
        mipFilter: mipFilter.toGpu(),
        widthAddressMode: widthAddressMode.toGpu(),
        heightAddressMode: heightAddressMode.toGpu(),
      );
}

extension SamplerOptionsFromGpu on gpu.SamplerOptions {
  SamplerOptions toEngine() => SamplerOptions(
        minFilter: minFilter.toEngine(),
        magFilter: magFilter.toEngine(),
        mipFilter: mipFilter.toEngine(),
        widthAddressMode: widthAddressMode.toEngine(),
        heightAddressMode: heightAddressMode.toEngine(),
      );
}
