/// What flutter_gpu can do, as one [DeviceFeatures] set, one [DeviceLimits]
/// and a [TextureFormatSupport] per format.
///
/// **Every answer here is either a flutter_gpu query or a statement about what
/// its Dart API exposes**, and each "no" names what flutter_gpu lacks at the
/// place it is decided. The legacy `supportsX` getters read these through
/// `DeviceCapabilityForwarders`, and each of them answers exactly what it
/// answered before 1.0.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

import 'gpu_formats.dart';

/// The name this backend refuses in, as `UnsupportedCapability.backend`.
const String impellerBackendName = 'Impeller';

/// The features flutter_gpu exposes on the running context.
///
/// [cubesWork] is the probe `GpuRenderBackend` makes, because flutter_gpu
/// reports no capability for cube textures.
DeviceFeatures impellerFeatures({required bool cubesWork}) {
  final context = gpu.gpuContext;
  return DeviceFeatures(<DeviceFeature>[
    // flutter_gpu's own answer.
    if (context.doesSupportOffscreenMSAA) DeviceFeature.offscreenMultisample,
    // blendConstant: not a property of the hardware — Metal and Vulkan both
    // have the constant — but of what flutter_gpu exposes, which is no setter
    // for it. See `GpuCommandEncoder.setBlendColor`, and the refusal in
    // `setBlend` that this absence promises.
    // TODO(impeller): flutter_gpu's RenderPass has no blend-constant setter
    // (no `InternalFlutterGpu_RenderPass_SetBlendColor`) — unblocked by an
    // upstream RenderPass.setBlendConstant.
    if (context.doesSupportManuallyMippedTextures) DeviceFeature.manualMipmaps,
    if (cubesWork) DeviceFeature.cubeTextures,
    // flutter_gpu's own answer: true on Metal and Vulkan, false on its OpenGL
    // ES path, where a `ColorAttachment.mipLevel` other than zero is refused.
    // A cube *face* is attachable everywhere — the same capability's note
    // says so — which is why this gates the probe's chain and not the probe.
    if (context.doesSupportFramebufferRenderMipmap)
      DeviceFeature.renderToMipLevel,
    // Impeller exposes glPolygonMode's equivalent, so the request goes
    // through.
    DeviceFeature.wireframe,
    // alphaToCoverage — `P7`: flutter_gpu exposes no alpha-to-coverage and
    // no sample mask.
    // TODO(impeller): no alpha-to-coverage in flutter_gpu's pipeline state —
    // unblocked by an upstream RenderPass/pipeline alpha-to-coverage flag.
    //
    // flutter_gpu's depth-stencil format is documented never to be
    // depth-only, so a device that names one has a stencil beside its depth;
    // one that answers `unknown` has neither, and the x-ray stage stays off.
    if (context.defaultDepthStencilFormat != gpu.PixelFormat.unknown)
      DeviceFeature.stencil,
    // gpuTimestamps, timestampQuery, occlusionQuery, pipelineStatisticsQuery:
    // TODO(impeller): flutter_gpu has no query objects of any kind — no timer,
    // occlusion or statistics query — unblocked by an upstream query-set API.
    //
    // compute and everything that needs it (storage, indirect dispatch):
    // TODO(impeller): flutter_gpu has no compute pipeline — unblocked by
    // flutter/flutter#188480 (the shape follows #188474).
    //
    // float32Filterable / float32Renderable / float32Blendable: flutter_gpu
    // answers `supportsTextureFormat` true for every uncompressed format
    // without asking the device, so it has no per-format answer to give.
    // TODO(impeller): unblocked by a per-format capability query in
    // flutter_gpu (filterable / renderable / blendable per PixelFormat).
    //
    // `R8`: flutter_gpu takes a `colorAttachmentIndex` on both blend setters,
    // and `GpuCommandEncoder.setBlend` has always passed the index through.
    DeviceFeature.independentBlend,
    // The 1.0 surface flutter_gpu genuinely offers.
    //
    // `createTexture` and `writeTexture`: `CommandBuffer
    // .copyBufferToTexture` takes any region of any level of any slice.
    DeviceFeature.textureWrites,
    // `createBuffer` and `writeBuffer`: a host-visible `DeviceBuffer`,
    // overwritten and flushed in place.
    DeviceFeature.buffers,
    // `RenderPass.draw` is a draw with no index buffer.
    DeviceFeature.nonIndexedDraw,
    // `multiDraw` is a loop of `drawIndexed`, which the contract allows.
    DeviceFeature.multiDraw,
    // `RenderPass.bindUniform` takes a buffer view of laid-out bytes.
    DeviceFeature.uniformBytes,
    // Per family, flutter_gpu's own answer.
    if (context.supportsTextureCompression(gpu.TextureCompressionFamily.bc))
      DeviceFeature.textureCompressionBC,
    if (context.supportsTextureCompression(gpu.TextureCompressionFamily.etc2))
      DeviceFeature.textureCompressionETC2,
    if (context.supportsTextureCompression(gpu.TextureCompressionFamily.astc))
      DeviceFeature.textureCompressionASTC,
    if (context.supportsTextureCompression(
      gpu.TextureCompressionFamily.astcHdr,
    ))
      DeviceFeature.textureCompressionASTCHdr,
    // `A2.8`: clip depth is `[0, 1]` on every flutter_gpu path — impellerc
    // turns it round for OpenGL ES itself — so what decides whether a
    // reversed projection gains anything is the depth format the context
    // chose. A float on Metal; on Vulkan whatever the driver offers, and on
    // the OpenGL ES path 24 fixed bits, where it would gain nothing.
    if (context.defaultDepthStencilFormat == gpu.PixelFormat.d32FloatS8UInt)
      DeviceFeature.reversedDepth,
    // Everything else is absent, and each call it gates refuses with a
    // TODO(impeller) at the refusal: array, 3D and cube-array textures and
    // rendering into a layer (flutter_gpu's TextureType is 2D, 2D
    // multisample, cube and external only); buffer-to-buffer copies, texture
    // copies past level 0 slice 0 and texture-to-buffer copies whose buffer
    // nothing can read; storage textures and buffers; indirect and
    // multi-indirect draws; depth bias, colour write masks and depth clamp
    // (no RenderPass setter for any of them); min/max and dual-source blend;
    // comparison, LOD-clamped and border samplers (flutter_gpu's
    // SamplerDescriptor has none of the three); mapped buffers and synchronous
    // readback (a DeviceBuffer has no read path); render bundles; a base
    // vertex or first instance; rg11b10 rendering; and the shader-language
    // features, which impellerc reports nothing about.
  ]);
}

/// The limits flutter_gpu reports or implies on the running context.
///
/// Where flutter_gpu publishes nothing, the WebGPU default stands — the
/// floor a portable caller may already assume — except for what this backend
/// cannot do at all, which is zero (or one, for "one layer").
DeviceLimits impellerLimits({required bool renderToMip, required bool msaa}) =>
    DeviceLimits(
      // No 3D and no array textures — see `impellerFeatures`.
      maxTextureDimension3D: 0,
      maxTextureArrayLayers: 1,
      // Four where this backend is not on its OpenGL ES path, one where it is
      // — `gfx-50n`, `L5`.
      //
      // **Inferred, and that is stated rather than hidden.** flutter_gpu
      // publishes no MRT capability and no backend name, so there is nothing
      // here to ask directly. `doesSupportFramebufferRenderMipmap` is the
      // closest published fact: flutter_gpu's own documentation says it is
      // true on Metal and Vulkan and false on the OpenGL ES path, which is
      // the same split the attachment limit falls on.
      //
      // **A probe is not available**, and this is the unusual part. Every
      // other uncertain capability in this backend is settled by trying it
      // and catching — see `_probeCubes`. Trying a second attachment on GLES
      // reaches an `FML_CHECK`, so the probe that would answer the question
      // is the same call that ends the process. An inference from a
      // neighbouring capability is what is left.
      //
      // Four where it is not, which is the floor both allow — Metal eight,
      // Vulkan's `maxColorAttachments` at least four on every conformant
      // device. Until `L5` this said two, because two was all the engine had
      // ever opened; the albedo buffer is a third, and the number published
      // is now what the two APIs guarantee rather than what the engine
      // happened to use.
      maxColorAttachments: renderToMip ? 4 : 1,
      // Four is the count this engine's goldens were recorded with, and the
      // one flutter_gpu's offscreen MSAA is built around.
      maxSampleCount: msaa ? 4 : 1,
      // flutter_gpu's own answer: sixteen on every Metal and Vulkan device
      // this has run on, and one where the driver has no anisotropic sampler.
      // A sampler asking for more than this is clamped inside `bindTexture`,
      // which is flutter_gpu's documented behaviour and not a courtesy of
      // this layer.
      maxSamplerAnisotropy: gpu.gpuContext.maxSamplerAnisotropy,
      // No storage of either kind — see `impellerFeatures`.
      maxStorageBuffersPerShaderStage: 0,
      maxStorageTexturesPerShaderStage: 0,
      maxStorageBufferBindingSize: 0,
      // flutter_gpu's own answer, which the transient allocators also round
      // every write to.
      minUniformBufferOffsetAlignment:
          gpu.gpuContext.minimumUniformByteAlignment,
      minStorageBufferOffsetAlignment: 256,
      // `RenderPass._kMaxVertexBufferSlots`, which flutter_gpu keeps equal to
      // `impeller::kMaxVertexBuffers`.
      maxVertexBuffers: 16,
      // No compute.
      maxComputeWorkgroupStorageSize: 0,
      maxComputeInvocationsPerWorkgroup: 0,
      maxComputeWorkgroupSizeX: 0,
      maxComputeWorkgroupSizeY: 0,
      maxComputeWorkgroupSizeZ: 0,
      maxComputeWorkgroupsPerDimension: 0,
    );

/// What [format] can be used for, from flutter_gpu's own answers.
///
/// `sampled` is `gpuContext.supportsTextureFormat` — flutter_gpu's own
/// answer, which is per compression family underneath: BC on a desktop GPU,
/// ETC2 and ASTC on a mobile one, all three on Apple silicon, and its
/// `formats.dart` says to ask before allocating. An uncompressed format is a
/// yes today because the capability surface does not vary by format there;
/// that is flutter_gpu's statement, and this repeats it rather than restating
/// it as a table of its own. The other uses follow from the format and from
/// [features]; a 32-bit float format is neither filterable nor renderable
/// here, for the reason `impellerFeatures` gives.
TextureFormatSupport impellerFormatSupport(
  TextureFormat format,
  DeviceFeatures features,
) {
  // TODO(impeller): the nineteen `extendedTextureFormats` have no
  // flutter_gpu PixelFormat — unblocked when flutter_gpu gains them.
  if (!format.isMirrored) return TextureFormatSupport.none;
  final pixel = format.toGpu();
  final sampled = gpu.gpuContext.supportsTextureFormat(pixel);
  if (!sampled) return TextureFormatSupport.none;
  final float32 =
      format == TextureFormat.r32Float ||
      format == TextureFormat.r32g32b32a32Float;
  final color = !format.isDepthOrStencil && !format.isCompressed;
  final renderable =
      color &&
      !float32 &&
      gpu.gpuContext.supportsTextureFormat(pixel, renderTarget: true);
  final depthStencil =
      format.isDepthOrStencil &&
      gpu.gpuContext.supportsTextureFormat(pixel, renderTarget: true);
  final msaa = features.has(DeviceFeature.offscreenMultisample);
  return TextureFormatSupport(
    sampled: true,
    filterable: !format.isDepthOrStencil && !format.isInteger && !float32,
    renderable: renderable,
    blendable: renderable && !format.isInteger,
    multisample: msaa && (renderable || depthStencil),
    resolve: msaa && renderable,
    depthStencil: depthStencil,
  );
}
