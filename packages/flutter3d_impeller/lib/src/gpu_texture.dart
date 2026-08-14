/// The flutter_gpu side of [TextureHandle]: where textures are made, and the
/// one place the object inside a handle is looked at.
///
/// The rest of the engine holds [TextureHandle] and never says `gpu.Texture`.
/// A pass that has to *use* one — as an attachment, or bound to a sampler slot
/// — reaches through [GpuTextureHandle.gpuTexture] at that line and nowhere
/// else.
library;

import 'package:flutter_gpu/gpu.dart' as gpu;

import 'package:flutter3d_graphics/flutter3d_graphics.dart';
import 'gpu_formats.dart';

/// Creates a flutter_gpu texture together with the single handle that will ever
/// stand for it.
///
/// **The only place in `lib/` that constructs a [TextureHandle].** That is what
/// makes the identity contract hold rather than merely be documented: this
/// returns the handle, the `gpu.Texture` never escapes as a value, and so no
/// call site is in a position to wrap one a second time. `identical()` on two
/// handles therefore answers the question callers actually mean.
///
/// The argument list mirrors `gpuContext.createTexture` — including its
/// defaults — so a call site that moves here reads the same. `textureType` is
/// left out: flutter_gpu infers it from [sampleCount], and nothing in this
/// engine wants a type the sample count does not already imply.
TextureHandle createGpuTexture(
  StorageMode storageMode,
  int width,
  int height, {
  TextureFormat format = TextureFormat.r8g8b8a8UNormInt,
  int sampleCount = 1,
  bool enableRenderTargetUsage = true,
  bool enableShaderReadUsage = true,
}) {
  final texture = gpu.gpuContext.createTexture(
    storageMode.toGpu(),
    width,
    height,
    format: format.toGpu(),
    sampleCount: sampleCount,
    enableRenderTargetUsage: enableRenderTargetUsage,
    enableShaderReadUsage: enableShaderReadUsage,
  );
  return TextureHandle(
    backend: texture,
    width: width,
    height: height,
    format: format,
    sampleCount: sampleCount,
    storageMode: storageMode,
  );
}

/// The colour format the device prefers, as an engine value.
///
/// A getter and not a constant on purpose: it is a runtime property of the
/// context, and the whole point of asking is that the answer differs by
/// platform. See `graphics/formats.dart`.
TextureFormat get defaultColorFormat =>
    gpu.gpuContext.defaultColorFormat.toEngine();

/// The depth/stencil format the device prefers, as an engine value.
///
/// Legitimately [TextureFormat.unknown] on a context that has none, which is
/// why it is not a constant either.
TextureFormat get defaultDepthStencilFormat =>
    gpu.gpuContext.defaultDepthStencilFormat.toEngine();

extension GpuTextureHandle on TextureHandle {
  /// The flutter_gpu texture behind this handle.
  ///
  /// Throws for a handle this backend did not make — a test's fake, or a second
  /// backend's — which is the right failure: it means a texture crossed from
  /// one backend into another's pass, and there is no picture to salvage.
  gpu.Texture get gpuTexture => backend as gpu.Texture;
}
