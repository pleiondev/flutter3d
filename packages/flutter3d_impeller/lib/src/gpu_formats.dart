/// The one place the engine's graphics vocabulary becomes flutter_gpu's.
///
/// Every translation between `graphics/formats.dart` and `flutter_gpu` lives
/// here and nowhere else. If two files translated [CullMode], one of them would
/// eventually be wrong, and a wrong mapping is the quietest defect in this
/// codebase: it compiles, it runs, and it renders wrong only for the values a
/// scene happens to use.
///
/// ## Every switch here is an expression with no `default`
///
/// That is not a style preference. A Dart `switch` *expression* over an enum
/// must be exhaustive, so the analyser refuses to compile a mapping that misses
/// a value — which turns "somebody added a value and forgot the mapping" from a
/// silent wrong render into a build error. A `default` clause, a wildcard `_`
/// pattern, or a `switch` *statement* would each restore the silence. Do not
/// add one.
///
/// The analyser guards our own enums gaining a value.
/// `test/gpu_formats_test.dart` guards the other direction — flutter_gpu
/// gaining one — by comparing counts, and guards the mapping itself by
/// asserting that each value lands on the flutter_gpu value of the same name.
///
/// ## Reverse mappings exist only where something reads state back
///
/// Textures carry their storage mode and format, and the opaque texture handle
/// this backend hands out has to answer questions about them without naming
/// flutter_gpu. Pipeline and pass state — cull,
/// blend, depth compare, load and store — is only ever written, so a reverse
/// mapping for it would be code with no reader.
library;

import 'package:flutter3d_graphics/flutter3d_graphics.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

// -- Resource description ---------------------------------------------------

extension StorageModeToGpu on StorageMode {
  gpu.StorageMode toGpu() => switch (this) {
        StorageMode.hostVisible => gpu.StorageMode.hostVisible,
        StorageMode.devicePrivate => gpu.StorageMode.devicePrivate,
        StorageMode.deviceTransient => gpu.StorageMode.deviceTransient,
      };
}

extension StorageModeFromGpu on gpu.StorageMode {
  StorageMode toEngine() => switch (this) {
        gpu.StorageMode.hostVisible => StorageMode.hostVisible,
        gpu.StorageMode.devicePrivate => StorageMode.devicePrivate,
        gpu.StorageMode.deviceTransient => StorageMode.deviceTransient,
      };
}

extension TextureTypeToGpu on TextureType {
  gpu.TextureType toGpu() => switch (this) {
        TextureType.texture2D => gpu.TextureType.texture2D,
        TextureType.texture2DMultisample => gpu.TextureType.texture2DMultisample,
        TextureType.textureCube => gpu.TextureType.textureCube,
        TextureType.textureExternalOES => gpu.TextureType.textureExternalOES,
      };
}

extension TextureFormatToGpu on TextureFormat {
  gpu.PixelFormat toGpu() => switch (this) {
        TextureFormat.unknown => gpu.PixelFormat.unknown,
        TextureFormat.a8UNormInt => gpu.PixelFormat.a8UNormInt,
        TextureFormat.r8UNormInt => gpu.PixelFormat.r8UNormInt,
        TextureFormat.r8g8UNormInt => gpu.PixelFormat.r8g8UNormInt,
        TextureFormat.r8g8b8a8UNormInt => gpu.PixelFormat.r8g8b8a8UNormInt,
        TextureFormat.r8g8b8a8UNormIntSRGB =>
          gpu.PixelFormat.r8g8b8a8UNormIntSRGB,
        TextureFormat.b8g8r8a8UNormInt => gpu.PixelFormat.b8g8r8a8UNormInt,
        TextureFormat.b8g8r8a8UNormIntSRGB =>
          gpu.PixelFormat.b8g8r8a8UNormIntSRGB,
        TextureFormat.r32g32b32a32Float => gpu.PixelFormat.r32g32b32a32Float,
        TextureFormat.r16g16b16a16Float => gpu.PixelFormat.r16g16b16a16Float,
        TextureFormat.r32Float => gpu.PixelFormat.r32Float,
        TextureFormat.s8UInt => gpu.PixelFormat.s8UInt,
        TextureFormat.d24UnormS8Uint => gpu.PixelFormat.d24UnormS8Uint,
        TextureFormat.d32FloatS8UInt => gpu.PixelFormat.d32FloatS8UInt,
        TextureFormat.bc1RGBAUNormInt => gpu.PixelFormat.bc1RGBAUNormInt,
        TextureFormat.bc1RGBAUNormIntSRGB =>
          gpu.PixelFormat.bc1RGBAUNormIntSRGB,
        TextureFormat.bc3RGBAUNormInt => gpu.PixelFormat.bc3RGBAUNormInt,
        TextureFormat.bc3RGBAUNormIntSRGB =>
          gpu.PixelFormat.bc3RGBAUNormIntSRGB,
        TextureFormat.bc5RGUNormInt => gpu.PixelFormat.bc5RGUNormInt,
        TextureFormat.bc7RGBAUNormInt => gpu.PixelFormat.bc7RGBAUNormInt,
        TextureFormat.bc7RGBAUNormIntSRGB =>
          gpu.PixelFormat.bc7RGBAUNormIntSRGB,
        TextureFormat.etc2RGB8UNormInt => gpu.PixelFormat.etc2RGB8UNormInt,
        TextureFormat.etc2RGB8UNormIntSRGB =>
          gpu.PixelFormat.etc2RGB8UNormIntSRGB,
        TextureFormat.etc2RGBA8UNormInt => gpu.PixelFormat.etc2RGBA8UNormInt,
        TextureFormat.etc2RGBA8UNormIntSRGB =>
          gpu.PixelFormat.etc2RGBA8UNormIntSRGB,
        TextureFormat.astc4x4LDR => gpu.PixelFormat.astc4x4LDR,
        TextureFormat.astc4x4LDRSRGB => gpu.PixelFormat.astc4x4LDRSRGB,
        TextureFormat.astc8x8LDR => gpu.PixelFormat.astc8x8LDR,
        TextureFormat.astc8x8LDRSRGB => gpu.PixelFormat.astc8x8LDRSRGB,
        TextureFormat.astc4x4HDR => gpu.PixelFormat.astc4x4HDR,
        TextureFormat.astc8x8HDR => gpu.PixelFormat.astc8x8HDR,
      };
}

extension TextureFormatFromGpu on gpu.PixelFormat {
  TextureFormat toEngine() => switch (this) {
        gpu.PixelFormat.unknown => TextureFormat.unknown,
        gpu.PixelFormat.a8UNormInt => TextureFormat.a8UNormInt,
        gpu.PixelFormat.r8UNormInt => TextureFormat.r8UNormInt,
        gpu.PixelFormat.r8g8UNormInt => TextureFormat.r8g8UNormInt,
        gpu.PixelFormat.r8g8b8a8UNormInt => TextureFormat.r8g8b8a8UNormInt,
        gpu.PixelFormat.r8g8b8a8UNormIntSRGB =>
          TextureFormat.r8g8b8a8UNormIntSRGB,
        gpu.PixelFormat.b8g8r8a8UNormInt => TextureFormat.b8g8r8a8UNormInt,
        gpu.PixelFormat.b8g8r8a8UNormIntSRGB =>
          TextureFormat.b8g8r8a8UNormIntSRGB,
        gpu.PixelFormat.r32g32b32a32Float => TextureFormat.r32g32b32a32Float,
        gpu.PixelFormat.r16g16b16a16Float => TextureFormat.r16g16b16a16Float,
        gpu.PixelFormat.r32Float => TextureFormat.r32Float,
        gpu.PixelFormat.s8UInt => TextureFormat.s8UInt,
        gpu.PixelFormat.d24UnormS8Uint => TextureFormat.d24UnormS8Uint,
        gpu.PixelFormat.d32FloatS8UInt => TextureFormat.d32FloatS8UInt,
        gpu.PixelFormat.bc1RGBAUNormInt => TextureFormat.bc1RGBAUNormInt,
        gpu.PixelFormat.bc1RGBAUNormIntSRGB =>
          TextureFormat.bc1RGBAUNormIntSRGB,
        gpu.PixelFormat.bc3RGBAUNormInt => TextureFormat.bc3RGBAUNormInt,
        gpu.PixelFormat.bc3RGBAUNormIntSRGB =>
          TextureFormat.bc3RGBAUNormIntSRGB,
        gpu.PixelFormat.bc5RGUNormInt => TextureFormat.bc5RGUNormInt,
        gpu.PixelFormat.bc7RGBAUNormInt => TextureFormat.bc7RGBAUNormInt,
        gpu.PixelFormat.bc7RGBAUNormIntSRGB =>
          TextureFormat.bc7RGBAUNormIntSRGB,
        gpu.PixelFormat.etc2RGB8UNormInt => TextureFormat.etc2RGB8UNormInt,
        gpu.PixelFormat.etc2RGB8UNormIntSRGB =>
          TextureFormat.etc2RGB8UNormIntSRGB,
        gpu.PixelFormat.etc2RGBA8UNormInt => TextureFormat.etc2RGBA8UNormInt,
        gpu.PixelFormat.etc2RGBA8UNormIntSRGB =>
          TextureFormat.etc2RGBA8UNormIntSRGB,
        gpu.PixelFormat.astc4x4LDR => TextureFormat.astc4x4LDR,
        gpu.PixelFormat.astc4x4LDRSRGB => TextureFormat.astc4x4LDRSRGB,
        gpu.PixelFormat.astc8x8LDR => TextureFormat.astc8x8LDR,
        gpu.PixelFormat.astc8x8LDRSRGB => TextureFormat.astc8x8LDRSRGB,
        gpu.PixelFormat.astc4x4HDR => TextureFormat.astc4x4HDR,
        gpu.PixelFormat.astc8x8HDR => TextureFormat.astc8x8HDR,
      };
}

// -- Geometry ---------------------------------------------------------------

extension IndexTypeToGpu on IndexType {
  gpu.IndexType toGpu() => switch (this) {
        IndexType.int16 => gpu.IndexType.int16,
        IndexType.int32 => gpu.IndexType.int32,
      };
}

extension IndexTypeFromGpu on gpu.IndexType {
  IndexType toEngine() => switch (this) {
        gpu.IndexType.int16 => IndexType.int16,
        gpu.IndexType.int32 => IndexType.int32,
      };
}

// -- Sampling ---------------------------------------------------------------

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

// -- Pass and pipeline state ------------------------------------------------
//
// Write-only, so no reverse mapping. See the library comment.

extension LoadActionToGpu on LoadAction {
  gpu.LoadAction toGpu() => switch (this) {
        LoadAction.dontCare => gpu.LoadAction.dontCare,
        LoadAction.load => gpu.LoadAction.load,
        LoadAction.clear => gpu.LoadAction.clear,
      };
}

extension StoreActionToGpu on StoreAction {
  gpu.StoreAction toGpu() => switch (this) {
        StoreAction.dontCare => gpu.StoreAction.dontCare,
        StoreAction.store => gpu.StoreAction.store,
        StoreAction.multisampleResolve => gpu.StoreAction.multisampleResolve,
        StoreAction.storeAndMultisampleResolve =>
          gpu.StoreAction.storeAndMultisampleResolve,
      };
}

extension PrimitiveTypeToGpu on PrimitiveType {
  gpu.PrimitiveType toGpu() => switch (this) {
        PrimitiveType.triangle => gpu.PrimitiveType.triangle,
        PrimitiveType.triangleStrip => gpu.PrimitiveType.triangleStrip,
        PrimitiveType.line => gpu.PrimitiveType.line,
        PrimitiveType.lineStrip => gpu.PrimitiveType.lineStrip,
        PrimitiveType.point => gpu.PrimitiveType.point,
      };
}

extension CullModeToGpu on CullMode {
  gpu.CullMode toGpu() => switch (this) {
        CullMode.none => gpu.CullMode.none,
        CullMode.frontFace => gpu.CullMode.frontFace,
        CullMode.backFace => gpu.CullMode.backFace,
      };
}

extension WindingOrderToGpu on WindingOrder {
  gpu.WindingOrder toGpu() => switch (this) {
        WindingOrder.clockwise => gpu.WindingOrder.clockwise,
        WindingOrder.counterClockwise => gpu.WindingOrder.counterClockwise,
      };
}

extension PolygonModeToGpu on PolygonMode {
  gpu.PolygonMode toGpu() => switch (this) {
        PolygonMode.fill => gpu.PolygonMode.fill,
        PolygonMode.line => gpu.PolygonMode.line,
      };
}

extension CompareFunctionToGpu on CompareFunction {
  gpu.CompareFunction toGpu() => switch (this) {
        CompareFunction.never => gpu.CompareFunction.never,
        CompareFunction.always => gpu.CompareFunction.always,
        CompareFunction.less => gpu.CompareFunction.less,
        CompareFunction.equal => gpu.CompareFunction.equal,
        CompareFunction.lessEqual => gpu.CompareFunction.lessEqual,
        CompareFunction.greater => gpu.CompareFunction.greater,
        CompareFunction.notEqual => gpu.CompareFunction.notEqual,
        CompareFunction.greaterEqual => gpu.CompareFunction.greaterEqual,
      };
}

extension BlendFactorToGpu on BlendFactor {
  gpu.BlendFactor toGpu() => switch (this) {
        BlendFactor.zero => gpu.BlendFactor.zero,
        BlendFactor.one => gpu.BlendFactor.one,
        BlendFactor.sourceColor => gpu.BlendFactor.sourceColor,
        BlendFactor.oneMinusSourceColor => gpu.BlendFactor.oneMinusSourceColor,
        BlendFactor.sourceAlpha => gpu.BlendFactor.sourceAlpha,
        BlendFactor.oneMinusSourceAlpha => gpu.BlendFactor.oneMinusSourceAlpha,
        BlendFactor.destinationColor => gpu.BlendFactor.destinationColor,
        BlendFactor.oneMinusDestinationColor =>
          gpu.BlendFactor.oneMinusDestinationColor,
        BlendFactor.destinationAlpha => gpu.BlendFactor.destinationAlpha,
        BlendFactor.oneMinusDestinationAlpha =>
          gpu.BlendFactor.oneMinusDestinationAlpha,
        BlendFactor.sourceAlphaSaturated =>
          gpu.BlendFactor.sourceAlphaSaturated,
        BlendFactor.blendColor => gpu.BlendFactor.blendColor,
        BlendFactor.oneMinusBlendColor => gpu.BlendFactor.oneMinusBlendColor,
        BlendFactor.blendAlpha => gpu.BlendFactor.blendAlpha,
        BlendFactor.oneMinusBlendAlpha => gpu.BlendFactor.oneMinusBlendAlpha,
      };
}

extension BlendOperationToGpu on BlendOperation {
  gpu.BlendOperation toGpu() => switch (this) {
        BlendOperation.add => gpu.BlendOperation.add,
        BlendOperation.subtract => gpu.BlendOperation.subtract,
        BlendOperation.reverseSubtract => gpu.BlendOperation.reverseSubtract,
      };
}

// -- Vertex layouts ---------------------------------------------------------

extension VertexFormatToGpu on VertexFormat {
  gpu.VertexFormat toGpu() => switch (this) {
        VertexFormat.float32 => gpu.VertexFormat.float32,
        VertexFormat.float32x2 => gpu.VertexFormat.float32x2,
        VertexFormat.float32x3 => gpu.VertexFormat.float32x3,
        VertexFormat.float32x4 => gpu.VertexFormat.float32x4,
        VertexFormat.uint32 => gpu.VertexFormat.uint32,
        VertexFormat.uint32x2 => gpu.VertexFormat.uint32x2,
        VertexFormat.uint32x3 => gpu.VertexFormat.uint32x3,
        VertexFormat.uint32x4 => gpu.VertexFormat.uint32x4,
        VertexFormat.sint32 => gpu.VertexFormat.sint32,
        VertexFormat.sint32x2 => gpu.VertexFormat.sint32x2,
        VertexFormat.sint32x3 => gpu.VertexFormat.sint32x3,
        VertexFormat.sint32x4 => gpu.VertexFormat.sint32x4,
      };
}

extension VertexFormatFromGpu on gpu.VertexFormat {
  VertexFormat toEngine() => switch (this) {
        gpu.VertexFormat.float32 => VertexFormat.float32,
        gpu.VertexFormat.float32x2 => VertexFormat.float32x2,
        gpu.VertexFormat.float32x3 => VertexFormat.float32x3,
        gpu.VertexFormat.float32x4 => VertexFormat.float32x4,
        gpu.VertexFormat.uint32 => VertexFormat.uint32,
        gpu.VertexFormat.uint32x2 => VertexFormat.uint32x2,
        gpu.VertexFormat.uint32x3 => VertexFormat.uint32x3,
        gpu.VertexFormat.uint32x4 => VertexFormat.uint32x4,
        gpu.VertexFormat.sint32 => VertexFormat.sint32,
        gpu.VertexFormat.sint32x2 => VertexFormat.sint32x2,
        gpu.VertexFormat.sint32x3 => VertexFormat.sint32x3,
        gpu.VertexFormat.sint32x4 => VertexFormat.sint32x4,
      };
}

extension VertexStepModeToGpu on VertexStepMode {
  gpu.VertexStepMode toGpu() => switch (this) {
        VertexStepMode.vertex => gpu.VertexStepMode.vertex,
        VertexStepMode.instance => gpu.VertexStepMode.instance,
      };
}

extension VertexStepModeFromGpu on gpu.VertexStepMode {
  VertexStepMode toEngine() => switch (this) {
        gpu.VertexStepMode.vertex => VertexStepMode.vertex,
        gpu.VertexStepMode.instance => VertexStepMode.instance,
      };
}

/// The whole layout, which is a structure rather than an enum and so is
/// translated by construction rather than by a `switch`.
extension VertexLayoutSpecToGpu on VertexLayoutSpec {
  gpu.VertexLayout toGpu() => gpu.VertexLayout(
        buffers: <gpu.VertexBuffer>[
          for (final buffer in buffers)
            gpu.VertexBuffer(
              strideInBytes: buffer.strideInBytes,
              stepMode: buffer.stepMode.toGpu(),
              attributes: <gpu.VertexAttribute>[
                for (final attribute in buffer.attributes)
                  gpu.VertexAttribute(
                    name: attribute.name,
                    format: attribute.format.toGpu(),
                    offsetInBytes: attribute.offsetInBytes,
                  ),
              ],
            ),
        ],
      );
}
