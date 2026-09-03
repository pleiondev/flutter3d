/// Pass and pipeline state — load and store actions, rasteriser and blend
/// settings — translated to flutter_gpu's vocabulary.
///
/// Write-only, so no reverse mapping here: nothing in this engine ever reads
/// this state back off a device. See the library comment on
/// `gpu_formats.dart`.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

/// Maps the engine's [LoadAction] to its `package:flutter_gpu` equivalent.
extension LoadActionToGpu on LoadAction {
  gpu.LoadAction toGpu() => switch (this) {
    LoadAction.dontCare => gpu.LoadAction.dontCare,
    LoadAction.load => gpu.LoadAction.load,
    LoadAction.clear => gpu.LoadAction.clear,
  };
}

/// Maps the engine's [StoreAction] to its `package:flutter_gpu` equivalent.
extension StoreActionToGpu on StoreAction {
  gpu.StoreAction toGpu() => switch (this) {
    StoreAction.dontCare => gpu.StoreAction.dontCare,
    StoreAction.store => gpu.StoreAction.store,
    StoreAction.multisampleResolve => gpu.StoreAction.multisampleResolve,
    StoreAction.storeAndMultisampleResolve =>
      gpu.StoreAction.storeAndMultisampleResolve,
  };
}

/// Maps the engine's [PrimitiveType] to its `package:flutter_gpu` equivalent.
extension PrimitiveTypeToGpu on PrimitiveType {
  gpu.PrimitiveType toGpu() => switch (this) {
    PrimitiveType.triangle => gpu.PrimitiveType.triangle,
    PrimitiveType.triangleStrip => gpu.PrimitiveType.triangleStrip,
    PrimitiveType.line => gpu.PrimitiveType.line,
    PrimitiveType.lineStrip => gpu.PrimitiveType.lineStrip,
    PrimitiveType.point => gpu.PrimitiveType.point,
  };
}

/// Maps the engine's [CullMode] to its `package:flutter_gpu` equivalent.
extension CullModeToGpu on CullMode {
  gpu.CullMode toGpu() => switch (this) {
    CullMode.none => gpu.CullMode.none,
    CullMode.frontFace => gpu.CullMode.frontFace,
    CullMode.backFace => gpu.CullMode.backFace,
  };
}

/// Maps the engine's [WindingOrder] to its `package:flutter_gpu` equivalent.
extension WindingOrderToGpu on WindingOrder {
  gpu.WindingOrder toGpu() => switch (this) {
    WindingOrder.clockwise => gpu.WindingOrder.clockwise,
    WindingOrder.counterClockwise => gpu.WindingOrder.counterClockwise,
  };
}

/// Maps the engine's [PolygonMode] to its `package:flutter_gpu` equivalent.
extension PolygonModeToGpu on PolygonMode {
  gpu.PolygonMode toGpu() => switch (this) {
    PolygonMode.fill => gpu.PolygonMode.fill,
    PolygonMode.line => gpu.PolygonMode.line,
  };
}

/// Maps the engine's [CompareFunction] to its `package:flutter_gpu`
/// equivalent.
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

/// Maps the engine's [StencilOperation] to its `package:flutter_gpu`
/// equivalent.
extension StencilOperationToGpu on StencilOperation {
  gpu.StencilOperation toGpu() => switch (this) {
    StencilOperation.keep => gpu.StencilOperation.keep,
    StencilOperation.zero => gpu.StencilOperation.zero,
    StencilOperation.setToReferenceValue =>
      gpu.StencilOperation.setToReferenceValue,
    StencilOperation.incrementClamp => gpu.StencilOperation.incrementClamp,
    StencilOperation.decrementClamp => gpu.StencilOperation.decrementClamp,
    StencilOperation.invert => gpu.StencilOperation.invert,
    StencilOperation.incrementWrap => gpu.StencilOperation.incrementWrap,
    StencilOperation.decrementWrap => gpu.StencilOperation.decrementWrap,
  };
}

/// Maps the engine's [StencilFace] to its `package:flutter_gpu` equivalent.
extension StencilFaceToGpu on StencilFace {
  gpu.StencilFace toGpu() => switch (this) {
    StencilFace.both => gpu.StencilFace.both,
    StencilFace.front => gpu.StencilFace.front,
    StencilFace.back => gpu.StencilFace.back,
  };
}

/// Maps the engine's [StencilState] to a `package:flutter_gpu`
/// `StencilConfig`, field for field.
///
/// A fresh object per call rather than a cache like the sampler's: the x-ray
/// stage sets this a handful of times per frame, not hundreds, and
/// `setStencilConfig` reads the fields out at once rather than holding the
/// object.
extension StencilStateToGpu on StencilState {
  gpu.StencilConfig toGpu() => gpu.StencilConfig(
    compareFunction: compare.toGpu(),
    stencilFailureOperation: failOp.toGpu(),
    depthFailureOperation: depthFailOp.toGpu(),
    depthStencilPassOperation: passOp.toGpu(),
    readMask: readMask,
    writeMask: writeMask,
  );
}

/// Maps the engine's [BlendFactor] to its `package:flutter_gpu` equivalent.
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
    BlendFactor.sourceAlphaSaturated => gpu.BlendFactor.sourceAlphaSaturated,
    BlendFactor.blendColor => gpu.BlendFactor.blendColor,
    BlendFactor.oneMinusBlendColor => gpu.BlendFactor.oneMinusBlendColor,
    BlendFactor.blendAlpha => gpu.BlendFactor.blendAlpha,
    BlendFactor.oneMinusBlendAlpha => gpu.BlendFactor.oneMinusBlendAlpha,
  };
}

/// Maps the engine's [BlendOperation] to its `package:flutter_gpu` equivalent.
extension BlendOperationToGpu on BlendOperation {
  gpu.BlendOperation toGpu() => switch (this) {
    BlendOperation.add => gpu.BlendOperation.add,
    BlendOperation.subtract => gpu.BlendOperation.subtract,
    BlendOperation.reverseSubtract => gpu.BlendOperation.reverseSubtract,
  };
}
