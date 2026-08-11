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

import 'package:flutter3d_graphics/flutter3d_graphics.dart';
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
      // Deliberately unsupported, and loudly. `a8` and `b8g8r8a8` have no sized
      // internal format in WebGL2 — the byte order is fixed at RGBA — and the
      // XR formats are Apple's. A backend that quietly substituted RGBA8 for
      // BGRA8 would swap red and blue in every texture it touched.
      TextureFormat.unknown ||
      TextureFormat.a8UNormInt ||
      TextureFormat.b8g8r8a8UNormInt ||
      TextureFormat.b8g8r8a8UNormIntSRGB ||
      TextureFormat.b10g10r10XR ||
      TextureFormat.b10g10r10XRSRGB ||
      TextureFormat.b10g10r10a10XR ||
      TextureFormat.s8UInt =>
        throw UnsupportedError(
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
