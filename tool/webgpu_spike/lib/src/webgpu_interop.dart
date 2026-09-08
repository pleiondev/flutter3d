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

extension type GpuNavigator._(JSObject _) implements JSObject {
  /// Null where the browser has no WebGPU, which is the answer a spike running
  /// in a headless test runner is most likely to get.
  external GPU? get gpu;
}

extension type GPU._(JSObject _) implements JSObject {
  external JSPromise<GPUAdapter?> requestAdapter();
}

extension type GPUAdapter._(JSObject _) implements JSObject {
  external JSPromise<GPUDevice> requestDevice();
}

extension type GPUDevice._(JSObject _) implements JSObject {
  external GPUQueue get queue;
  external GPUShaderModule createShaderModule(GPUShaderModuleDescriptor d);
  external GPURenderPipeline createRenderPipeline(
    GPURenderPipelineDescriptor d,
  );
  external GPUBuffer createBuffer(GPUBufferDescriptor d);
  external GPUTexture createTexture(GPUTextureDescriptor d);
  external GPUCommandEncoder createCommandEncoder();
  external void destroy();
}

extension type GPUQueue._(JSObject _) implements JSObject {
  external void writeBuffer(GPUBuffer buffer, int bufferOffset, JSObject data);
  external void submit(JSArray<GPUCommandBuffer> buffers);

  /// Resolves when everything submitted before the call has finished, which is
  /// exactly what `GraphicsDevice.onFrameComplete` promises.
  external JSPromise<JSAny?> onSubmittedWorkDone();
}

extension type GPUShaderModule._(JSObject _) implements JSObject {}

extension type GPURenderPipeline._(JSObject _) implements JSObject {}

extension type GPUCommandBuffer._(JSObject _) implements JSObject {}

extension type GPUTextureView._(JSObject _) implements JSObject {}

extension type GPUTexture._(JSObject _) implements JSObject {
  external GPUTextureView createView();
  external void destroy();
}

extension type GPUBuffer._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> mapAsync(int mode);
  external JSArrayBuffer getMappedRange();
  external void unmap();
  external void destroy();
}

extension type GPUCommandEncoder._(JSObject _) implements JSObject {
  external GPURenderPassEncoder beginRenderPass(GPURenderPassDescriptor d);
  external void copyTextureToBuffer(
    GPUTexelCopyTextureInfo source,
    GPUTexelCopyBufferInfo destination,
    GPUExtent3DDict copySize,
  );
  external GPUCommandBuffer finish();
}

extension type GPURenderPassEncoder._(JSObject _) implements JSObject {
  external void setPipeline(GPURenderPipeline pipeline);
  external void setVertexBuffer(int slot, GPUBuffer buffer);
  external void setIndexBuffer(GPUBuffer buffer, String format);
  external void setViewport(
    double x,
    double y,
    double width,
    double height,
    double minDepth,
    double maxDepth,
  );
  external void setScissorRect(int x, int y, int width, int height);
  external void setBlendConstant(GPUColorDict color);
  external void setStencilReference(int reference);
  external void drawIndexed(int indexCount, int instanceCount);
  external void end();
}

// ------------------------------------------------------------- descriptors

extension type GPUShaderModuleDescriptor._(JSObject _) implements JSObject {
  external factory GPUShaderModuleDescriptor({String code});
}

extension type GPUBufferDescriptor._(JSObject _) implements JSObject {
  external factory GPUBufferDescriptor({int size, int usage});
}

extension type GPUTextureDescriptor._(JSObject _) implements JSObject {
  external factory GPUTextureDescriptor({
    GPUExtent3DDict size,
    String format,
    int usage,
    int sampleCount,
    int mipLevelCount,
  });
}

extension type GPUExtent3DDict._(JSObject _) implements JSObject {
  external factory GPUExtent3DDict({
    int width,
    int height,
    int depthOrArrayLayers,
  });
}

extension type GPUColorDict._(JSObject _) implements JSObject {
  external factory GPUColorDict({double r, double g, double b, double a});
}

extension type GPURenderPassDescriptor._(JSObject _) implements JSObject {
  external factory GPURenderPassDescriptor({
    JSArray<GPURenderPassColorAttachment> colorAttachments,
  });
}

extension type GPURenderPassColorAttachment._(JSObject _) implements JSObject {
  external factory GPURenderPassColorAttachment({
    GPUTextureView view,
    GPUColorDict clearValue,
    String loadOp,
    String storeOp,
  });
}

extension type GPUVertexAttribute._(JSObject _) implements JSObject {
  external factory GPUVertexAttribute({
    String format,
    int offset,
    int shaderLocation,
  });
}

extension type GPUVertexBufferLayout._(JSObject _) implements JSObject {
  external factory GPUVertexBufferLayout({
    int arrayStride,
    String stepMode,
    JSArray<GPUVertexAttribute> attributes,
  });
}

extension type GPUVertexState._(JSObject _) implements JSObject {
  external factory GPUVertexState({
    GPUShaderModule module,
    String entryPoint,
    JSArray<GPUVertexBufferLayout> buffers,
  });
}

extension type GPUBlendComponent._(JSObject _) implements JSObject {
  external factory GPUBlendComponent({
    String operation,
    String srcFactor,
    String dstFactor,
  });
}

extension type GPUBlendState._(JSObject _) implements JSObject {
  external factory GPUBlendState({
    GPUBlendComponent color,
    GPUBlendComponent alpha,
  });
}

extension type GPUColorTargetState._(JSObject _) implements JSObject {
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

extension type GPUFragmentState._(JSObject _) implements JSObject {
  external factory GPUFragmentState({
    GPUShaderModule module,
    String entryPoint,
    JSArray<GPUColorTargetState> targets,
  });
}

extension type GPUPrimitiveState._(JSObject _) implements JSObject {
  external factory GPUPrimitiveState({
    String topology,
    String cullMode,
    String frontFace,
  });
}

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

extension type GPUTexelCopyTextureInfo._(JSObject _) implements JSObject {
  external factory GPUTexelCopyTextureInfo({GPUTexture texture});
}

extension type GPUTexelCopyBufferInfo._(JSObject _) implements JSObject {
  external factory GPUTexelCopyBufferInfo({
    GPUBuffer buffer,
    int bytesPerRow,
    int rowsPerImage,
  });
}
