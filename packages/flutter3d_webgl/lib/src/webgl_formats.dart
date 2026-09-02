/// Translation between the engine's vocabulary and WebGL2's constants.
///
/// The counterpart to `flutter3d_impeller`'s `gpu_formats.dart`, and written to the
/// same rule: one `switch` per enum, no `default`, so a value added to the HAL
/// is a compile error here rather than a wrong picture on one backend only.
///
/// Where a value has no WebGL2 equivalent it throws rather than degrading. A
/// silent fallback is the defect this project has been bitten by repeatedly: it
/// compiles, it runs, and it renders wrong only for the scenes that use it.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:web/web.dart' as web;

/// The comparison function, as `gl.depthFunc` wants it.
int compareFunctionToGl(CompareFunction f) => switch (f) {
  CompareFunction.never => web.WebGLRenderingContext.NEVER,
  CompareFunction.always => web.WebGLRenderingContext.ALWAYS,
  CompareFunction.less => web.WebGLRenderingContext.LESS,
  CompareFunction.equal => web.WebGLRenderingContext.EQUAL,
  CompareFunction.lessEqual => web.WebGLRenderingContext.LEQUAL,
  CompareFunction.greater => web.WebGLRenderingContext.GREATER,
  CompareFunction.notEqual => web.WebGLRenderingContext.NOTEQUAL,
  CompareFunction.greaterEqual => web.WebGLRenderingContext.GEQUAL,
};

/// Which faces the rasteriser discards.
///
/// Null means culling is switched off entirely — `gl.disable(CULL_FACE)` —
/// because WebGL has no "cull nothing" face constant.
int? cullModeToGl(CullMode mode) => switch (mode) {
  CullMode.none => null,
  CullMode.frontFace => web.WebGLRenderingContext.FRONT,
  CullMode.backFace => web.WebGLRenderingContext.BACK,
};

int windingOrderToGl(WindingOrder order) => switch (order) {
  WindingOrder.clockwise => web.WebGLRenderingContext.CW,
  WindingOrder.counterClockwise => web.WebGLRenderingContext.CCW,
};

int primitiveTypeToGl(PrimitiveType type) => switch (type) {
  PrimitiveType.triangle => web.WebGLRenderingContext.TRIANGLES,
  PrimitiveType.triangleStrip => web.WebGLRenderingContext.TRIANGLE_STRIP,
  PrimitiveType.line => web.WebGLRenderingContext.LINES,
  PrimitiveType.lineStrip => web.WebGLRenderingContext.LINE_STRIP,
  PrimitiveType.point => web.WebGLRenderingContext.POINTS,
};

int blendFactorToGl(BlendFactor factor) => switch (factor) {
  BlendFactor.zero => web.WebGLRenderingContext.ZERO,
  BlendFactor.one => web.WebGLRenderingContext.ONE,
  BlendFactor.sourceColor => web.WebGLRenderingContext.SRC_COLOR,
  BlendFactor.oneMinusSourceColor =>
    web.WebGLRenderingContext.ONE_MINUS_SRC_COLOR,
  BlendFactor.sourceAlpha => web.WebGLRenderingContext.SRC_ALPHA,
  BlendFactor.oneMinusSourceAlpha =>
    web.WebGLRenderingContext.ONE_MINUS_SRC_ALPHA,
  BlendFactor.destinationColor => web.WebGLRenderingContext.DST_COLOR,
  BlendFactor.oneMinusDestinationColor =>
    web.WebGLRenderingContext.ONE_MINUS_DST_COLOR,
  BlendFactor.destinationAlpha => web.WebGLRenderingContext.DST_ALPHA,
  BlendFactor.oneMinusDestinationAlpha =>
    web.WebGLRenderingContext.ONE_MINUS_DST_ALPHA,
  BlendFactor.sourceAlphaSaturated =>
    web.WebGLRenderingContext.SRC_ALPHA_SATURATE,
  BlendFactor.blendColor => web.WebGLRenderingContext.CONSTANT_COLOR,
  BlendFactor.oneMinusBlendColor =>
    web.WebGLRenderingContext.ONE_MINUS_CONSTANT_COLOR,
  BlendFactor.blendAlpha => web.WebGLRenderingContext.CONSTANT_ALPHA,
  BlendFactor.oneMinusBlendAlpha =>
    web.WebGLRenderingContext.ONE_MINUS_CONSTANT_ALPHA,
};

int blendOperationToGl(BlendOperation op) => switch (op) {
  BlendOperation.add => web.WebGLRenderingContext.FUNC_ADD,
  BlendOperation.subtract => web.WebGLRenderingContext.FUNC_SUBTRACT,
  BlendOperation.reverseSubtract =>
    web.WebGLRenderingContext.FUNC_REVERSE_SUBTRACT,
};

int indexTypeToGl(IndexType type) => switch (type) {
  IndexType.int16 => web.WebGLRenderingContext.UNSIGNED_SHORT,
  IndexType.int32 => web.WebGLRenderingContext.UNSIGNED_INT,
};

/// Bytes per index, for turning a count into a buffer length.
int indexSizeInBytes(IndexType type) => switch (type) {
  IndexType.int16 => 2,
  IndexType.int32 => 4,
};

/// The sized internal format for `texStorage2D`.
///
/// Depth formats map to the nearest WebGL2 has: there is no `d24s8` under that
/// name, it is `DEPTH24_STENCIL8`, and `d32FloatS8UInt` is
/// `DEPTH32F_STENCIL8`. `s8UInt` alone is a renderbuffer-only format on WebGL2
/// and this engine never asks for one, so it throws rather than pretending.
int textureFormatToGl(TextureFormat format) => switch (format) {
  TextureFormat.r8UNormInt => web.WebGL2RenderingContext.R8,
  TextureFormat.r8g8UNormInt => web.WebGL2RenderingContext.RG8,
  TextureFormat.r8g8b8a8UNormInt => web.WebGL2RenderingContext.RGBA8,
  TextureFormat.r8g8b8a8UNormIntSRGB => web.WebGL2RenderingContext.SRGB8_ALPHA8,
  TextureFormat.r32g32b32a32Float => web.WebGL2RenderingContext.RGBA32F,
  TextureFormat.r16g16b16a16Float => web.WebGL2RenderingContext.RGBA16F,
  TextureFormat.d24UnormS8Uint => web.WebGL2RenderingContext.DEPTH24_STENCIL8,
  TextureFormat.d32FloatS8UInt => web.WebGL2RenderingContext.DEPTH32F_STENCIL8,
  TextureFormat.r32Float => web.WebGL2RenderingContext.R32F,
  // Deliberately unsupported, and loudly. `a8` and `b8g8r8a8` have no sized
  // internal format in WebGL2 — the byte order is fixed at RGBA. A backend
  // that quietly substituted RGBA8 for BGRA8 would swap red and blue in
  // every texture it touched.
  //
  // The compressed formats are a different kind of no, and a narrower one
  // than it looks: they throw *here* because this function is for
  // `texStorage2D`'s sized internal format, and a compressed format is never
  // a valid render target or a plain `texSubImage2D` upload — the same
  // refusal Impeller's own `enableRenderTargetUsage` gives them. An actual
  // compressed-texture upload goes through `compressedTextureFormatToGl`
  // instead, which resolves the same values against whatever extensions the
  // context has, rather than refusing them all unconditionally.
  TextureFormat.unknown ||
  TextureFormat.a8UNormInt ||
  TextureFormat.b8g8r8a8UNormInt ||
  TextureFormat.b8g8r8a8UNormIntSRGB ||
  TextureFormat.s8UInt ||
  TextureFormat.bc1RGBAUNormInt ||
  TextureFormat.bc1RGBAUNormIntSRGB ||
  TextureFormat.bc3RGBAUNormInt ||
  TextureFormat.bc3RGBAUNormIntSRGB ||
  TextureFormat.bc5RGUNormInt ||
  TextureFormat.bc7RGBAUNormInt ||
  TextureFormat.bc7RGBAUNormIntSRGB ||
  TextureFormat.etc2RGB8UNormInt ||
  TextureFormat.etc2RGB8UNormIntSRGB ||
  TextureFormat.etc2RGBA8UNormInt ||
  TextureFormat.etc2RGBA8UNormIntSRGB ||
  TextureFormat.astc4x4LDR ||
  TextureFormat.astc4x4LDRSRGB ||
  TextureFormat.astc8x8LDR ||
  TextureFormat.astc8x8LDRSRGB ||
  TextureFormat.astc4x4HDR ||
  TextureFormat.astc8x8HDR => throw UnsupportedError(
    'WebGL2 has no sized internal format for TextureFormat.${format.name}. '
    'If the engine needs it, the HAL needs a capability query rather than '
    'this backend needs a substitute.',
  ),
};

/// The filter, as `gl.texParameteri` wants it.
int minMagFilterToGl(MinMagFilter filter) => switch (filter) {
  MinMagFilter.nearest => web.WebGLRenderingContext.NEAREST,
  MinMagFilter.linear => web.WebGLRenderingContext.LINEAR,
};

/// The minification filter, with the mip filter folded in the way GL wants.
///
/// **GL puts the mip filter on the minification filter, and a plain `LINEAR`
/// samples the base level alone whatever level a shader asks for.** That is
/// the specification, not a driver: with `NEAREST` or `LINEAR` as the min
/// filter, mipmapping is off and `textureLod` picks between magnification and
/// minification and nothing else. So a sampler whose [mip] is
/// [MipFilter.linear] has to become `LINEAR_MIPMAP_LINEAR` here, or a
/// prefiltered cube — every level of which is a different roughness — reads
/// as a mirror at every roughness.
///
/// [MipFilter.nearest] is left as the plain filter rather than turned into
/// `*_MIPMAP_NEAREST`, and deliberately: it is the default on every sampler
/// the engine binds, thirty-four recorded pictures were drawn with the base
/// level under it, and the one texture that wants a level chosen asks for
/// the linear mip filter and says so.
int minFilterToGl(MinMagFilter filter, MipFilter mip) =>
    switch ((filter, mip)) {
      (MinMagFilter.nearest, MipFilter.linear) =>
        web.WebGLRenderingContext.NEAREST_MIPMAP_LINEAR,
      (MinMagFilter.linear, MipFilter.linear) =>
        web.WebGLRenderingContext.LINEAR_MIPMAP_LINEAR,
      (final MinMagFilter plain, MipFilter.nearest) => minMagFilterToGl(plain),
    };

int addressModeToGl(SamplerAddressMode mode) => switch (mode) {
  SamplerAddressMode.clampToEdge => web.WebGLRenderingContext.CLAMP_TO_EDGE,
  SamplerAddressMode.repeat => web.WebGLRenderingContext.REPEAT,
  SamplerAddressMode.mirror => web.WebGLRenderingContext.MIRRORED_REPEAT,
};

/// Whether WebGL2 can draw this polygon mode at all.
///
/// **It cannot draw [PolygonMode.line].** `glPolygonMode` does not exist in
/// OpenGL ES, and so not in WebGL: wireframe there means drawing line
/// primitives from a different index buffer, which is a decision for the
/// renderer and not a substitution a backend may make silently. The engine uses
/// it for `RenderSettings.wireframe`.
///
/// Returned as a question rather than thrown at the call site, because the
/// engine sets a polygon mode on every pass whether or not it wants wireframe.
/// Throwing would take down the ninety-nine percent case for the one percent.
bool canDrawPolygonMode(PolygonMode mode) => switch (mode) {
  PolygonMode.fill => true,
  PolygonMode.line => false,
};

/// Which compressed-texture extensions this context's [getExtension] answered
/// for, queried once when the device is made.
///
/// **A query every real WebGL2 implementation answers, and it is still made.**
/// ETC2 is mandated by the OpenGL ES 3.0 core WebGL2 is built on, so
/// [etc2] is `true` everywhere in practice — but WebGL still requires calling
/// `getExtension` to unlock a format's tokens for `compressedTexImage2D`
/// regardless of what the underlying hardware guarantees, so skipping the
/// call would be assuming a WebGL-specific formality away rather than
/// answering a real question.
///
/// The other five vary by platform: [s3tc] (BC1/BC3) and [s3tcSrgb] are near-
/// universal on desktop and near-absent on mobile GPUs; [astc] is the
/// reverse; [rgtc] (BC5) and [bptc] (BC7) are newer and the least reliably
/// present of the six.
final class CompressedTextureSupport {
  const CompressedTextureSupport({
    required this.etc2,
    required this.s3tc,
    required this.s3tcSrgb,
    required this.rgtc,
    required this.bptc,
    required this.astc,
  });

  final bool etc2;
  final bool s3tc;
  final bool s3tcSrgb;
  final bool rgtc;
  final bool bptc;
  final bool astc;

  factory CompressedTextureSupport.query(web.WebGL2RenderingContext gl) =>
      CompressedTextureSupport(
        etc2: gl.getExtension('WEBGL_compressed_texture_etc') != null,
        s3tc: gl.getExtension('WEBGL_compressed_texture_s3tc') != null,
        s3tcSrgb: gl.getExtension('WEBGL_compressed_texture_s3tc_srgb') != null,
        rgtc: gl.getExtension('EXT_texture_compression_rgtc') != null,
        bptc: gl.getExtension('EXT_texture_compression_bptc') != null,
        astc: gl.getExtension('WEBGL_compressed_texture_astc') != null,
      );
}

/// The WebGL2 internal format for a compressed [format], given what
/// [support] actually has — or a thrown, named refusal for the one it
/// needs.
///
/// **Numbers from the Khronos WebGL extension registry, not derived.**
/// `package:web` (1.1.1) generates typed constants for
/// `WEBGL_compressed_texture_{etc,s3tc,s3tc_srgb,astc}`, used below by name;
/// it generates none for `EXT_texture_compression_rgtc` (BC5) or
/// `EXT_texture_compression_bptc` (BC7), so those two are the literal
/// `GLenum` values from each extension's `extension.xml` in
/// `KhronosGroup/WebGL` — `COMPRESSED_RED_GREEN_RGTC2_EXT = 0x8DBD` and
/// `COMPRESSED_RGBA_BPTC_UNORM_EXT` / `COMPRESSED_SRGB_ALPHA_BPTC_UNORM_EXT`
/// = `0x8E8C` / `0x8E8D`.
///
/// Thrown rather than returning null, for the same reason [textureFormatToGl]
/// does: a silent substitution is unavailable here (there is no
/// almost-as-good compressed format to fall back to) and a silent *failure*
/// is the one this whole function exists to replace with a message naming
/// exactly which extension is missing.
int compressedTextureFormatToGl(
  TextureFormat format,
  CompressedTextureSupport support,
) {
  int need(bool has, String extension, int glEnum) {
    if (!has) {
      throw UnsupportedError(
        'TextureFormat.${format.name} needs the WebGL2 extension '
        '"$extension", which this context does not have.',
      );
    }
    return glEnum;
  }

  return switch (format) {
    TextureFormat.bc1RGBAUNormInt => need(
      support.s3tc,
      'WEBGL_compressed_texture_s3tc',
      web.WEBGL_compressed_texture_s3tc.COMPRESSED_RGBA_S3TC_DXT1_EXT,
    ),
    TextureFormat.bc1RGBAUNormIntSRGB => need(
      support.s3tcSrgb,
      'WEBGL_compressed_texture_s3tc_srgb',
      web
          .WEBGL_compressed_texture_s3tc_srgb
          .COMPRESSED_SRGB_ALPHA_S3TC_DXT1_EXT,
    ),
    TextureFormat.bc3RGBAUNormInt => need(
      support.s3tc,
      'WEBGL_compressed_texture_s3tc',
      web.WEBGL_compressed_texture_s3tc.COMPRESSED_RGBA_S3TC_DXT5_EXT,
    ),
    TextureFormat.bc3RGBAUNormIntSRGB => need(
      support.s3tcSrgb,
      'WEBGL_compressed_texture_s3tc_srgb',
      web
          .WEBGL_compressed_texture_s3tc_srgb
          .COMPRESSED_SRGB_ALPHA_S3TC_DXT5_EXT,
    ),
    // EXT_texture_compression_rgtc: no package:web binding, see the doc
    // comment above.
    TextureFormat.bc5RGUNormInt => need(
      support.rgtc,
      'EXT_texture_compression_rgtc',
      0x8DBD,
    ),
    // EXT_texture_compression_bptc: no package:web binding, see the doc
    // comment above.
    TextureFormat.bc7RGBAUNormInt => need(
      support.bptc,
      'EXT_texture_compression_bptc',
      0x8E8C,
    ),
    TextureFormat.bc7RGBAUNormIntSRGB => need(
      support.bptc,
      'EXT_texture_compression_bptc',
      0x8E8D,
    ),
    TextureFormat.etc2RGB8UNormInt => need(
      support.etc2,
      'WEBGL_compressed_texture_etc',
      web.WEBGL_compressed_texture_etc.COMPRESSED_RGB8_ETC2,
    ),
    TextureFormat.etc2RGB8UNormIntSRGB => need(
      support.etc2,
      'WEBGL_compressed_texture_etc',
      web.WEBGL_compressed_texture_etc.COMPRESSED_SRGB8_ETC2,
    ),
    TextureFormat.etc2RGBA8UNormInt => need(
      support.etc2,
      'WEBGL_compressed_texture_etc',
      web.WEBGL_compressed_texture_etc.COMPRESSED_RGBA8_ETC2_EAC,
    ),
    TextureFormat.etc2RGBA8UNormIntSRGB => need(
      support.etc2,
      'WEBGL_compressed_texture_etc',
      web.WEBGL_compressed_texture_etc.COMPRESSED_SRGB8_ALPHA8_ETC2_EAC,
    ),
    TextureFormat.astc4x4LDR => need(
      support.astc,
      'WEBGL_compressed_texture_astc',
      web.WEBGL_compressed_texture_astc.COMPRESSED_RGBA_ASTC_4x4_KHR,
    ),
    TextureFormat.astc4x4LDRSRGB => need(
      support.astc,
      'WEBGL_compressed_texture_astc',
      web.WEBGL_compressed_texture_astc.COMPRESSED_SRGB8_ALPHA8_ASTC_4x4_KHR,
    ),
    TextureFormat.astc8x8LDR => need(
      support.astc,
      'WEBGL_compressed_texture_astc',
      web.WEBGL_compressed_texture_astc.COMPRESSED_RGBA_ASTC_8x8_KHR,
    ),
    TextureFormat.astc8x8LDRSRGB => need(
      support.astc,
      'WEBGL_compressed_texture_astc',
      web.WEBGL_compressed_texture_astc.COMPRESSED_SRGB8_ALPHA8_ASTC_8x8_KHR,
    ),
    // WebGL has no ASTC HDR extension — `WEBGL_compressed_texture_astc` is
    // LDR-only, and nothing else exposes the profile.
    TextureFormat.astc4x4HDR ||
    TextureFormat.astc8x8HDR => throw UnsupportedError(
      'TextureFormat.${format.name}: WebGL2 has no ASTC HDR extension.',
    ),
    _ => throw ArgumentError(
      'TextureFormat.${format.name} is not compressed; '
      'textureFormatToGl is for this.',
    ),
  };
}
