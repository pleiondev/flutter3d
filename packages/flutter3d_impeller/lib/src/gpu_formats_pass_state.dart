/// Pass and pipeline state — load and store actions, rasteriser and blend
/// settings — translated to flutter_gpu's vocabulary.
///
/// Write-only, so no reverse mapping here: nothing in this engine ever reads
/// this state back off a device. See the library comment on
/// `gpu_formats.dart`.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

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
