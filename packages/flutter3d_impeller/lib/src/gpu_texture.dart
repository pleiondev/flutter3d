/// The flutter_gpu side of [TextureHandle]: where textures are made, and the
/// one place the object inside a handle is looked at.
///
/// The rest of the engine holds [TextureHandle] and never says `gpu.Texture`.
/// A pass that has to *use* one — as an attachment, or bound to a sampler slot
/// — reaches through [GpuTextureHandle.gpuTexture] at that line and nowhere
/// else.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

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
/// defaults — so a call site that moves here reads the same.
///
/// [type] is passed through rather than inferred. flutter_gpu derives a
/// multisample type from [sampleCount] on its own, but a cube is not something
/// any other argument implies, and it changes what the texture *is*:
/// `gpu.Texture.sliceCount` becomes six, and `overwrite` starts taking a face
/// index. A cube also asks for [enableRenderTargetUsage] false at every call
/// site there is — nothing renders into a face, because `ColorTarget` has no
/// slice to render into.
TextureHandle createGpuTexture(
  StorageMode storageMode,
  int width,
  int height, {
  TextureFormat format = TextureFormat.r8g8b8a8UNormInt,
  int sampleCount = 1,
  bool enableRenderTargetUsage = true,
  bool enableShaderReadUsage = true,
  int mipLevelCount = 1,
  TextureType type = TextureType.texture2D,
}) {
  final texture = gpu.gpuContext.createTexture(
    storageMode.toGpu(),
    width,
    height,
    format: format.toGpu(),
    // Multisampling still decides the type when the caller has no opinion, and
    // that is not a nicety — passing a plain `texture2D` with a sample count
    // above one is a combination flutter_gpu refuses, and it refuses it as
    // "Texture creation failed" with nothing about which argument was wrong.
    // This line used to be absent for exactly that reason; a cube is the first
    // type no other argument implies, so the type is passed *and* the old
    // inference is kept.
    textureType: type == TextureType.texture2D && sampleCount > 1
        ? gpu.TextureType.texture2DMultisample
        : type.toGpu(),
    sampleCount: sampleCount,
    // Clamped to what the device will allocate. `fullMipCount` stops one short
    // of one-by-one, and asking for more than it throws — so the trim happens
    // here, where the limit is, rather than at every call site.
    mipLevelCount: mipLevelCount <= 1
        ? 1
        : (mipLevelCount < gpu.Texture.fullMipCount(width, height)
            ? mipLevelCount
            : gpu.Texture.fullMipCount(width, height)),
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
    type: type,
  );
}

/// The colour format the device prefers, as an engine value.
///
/// A runtime property of the context and not a constant, because the answer
/// differs by platform. See `graphics/formats.dart`.
///
/// **Asked once, because the context stops answering.** This was measured, and
/// it is a trap with a timer on it: `gpu.gpuContext.defaultColorFormat` reports
/// `b8g8r8a8UNormInt` for about a second after launch and `unknown` for the
/// rest of the process. Nothing else goes with it — the depth format and the
/// MSAA capability keep answering — so it does not read as a context that has
/// gone away.
///
/// Nothing noticed for as long as this repository held only games, and that is
/// luck rather than design: `Renderer._ensureTargets` reads this when it builds
/// the frame targets, which happens on the first frame and then only when the
/// window is resized. A game gets there in a few hundred milliseconds. The
/// fourth application here reads a level document off the disk first, and its
/// first frame arrives after the answer has gone — so every frame threw
/// `Texture creation failed` from a descriptor whose format was `unknown`, for
/// the life of the window, on a machine where the three games are fine.
///
/// So: the first answer is kept, and an `unknown` first answer becomes the one
/// format every Metal surface here has ever reported. The target this feeds is
/// an offscreen texture that becomes a `ui.Image`; it does not have to match a
/// swapchain, it has to be an eight-bit colour format that exists.
/// Named for the context rather than for the device, because the device has a
/// member of the same name and this is what it answers with.
TextureFormat get defaultColorFormatOfContext => _defaultColorFormat ??=
    colorFormatOrFallback(gpu.gpuContext.defaultColorFormat.toEngine());

TextureFormat? _defaultColorFormat;

/// Forgets the cached answer, so the next reader asks the context again.
///
/// **For tests, and it is not a nicety.** The cache above is process-wide and
/// written once, so without this the *first* test to touch a context decides
/// the colour format for every test that runs after it in the same process —
/// which makes the order of a test file part of what it asserts. A test that
/// passes alone and fails in a suite, or the reverse, is the most expensive
/// kind there is.
///
/// It is deliberately not called by anything in `lib/`: inside a running
/// application the whole point is that the answer is taken once, while the
/// context is still willing to give it.
void forgetDefaultColorFormat() => _defaultColorFormat = null;

/// What to use when the context reports [TextureFormat.unknown].
///
/// Separate from the reading so that it can be checked without a GPU: the
/// substitution is the part with a decision in it, and the part that would
/// otherwise only ever be exercised on a device, on the second of the two
/// seconds the context is willing to answer.
///
/// `b8g8r8a8UNormInt` is the one format every Metal surface here has ever
/// reported. What it feeds is an offscreen texture that becomes a `ui.Image`;
/// it does not have to match a swapchain, it has to be an eight-bit colour
/// format that exists.
TextureFormat colorFormatOrFallback(TextureFormat reported) =>
    reported == TextureFormat.unknown
        ? TextureFormat.b8g8r8a8UNormInt
        : reported;

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
