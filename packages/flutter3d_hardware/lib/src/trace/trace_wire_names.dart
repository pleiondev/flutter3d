/// The words a trace writes for each value of the HAL's enums.
///
/// **Explicit, so a rename cannot change a file.** A trace used to write a
/// value's Dart name (`.name`) and read it back with `byName`. The day an
/// identifier is renamed — wave 4 renames for spelling and units — every
/// trace written before would stop reading, and every trace written after
/// would say something a released build does not know. Each table below
/// holds the words as they were on the day traces went 1.0; a value renamed
/// in Dart keeps its word here, and a value added gets a new entry.
library;

import '../formats.dart';
import '../geometry_buffer.dart';
import '../sampler.dart';
import '../vertex_layout_spec.dart';
import 'trace_format_exception.dart';

/// A value's word in a file, and the value a word stands for.
final class WireNames<T extends Object> {
  const WireNames(this.what, this._words);

  /// What the values are, for a message: `TextureFormat`.
  final String what;

  final Map<T, String> _words;

  /// [value]'s word. Throws a [StateError] for a value nobody gave one,
  /// which is a value added to the type without its entry here.
  String write(T value) =>
      _words[value] ??
      (throw StateError(
        '$what.$value has no word in the trace format: add it to its table '
        'in trace_wire_names.dart',
      ));

  /// The value [word] stands for. Throws a [TraceFormatException] naming
  /// [what] and the word when no value does.
  T read(Object? word) {
    for (final MapEntry(:key, :value) in _words.entries) {
      if (value == word) return key;
    }
    throw TraceFormatException(
      'a trace names $what "$word", which this build has no value for',
    );
  }
}

/// [BlendOperation] in a trace.
const WireNames<BlendOperation> blendOperationWire =
    WireNames<BlendOperation>('BlendOperation', <BlendOperation, String>{
      BlendOperation.add: 'add',
      BlendOperation.subtract: 'subtract',
      BlendOperation.reverseSubtract: 'reverseSubtract',
      BlendOperation.min: 'min',
      BlendOperation.max: 'max',
    });

/// [BlendFactor] in a trace.
const WireNames<BlendFactor> blendFactorWire =
    WireNames<BlendFactor>('BlendFactor', <BlendFactor, String>{
      BlendFactor.zero: 'zero',
      BlendFactor.one: 'one',
      BlendFactor.sourceColor: 'sourceColor',
      BlendFactor.oneMinusSourceColor: 'oneMinusSourceColor',
      BlendFactor.sourceAlpha: 'sourceAlpha',
      BlendFactor.oneMinusSourceAlpha: 'oneMinusSourceAlpha',
      BlendFactor.destinationColor: 'destinationColor',
      BlendFactor.oneMinusDestinationColor: 'oneMinusDestinationColor',
      BlendFactor.destinationAlpha: 'destinationAlpha',
      BlendFactor.oneMinusDestinationAlpha: 'oneMinusDestinationAlpha',
      BlendFactor.sourceAlphaSaturated: 'sourceAlphaSaturated',
      BlendFactor.blendColor: 'blendColor',
      BlendFactor.oneMinusBlendColor: 'oneMinusBlendColor',
      BlendFactor.blendAlpha: 'blendAlpha',
      BlendFactor.oneMinusBlendAlpha: 'oneMinusBlendAlpha',
      BlendFactor.source1Color: 'source1Color',
      BlendFactor.oneMinusSource1Color: 'oneMinusSource1Color',
      BlendFactor.source1Alpha: 'source1Alpha',
      BlendFactor.oneMinusSource1Alpha: 'oneMinusSource1Alpha',
    });

/// [CompareFunction] in a trace.
const WireNames<CompareFunction> compareFunctionWire =
    WireNames<CompareFunction>('CompareFunction', <CompareFunction, String>{
      CompareFunction.never: 'never',
      CompareFunction.always: 'always',
      CompareFunction.less: 'less',
      CompareFunction.equal: 'equal',
      CompareFunction.lessEqual: 'lessEqual',
      CompareFunction.greater: 'greater',
      CompareFunction.notEqual: 'notEqual',
      CompareFunction.greaterEqual: 'greaterEqual',
    });

/// [StencilOperation] in a trace.
const WireNames<StencilOperation> stencilOperationWire =
    WireNames<StencilOperation>('StencilOperation', <StencilOperation, String>{
      StencilOperation.keep: 'keep',
      StencilOperation.zero: 'zero',
      StencilOperation.setToReferenceValue: 'setToReferenceValue',
      StencilOperation.incrementClamp: 'incrementClamp',
      StencilOperation.decrementClamp: 'decrementClamp',
      StencilOperation.invert: 'invert',
      StencilOperation.incrementWrap: 'incrementWrap',
      StencilOperation.decrementWrap: 'decrementWrap',
    });

/// [MinMagFilter] in a trace.
const WireNames<MinMagFilter> minMagFilterWire = WireNames<MinMagFilter>(
  'MinMagFilter',
  <MinMagFilter, String>{
    MinMagFilter.nearest: 'nearest',
    MinMagFilter.linear: 'linear',
  },
);

/// [MipFilter] in a trace.
const WireNames<MipFilter> mipFilterWire = WireNames<MipFilter>(
  'MipFilter',
  <MipFilter, String>{MipFilter.nearest: 'nearest', MipFilter.linear: 'linear'},
);

/// [SamplerAddressMode] in a trace.
const WireNames<SamplerAddressMode> samplerAddressModeWire =
    WireNames<SamplerAddressMode>(
      'SamplerAddressMode',
      <SamplerAddressMode, String>{
        SamplerAddressMode.clampToEdge: 'clampToEdge',
        SamplerAddressMode.repeat: 'repeat',
        SamplerAddressMode.mirror: 'mirror',
      },
    );

/// [SamplerBorderColor] in a trace.
const WireNames<SamplerBorderColor> samplerBorderColorWire =
    WireNames<SamplerBorderColor>(
      'SamplerBorderColor',
      <SamplerBorderColor, String>{
        SamplerBorderColor.transparentBlack: 'transparentBlack',
        SamplerBorderColor.opaqueBlack: 'opaqueBlack',
        SamplerBorderColor.opaqueWhite: 'opaqueWhite',
      },
    );

/// [TextureFormat] in a trace.
const WireNames<TextureFormat> textureFormatWire =
    WireNames<TextureFormat>('TextureFormat', <TextureFormat, String>{
      TextureFormat.unknown: 'unknown',
      TextureFormat.a8UNormInt: 'a8UNormInt',
      TextureFormat.r8UNormInt: 'r8UNormInt',
      TextureFormat.r8g8UNormInt: 'r8g8UNormInt',
      TextureFormat.r8g8b8a8UNormInt: 'r8g8b8a8UNormInt',
      TextureFormat.r8g8b8a8UNormIntSRGB: 'r8g8b8a8UNormIntSRGB',
      TextureFormat.b8g8r8a8UNormInt: 'b8g8r8a8UNormInt',
      TextureFormat.b8g8r8a8UNormIntSRGB: 'b8g8r8a8UNormIntSRGB',
      TextureFormat.r32g32b32a32Float: 'r32g32b32a32Float',
      TextureFormat.r16g16b16a16Float: 'r16g16b16a16Float',
      TextureFormat.r32Float: 'r32Float',
      TextureFormat.s8UInt: 's8UInt',
      TextureFormat.d24UnormS8Uint: 'd24UnormS8Uint',
      TextureFormat.d32FloatS8UInt: 'd32FloatS8UInt',
      TextureFormat.bc1RGBAUNormInt: 'bc1RGBAUNormInt',
      TextureFormat.bc1RGBAUNormIntSRGB: 'bc1RGBAUNormIntSRGB',
      TextureFormat.bc3RGBAUNormInt: 'bc3RGBAUNormInt',
      TextureFormat.bc3RGBAUNormIntSRGB: 'bc3RGBAUNormIntSRGB',
      TextureFormat.bc5RGUNormInt: 'bc5RGUNormInt',
      TextureFormat.bc7RGBAUNormInt: 'bc7RGBAUNormInt',
      TextureFormat.bc7RGBAUNormIntSRGB: 'bc7RGBAUNormIntSRGB',
      TextureFormat.etc2RGB8UNormInt: 'etc2RGB8UNormInt',
      TextureFormat.etc2RGB8UNormIntSRGB: 'etc2RGB8UNormIntSRGB',
      TextureFormat.etc2RGBA8UNormInt: 'etc2RGBA8UNormInt',
      TextureFormat.etc2RGBA8UNormIntSRGB: 'etc2RGBA8UNormIntSRGB',
      TextureFormat.astc4x4LDR: 'astc4x4LDR',
      TextureFormat.astc4x4LDRSRGB: 'astc4x4LDRSRGB',
      TextureFormat.astc8x8LDR: 'astc8x8LDR',
      TextureFormat.astc8x8LDRSRGB: 'astc8x8LDRSRGB',
      TextureFormat.astc4x4HDR: 'astc4x4HDR',
      TextureFormat.astc8x8HDR: 'astc8x8HDR',
      TextureFormat.r8g8b8a8SNormInt: 'r8g8b8a8SNormInt',
      TextureFormat.r8g8b8a8UInt: 'r8g8b8a8UInt',
      TextureFormat.r8g8b8a8SInt: 'r8g8b8a8SInt',
      TextureFormat.r16Float: 'r16Float',
      TextureFormat.r16g16Float: 'r16g16Float',
      TextureFormat.r16g16b16a16UInt: 'r16g16b16a16UInt',
      TextureFormat.r16g16b16a16SInt: 'r16g16b16a16SInt',
      TextureFormat.r32UInt: 'r32UInt',
      TextureFormat.r32SInt: 'r32SInt',
      TextureFormat.r32g32Float: 'r32g32Float',
      TextureFormat.r32g32UInt: 'r32g32UInt',
      TextureFormat.r32g32SInt: 'r32g32SInt',
      TextureFormat.r32g32b32a32UInt: 'r32g32b32a32UInt',
      TextureFormat.r32g32b32a32SInt: 'r32g32b32a32SInt',
      TextureFormat.r10g10b10a2UNormInt: 'r10g10b10a2UNormInt',
      TextureFormat.r11g11b10UFloat: 'r11g11b10UFloat',
      TextureFormat.r9g9b9e5UFloat: 'r9g9b9e5UFloat',
      TextureFormat.d16UNormInt: 'd16UNormInt',
      TextureFormat.d32Float: 'd32Float',
    });

/// [StorageMode] in a trace.
const WireNames<StorageMode> storageModeWire =
    WireNames<StorageMode>('StorageMode', <StorageMode, String>{
      StorageMode.hostVisible: 'hostVisible',
      StorageMode.devicePrivate: 'devicePrivate',
      StorageMode.deviceTransient: 'deviceTransient',
    });

/// [VertexStepMode] in a trace.
const WireNames<VertexStepMode> vertexStepModeWire = WireNames<VertexStepMode>(
  'VertexStepMode',
  <VertexStepMode, String>{
    VertexStepMode.vertex: 'vertex',
    VertexStepMode.instance: 'instance',
  },
);

/// [VertexFormat] in a trace.
const WireNames<VertexFormat> vertexFormatWire =
    WireNames<VertexFormat>('VertexFormat', <VertexFormat, String>{
      VertexFormat.float32: 'float32',
      VertexFormat.float32x2: 'float32x2',
      VertexFormat.float32x3: 'float32x3',
      VertexFormat.float32x4: 'float32x4',
      VertexFormat.uint32: 'uint32',
      VertexFormat.uint32x2: 'uint32x2',
      VertexFormat.uint32x3: 'uint32x3',
      VertexFormat.uint32x4: 'uint32x4',
      VertexFormat.sint32: 'sint32',
      VertexFormat.sint32x2: 'sint32x2',
      VertexFormat.sint32x3: 'sint32x3',
      VertexFormat.sint32x4: 'sint32x4',
    });

/// [GeometryUsage] in a trace.
const WireNames<GeometryUsage> geometryUsageWire = WireNames<GeometryUsage>(
  'GeometryUsage',
  <GeometryUsage, String>{
    GeometryUsage.vertices: 'vertices',
    GeometryUsage.indices: 'indices',
  },
);

/// [LoadAction] in a trace.
const WireNames<LoadAction> loadActionWire =
    WireNames<LoadAction>('LoadAction', <LoadAction, String>{
      LoadAction.dontCare: 'dontCare',
      LoadAction.load: 'load',
      LoadAction.clear: 'clear',
    });

/// [StoreAction] in a trace.
const WireNames<StoreAction> storeActionWire =
    WireNames<StoreAction>('StoreAction', <StoreAction, String>{
      StoreAction.dontCare: 'dontCare',
      StoreAction.store: 'store',
      StoreAction.multisampleResolve: 'multisampleResolve',
      StoreAction.storeAndMultisampleResolve: 'storeAndMultisampleResolve',
    });

/// [PrimitiveType] in a trace.
const WireNames<PrimitiveType> primitiveTypeWire =
    WireNames<PrimitiveType>('PrimitiveType', <PrimitiveType, String>{
      PrimitiveType.triangle: 'triangle',
      PrimitiveType.triangleStrip: 'triangleStrip',
      PrimitiveType.line: 'line',
      PrimitiveType.lineStrip: 'lineStrip',
      PrimitiveType.point: 'point',
    });

/// [CullMode] in a trace.
const WireNames<CullMode> cullModeWire =
    WireNames<CullMode>('CullMode', <CullMode, String>{
      CullMode.none: 'none',
      CullMode.frontFace: 'frontFace',
      CullMode.backFace: 'backFace',
    });

/// [WindingOrder] in a trace.
const WireNames<WindingOrder> windingOrderWire =
    WireNames<WindingOrder>('WindingOrder', <WindingOrder, String>{
      WindingOrder.clockwise: 'clockwise',
      WindingOrder.counterClockwise: 'counterClockwise',
    });

/// [PolygonMode] in a trace.
const WireNames<PolygonMode> polygonModeWire = WireNames<PolygonMode>(
  'PolygonMode',
  <PolygonMode, String>{PolygonMode.fill: 'fill', PolygonMode.line: 'line'},
);

/// [IndexType] in a trace.
const WireNames<IndexType> indexTypeWire = WireNames<IndexType>(
  'IndexType',
  <IndexType, String>{IndexType.int16: 'int16', IndexType.int32: 'int32'},
);
