/// The slice of WebGPU one triangle needs, as `dart:js_interop` declarations.
///
/// **Hand-written because there is nothing to import.** `package:web` is
/// generated from the same IDL as everything else a browser has, and for WebGPU
/// it stops at the flag constants — `GPUBufferUsage`, `GPUTextureUsage`,
/// `GPUShaderStage` and their siblings are there and every interface is not. So
/// a backend on this API starts by writing its own bindings, which is a fact
/// about the cost of the fourth backend rather than about the contract: it is
/// mechanical, it is a few hundred lines, and none of it is a decision.
///
/// Only what this spike calls is declared. An interface here with a method
/// missing is not an omission to be fixed on sight — see the package's own
/// README for what a spike is and is not.
///
/// Descriptors are object-literal constructors rather than maps, so a misspelt
/// member is a compile error instead of a browser refusing a dictionary at run
/// time with a message naming a field nobody typed.
@JS()
library;

import 'dart:js_interop';

/// `navigator`, for the one property that says whether this browser has WebGPU
/// at all.
@JS('navigator')
external GpuNavigator get gpuNavigator;

/// The browser's `navigator`, for its `gpu` property.
extension type GpuNavigator._(JSObject _) implements JSObject {
  /// Null where the browser has no WebGPU, which is the answer a spike running
  /// in a headless test runner is most likely to get.
  external GPU? get gpu;
}

/// The WebGPU `GPU` interface, with only the members this spike calls.
extension type GPU._(JSObject _) implements JSObject {
  /// Asks for an adapter; resolves to null where the browser has none to give.
  external JSPromise<GPUAdapter?> requestAdapter();
}

/// The WebGPU `GPUAdapter` interface, with only the members this spike calls.
extension type GPUAdapter._(JSObject _) implements JSObject {
  /// Asks the adapter for a device, with the default limits and no optional
  /// features.
  external JSPromise<GPUDevice> requestDevice();
}

/// The WebGPU `GPUDevice` interface, with only the members this spike calls.
extension type GPUDevice._(JSObject _) implements JSObject {
  /// The device's one queue, where buffers are written and work is submitted.
  external GPUQueue get queue;

  /// Compiles the WGSL source [d] carries into a module.
  external GPUShaderModule createShaderModule(GPUShaderModuleDescriptor d);

  /// Builds a render pipeline from the stages and state [d] describes.
  external GPURenderPipeline createRenderPipeline(
    GPURenderPipelineDescriptor d,
  );

  /// Allocates a buffer of [d]'s size in bytes, with its `GPUBufferUsage`
  /// flags.
  external GPUBuffer createBuffer(GPUBufferDescriptor d);

  /// Allocates a texture of [d]'s size, format and usage.
  external GPUTexture createTexture(GPUTextureDescriptor d);

  /// Starts recording the commands of one submission.
  external GPUCommandEncoder createCommandEncoder();

  /// Releases the device, and with it everything made from it.
  external void destroy();
}

/// The WebGPU `GPUQueue` interface, with only the members this spike calls.
extension type GPUQueue._(JSObject _) implements JSObject {
  /// Copies the bytes of [data] into [buffer] at [bufferOffset] bytes, ahead of
  /// the next submission.
  external void writeBuffer(GPUBuffer buffer, int bufferOffset, JSObject data);

  /// Hands [buffers] to the GPU, to run in order.
  external void submit(JSArray<GPUCommandBuffer> buffers);

  /// Resolves when everything submitted before the call has finished, which is
  /// exactly what `GraphicsDevice.onFrameComplete` promises.
  external JSPromise<JSAny?> onSubmittedWorkDone();
}

/// The WebGPU `GPUShaderModule` interface, with only the members this spike
/// calls.
extension type GPUShaderModule._(JSObject _) implements JSObject {}

/// The WebGPU `GPURenderPipeline` interface, with only the members this spike
/// calls.
extension type GPURenderPipeline._(JSObject _) implements JSObject {}

/// The WebGPU `GPUCommandBuffer` interface, with only the members this spike
/// calls.
extension type GPUCommandBuffer._(JSObject _) implements JSObject {}

/// The WebGPU `GPUTextureView` interface, with only the members this spike
/// calls.
extension type GPUTextureView._(JSObject _) implements JSObject {}

/// The WebGPU `GPUTexture` interface, with only the members this spike calls.
extension type GPUTexture._(JSObject _) implements JSObject {
  /// A view of the whole texture, for a render pass to draw into.
  external GPUTextureView createView();

  /// Releases the texture's memory now rather than at collection.
  external void destroy();
}

/// The WebGPU `GPUBuffer` interface, with only the members this spike calls.
extension type GPUBuffer._(JSObject _) implements JSObject {
  /// Maps the buffer for the CPU, [mode] being `GPUMapMode` flags; resolves
  /// once the GPU is done with it.
  external JSPromise<JSAny?> mapAsync(int mode);

  /// The mapped bytes, valid until [unmap].
  external JSArrayBuffer getMappedRange();

  /// Gives the buffer back to the GPU; the mapped range is detached.
  external void unmap();

  /// Releases the buffer's memory now rather than at collection.
  external void destroy();
}

/// The WebGPU `GPUCommandEncoder` interface, with only the members this spike
/// calls.
extension type GPUCommandEncoder._(JSObject _) implements JSObject {
  /// Starts a render pass into the attachments [d] names.
  external GPURenderPassEncoder beginRenderPass(GPURenderPassDescriptor d);

  /// Records a copy of a texture's texels into a buffer, for reading back.
  external void copyTextureToBuffer(
    GPUTexelCopyTextureInfo source,
    GPUTexelCopyBufferInfo destination,
    GPUExtent3DDict copySize,
  );

  /// Ends the recording and returns the command buffer to submit.
  external GPUCommandBuffer finish();
}

/// The WebGPU `GPURenderPassEncoder` interface, with only the members this
/// spike calls.
extension type GPURenderPassEncoder._(JSObject _) implements JSObject {
  /// Binds [pipeline] for the draws that follow.
  external void setPipeline(GPURenderPipeline pipeline);

  /// Binds [buffer] to vertex buffer slot [slot].
  external void setVertexBuffer(int slot, GPUBuffer buffer);

  /// Binds [buffer] as the index buffer, [format] being `uint16` or `uint32`.
  external void setIndexBuffer(GPUBuffer buffer, String format);

  /// Sets the viewport in pixels, with its depth range from 0 to 1.
  external void setViewport(
    double x,
    double y,
    double width,
    double height,
    double minDepth,
    double maxDepth,
  );

  /// Limits drawing to a rectangle, in pixels.
  external void setScissorRect(int x, int y, int width, int height);

  /// Sets the colour a `constant` blend factor reads.
  external void setBlendConstant(GPUColorDict color);

  /// Sets the value the stencil test compares against.
  external void setStencilReference(int reference);

  /// Draws [indexCount] indices from the bound index buffer.
  external void drawIndexed(
    int indexCount,
    int instanceCount, [
    int firstIndex,
  ]);

  /// Ends the render pass.
  external void end();
}

// ------------------------------------------------------------- descriptors

/// The WebGPU `GPUShaderModuleDescriptor` dictionary, with only the members
/// this spike sets.
extension type GPUShaderModuleDescriptor._(JSObject _) implements JSObject {
  /// A `GPUShaderModuleDescriptor` with the given members; one left out takes
  /// WebGPU's default.
  external factory GPUShaderModuleDescriptor({String code});
}

/// The WebGPU `GPUBufferDescriptor` dictionary, with only the members this
/// spike sets.
extension type GPUBufferDescriptor._(JSObject _) implements JSObject {
  /// A `GPUBufferDescriptor` with the given members; one left out takes
  /// WebGPU's default.
  external factory GPUBufferDescriptor({int size, int usage});
}

/// The WebGPU `GPUTextureDescriptor` dictionary, with only the members this
/// spike sets.
extension type GPUTextureDescriptor._(JSObject _) implements JSObject {
  /// A `GPUTextureDescriptor` with the given members; one left out takes
  /// WebGPU's default.
  external factory GPUTextureDescriptor({
    GPUExtent3DDict size,
    String format,
    int usage,
    int sampleCount,
    int mipLevelCount,
  });
}

/// The WebGPU `GPUExtent3DDict` dictionary, with only the members this spike
/// sets.
extension type GPUExtent3DDict._(JSObject _) implements JSObject {
  /// A `GPUExtent3DDict` with the given members; one left out takes WebGPU's
  /// default.
  external factory GPUExtent3DDict({
    int width,
    int height,
    int depthOrArrayLayers,
  });
}

/// The WebGPU `GPUColorDict` dictionary, with only the members this spike sets.
extension type GPUColorDict._(JSObject _) implements JSObject {
  /// A `GPUColorDict` with the given members; one left out takes WebGPU's
  /// default.
  external factory GPUColorDict({double r, double g, double b, double a});
}

/// The WebGPU `GPURenderPassDescriptor` dictionary, with only the members this
/// spike sets.
extension type GPURenderPassDescriptor._(JSObject _) implements JSObject {
  /// A `GPURenderPassDescriptor` with the given members; one left out takes
  /// WebGPU's default.
  external factory GPURenderPassDescriptor({
    JSArray<GPURenderPassColorAttachment> colorAttachments,
  });
}

/// The WebGPU `GPURenderPassColorAttachment` dictionary, with only the members
/// this spike sets.
extension type GPURenderPassColorAttachment._(JSObject _) implements JSObject {
  /// A `GPURenderPassColorAttachment` with the given members; one left out
  /// takes WebGPU's default.
  external factory GPURenderPassColorAttachment({
    GPUTextureView view,
    GPUColorDict clearValue,
    String loadOp,
    String storeOp,
  });
}

/// The WebGPU `GPUVertexAttribute` dictionary, with only the members this spike
/// sets.
extension type GPUVertexAttribute._(JSObject _) implements JSObject {
  /// A `GPUVertexAttribute` with the given members; one left out takes WebGPU's
  /// default.
  external factory GPUVertexAttribute({
    String format,
    int offset,
    int shaderLocation,
  });
}

/// The WebGPU `GPUVertexBufferLayout` dictionary, with only the members this
/// spike sets.
extension type GPUVertexBufferLayout._(JSObject _) implements JSObject {
  /// A `GPUVertexBufferLayout` with the given members; one left out takes
  /// WebGPU's default.
  external factory GPUVertexBufferLayout({
    int arrayStride,
    String stepMode,
    JSArray<GPUVertexAttribute> attributes,
  });
}

/// The WebGPU `GPUVertexState` dictionary, with only the members this spike
/// sets.
extension type GPUVertexState._(JSObject _) implements JSObject {
  /// A `GPUVertexState` with the given members; one left out takes WebGPU's
  /// default.
  external factory GPUVertexState({
    GPUShaderModule module,
    String entryPoint,
    JSArray<GPUVertexBufferLayout> buffers,
  });
}

/// The WebGPU `GPUBlendComponent` dictionary, with only the members this spike
/// sets.
extension type GPUBlendComponent._(JSObject _) implements JSObject {
  /// A `GPUBlendComponent` with the given members; one left out takes WebGPU's
  /// default.
  external factory GPUBlendComponent({
    String operation,
    String srcFactor,
    String dstFactor,
  });
}

/// The WebGPU `GPUBlendState` dictionary, with only the members this spike
/// sets.
extension type GPUBlendState._(JSObject _) implements JSObject {
  /// A `GPUBlendState` with the given members; one left out takes WebGPU's
  /// default.
  external factory GPUBlendState({
    GPUBlendComponent color,
    GPUBlendComponent alpha,
  });
}

/// The WebGPU `GPUColorTargetState` dictionary, with only the members this
/// spike sets.
extension type GPUColorTargetState._(JSObject _) implements JSObject {
  /// A `GPUColorTargetState` with the given members; one left out takes
  /// WebGPU's default.
  external factory GPUColorTargetState({String format, GPUBlendState blend});

  /// Blending off, said by leaving the member out.
  ///
  /// **An absent key and an explicit null are different things to WebGPU**, and
  /// the difference is a `TypeError` at `createRenderPipeline` reading "the
  /// provided value is not of type 'GPUBlendState'". `PassEncoder.setBlend`
  /// takes a nullable state and null means off, so the obvious translation
  /// writes `blend: null` — which is the one spelling this API refuses. Two
  /// constructors rather than one nullable member, so the difference is made at
  /// the call site instead of discovered in a browser.
  external factory GPUColorTargetState.opaque({String format});
}

/// The WebGPU `GPUFragmentState` dictionary, with only the members this spike
/// sets.
extension type GPUFragmentState._(JSObject _) implements JSObject {
  /// A `GPUFragmentState` with the given members; one left out takes WebGPU's
  /// default.
  external factory GPUFragmentState({
    GPUShaderModule module,
    String entryPoint,
    JSArray<GPUColorTargetState> targets,
  });
}

/// The WebGPU `GPUPrimitiveState` dictionary, with only the members this spike
/// sets.
extension type GPUPrimitiveState._(JSObject _) implements JSObject {
  /// A `GPUPrimitiveState` with the given members; one left out takes WebGPU's
  /// default.
  external factory GPUPrimitiveState({
    String topology,
    String cullMode,
    String frontFace,
  });
}

/// The WebGPU `GPURenderPipelineDescriptor` dictionary, with only the members
/// this spike sets.
extension type GPURenderPipelineDescriptor._(JSObject _) implements JSObject {
  /// [layout] is `GPUPipelineLayout | "auto"`, so it is typed as `JSAny` and
  /// this spike always hands over the string: it declares no bindings, which is
  /// the whole of why it can get away with `"auto"`. A backend binding uniform
  /// blocks and samplers by name needs real layouts, built from the reflection
  /// the bundle would have to carry — see `webgpuContractGaps`.
  external factory GPURenderPipelineDescriptor({
    JSAny layout,
    GPUVertexState vertex,
    GPUFragmentState fragment,
    GPUPrimitiveState primitive,
  });
}

/// The WebGPU `GPUTexelCopyTextureInfo` dictionary, with only the members this
/// spike sets.
extension type GPUTexelCopyTextureInfo._(JSObject _) implements JSObject {
  /// A `GPUTexelCopyTextureInfo` with the given members; one left out takes
  /// WebGPU's default.
  external factory GPUTexelCopyTextureInfo({GPUTexture texture});
}

/// The WebGPU `GPUTexelCopyBufferInfo` dictionary, with only the members this
/// spike sets.
extension type GPUTexelCopyBufferInfo._(JSObject _) implements JSObject {
  /// A `GPUTexelCopyBufferInfo` with the given members; one left out takes
  /// WebGPU's default.
  external factory GPUTexelCopyBufferInfo({
    GPUBuffer buffer,
    int bytesPerRow,
    int rowsPerImage,
  });
}
