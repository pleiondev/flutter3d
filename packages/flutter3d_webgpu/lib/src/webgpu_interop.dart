/// WebGPU as `dart:js_interop` declarations, sized for a backend.
///
/// **Hand-written because there is nothing to import.** `package:web` is
/// generated from the same IDL as everything else a browser has, and for WebGPU
/// it stops at the flag constants — `GPUBufferUsage`, `GPUTextureUsage`,
/// `GPUShaderStage` and their siblings are there and every interface is not. So
/// a backend on this API starts by writing its own bindings, which is a fact
/// about the cost of the fourth backend rather than about the contract: it is
/// mechanical, it is a few hundred lines, and none of it is a decision.
///
/// Descriptors are object-literal constructors rather than maps, so a misspelt
/// member is a compile error instead of a browser refusing a dictionary at run
/// time with a message naming a field nobody typed. That is the whole reason
/// this file is shaped the way it is, and it is the reason it is worth three
/// hundred lines of typing: `createRenderPipeline` given `frontface` instead of
/// `frontFace` does not fail — it silently takes the default, and the picture
/// comes out with the wrong faces missing.
///
/// **The flag constants are written out here rather than imported.** The spike
/// this file grew from reached into `package:web` for `$GPUBufferUsage` and
/// friends, which cost it a dependency for five integers. A package three
/// branches are writing into at once is a bad place to add a dependency line,
/// and the numbers are fixed by the specification and asserted by this
/// package's own tests, so [GpuBufferUsage] and its siblings hold them. Nothing
/// in this file imports anything but `dart:js_interop`.
///
/// **What is deliberately absent:** external textures. `flutter3d_hardware`
/// does not ask for them, and a declaration nobody calls is a declaration
/// nobody has checked against a browser. Compute pipelines arrived with `H6`,
/// and query sets, render bundles, indirect draws and storage textures with
/// 1.0, each when the contract did ask.
@JS()
library;

import 'dart:js_interop';

// The one place a property is set by a name that is not known until run time:
// `GPUDeviceDescriptor.requiredLimits` is a record of limit name to number, and
// a record has no Dart spelling past `JSObject`. See [gpuRequiredLimits], which
// is the whole of this import's use.
import 'dart:js_interop_unsafe';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show ResourceException;

// ------------------------------------------------------------ getting a device

/// `navigator`, for the one property that says whether this browser has WebGPU
/// at all.
@JS('navigator')
external GpuNavigator get gpuNavigator;

/// The browser's `Navigator`, reduced to its `gpu` member.
extension type GpuNavigator._(JSObject _) implements JSObject {
  /// Null where the browser has no WebGPU, which is the answer a test runner on
  /// a machine with no GPU is most likely to get, and an ordinary case rather
  /// than a failure: a caller's move is to pick another backend.
  external GPU? get gpu;
}

/// WebGPU's `GPU` object, `navigator.gpu`: the entry point that hands out
/// adapters.
extension type GPU._(JSObject _) implements JSObject {
  /// The adapter, asked for with the options that decide which one arrives.
  ///
  /// **The options are the point of taking a descriptor at all.** A laptop with
  /// two GPUs hands out the low-power one unless asked otherwise, and a
  /// renderer that has just been told to draw shadows and bloom wants the other
  /// one. The argument is optional because "whatever this machine prefers" is a
  /// real answer and the common one.
  external JSPromise<GPUAdapter?> requestAdapter([
    GPURequestAdapterOptions options,
  ]);

  /// The texture format a canvas on this machine can present without a
  /// conversion pass — `"bgra8unorm"` on most desktops and `"rgba8unorm"` on
  /// some phones.
  ///
  /// Asked rather than assumed because configuring a canvas with the other one
  /// is legal, costs a blit per frame, and looks identical.
  external String getPreferredCanvasFormat();
}

/// WebGPU's `GPUAdapter`: one physical or software implementation, from which
/// a device is requested.
extension type GPUAdapter._(JSObject _) implements JSObject {
  /// What this adapter can do beyond the guaranteed baseline.
  ///
  /// **The only honest source of an answer about compressed formats.** BC, ETC2
  /// and ASTC are optional features in WebGPU: the format strings exist in the
  /// specification and a device that did not ask for the feature refuses every
  /// one of them. So `GraphicsDevice.supportsTextureFormat` cannot be answered
  /// from a translation table alone — it has to ask this set, and the device
  /// has to have requested the feature before it can be used.
  external GPUSupportedFeatures get features;

  /// The best limits this adapter can grant, which a device only gets where
  /// it asks for them in `requiredLimits`.
  external GPUSupportedLimits get limits;

  /// Vendor and architecture strings, for whoever is deciding what to log about
  /// the machine a frame was slow on.
  external GPUAdapterInfo get info;

  /// The device, with the features and limits it will be held to.
  ///
  /// **A device gets exactly what it asks for.** Requesting no features and
  /// then sampling a BC7 texture is a validation error, not a slow path, which
  /// is why the descriptor is worth having: the adapter is asked what it has,
  /// the intersection is requested, and the device's own `features` is what the
  /// backend then answers questions from.
  external JSPromise<GPUDevice> requestDevice([GPUDeviceDescriptor descriptor]);
}

/// The set of feature names an adapter or a device carries.
///
/// A JavaScript set, reduced to the one question anybody asks it. See
/// [GpuFeature] for the names worth asking about.
extension type GPUSupportedFeatures._(JSObject _) implements JSObject {
  /// Whether [feature] is available. A name this API does not know is `false`
  /// rather than an error, which is why the names are constants here and not
  /// string literals at the call site.
  external bool has(String feature);
}

/// The numbers a device will not go past.
///
/// Every limit `DeviceLimits` reports, which since 1.0 is what
/// `GraphicsDevice.limits` reads off the device that was granted.
extension type GPUSupportedLimits._(JSObject _) implements JSObject {
  /// Largest width of a `"1d"` texture, in texels.
  external int get maxTextureDimension1D;

  /// Largest width or height of a `"2d"` texture, in texels.
  external int get maxTextureDimension2D;

  /// Largest width, height or depth of a `"3d"` texture, in texels.
  external int get maxTextureDimension3D;

  /// Largest layer count of a 2D array texture.
  external int get maxTextureArrayLayers;

  /// Count of bind groups a pipeline layout may hold, so the highest usable
  /// `@group` is one less.
  external int get maxBindGroups;

  /// Count of sampler bindings one shader stage may see across all groups.
  external int get maxSamplersPerShaderStage;

  /// Count of sampled-texture bindings one shader stage may see.
  external int get maxSampledTexturesPerShaderStage;

  /// Count of storage-buffer bindings one shader stage may see.
  external int get maxStorageBuffersPerShaderStage;

  /// Count of storage-texture bindings one shader stage may see.
  external int get maxStorageTexturesPerShaderStage;

  /// Count of uniform-buffer bindings one shader stage may see.
  external int get maxUniformBuffersPerShaderStage;

  /// Count of uniform bindings with a dynamic offset in one pipeline layout.
  external int get maxDynamicUniformBuffersPerPipelineLayout;

  /// Largest size of one uniform buffer binding, in bytes.
  external int get maxUniformBufferBindingSize;

  /// Largest size of one storage buffer binding, in bytes.
  external int get maxStorageBufferBindingSize;

  /// Largest size of a buffer, in bytes.
  external int get maxBufferSize;

  /// Count of vertex buffer slots a pipeline may use.
  external int get maxVertexBuffers;

  /// Count of vertex attributes across all of a pipeline's buffers.
  external int get maxVertexAttributes;

  /// Largest `arrayStride` of a vertex buffer layout, in bytes.
  external int get maxVertexBufferArrayStride;

  /// Count of scalar components that may pass from the vertex stage to the
  /// fragment stage, in units of four-component vectors.
  external int get maxInterStageShaderVariables;

  /// Count of colour attachments a pass or pipeline may have.
  external int get maxColorAttachments;

  /// Bytes all colour attachments together may store per sample.
  external int get maxColorAttachmentBytesPerSample;

  /// The alignment a storage buffer binding's offset has to satisfy, in
  /// bytes.
  external int get minStorageBufferOffsetAlignment;

  /// Bytes of `var<workgroup>` memory one compute workgroup may use.
  external int get maxComputeWorkgroupStorageSize;

  /// Count of invocations in one workgroup, the product of its three sizes.
  external int get maxComputeInvocationsPerWorkgroup;

  /// Largest `@workgroup_size` along x.
  external int get maxComputeWorkgroupSizeX;

  /// Largest `@workgroup_size` along y.
  external int get maxComputeWorkgroupSizeY;

  /// Largest `@workgroup_size` along z.
  external int get maxComputeWorkgroupSizeZ;

  /// Largest workgroup count along any one axis of a dispatch.
  external int get maxComputeWorkgroupsPerDimension;

  /// The limit called [name], for a caller that holds a list of names rather
  /// than a getter per limit: what `webgpuRequiredLimits` asks an adapter.
  int named(String name) => getProperty<JSNumber>(name.toJS).toDartInt;

  /// The alignment a dynamic uniform offset has to satisfy — 256 on every
  /// implementation so far, and the reason a per-object uniform block is padded
  /// out rather than packed.
  external int get minUniformBufferOffsetAlignment;
}

/// WebGPU's `GPUAdapterInfo`: what the browser is willing to say about the
/// adapter. Every member may be the empty string where it says nothing.
extension type GPUAdapterInfo._(JSObject _) implements JSObject {
  /// The adapter's vendor, such as `"nvidia"` or `"apple"`.
  external String get vendor;

  /// The vendor's GPU family name, such as `"turing"`.
  external String get architecture;

  /// A vendor-specific identifier of the adapter.
  external String get device;

  /// A human-readable name of the adapter, as the driver reports it.
  external String get description;
}

/// WebGPU's `GPUDevice`: the logical device every resource and command is
/// created on.
extension type GPUDevice._(JSObject _) implements JSObject {
  /// The device's one queue, which writes and submissions go through.
  external GPUQueue get queue;

  /// What was actually granted, which is not always what was asked for.
  external GPUSupportedFeatures get features;

  /// The limits the device was granted: the defaults, raised wherever
  /// `requiredLimits` asked.
  external GPUSupportedLimits get limits;

  /// Resolves when the device is gone — the tab lost its GPU, or something
  /// called [destroy].
  ///
  /// Never rejects, so a listener on it is a listener and not an error path.
  /// Read by whoever wants to tear the renderer down rather than let every
  /// subsequent call fail one at a time.
  external JSPromise<GPUDeviceLostInfo> get lost;

  /// Compiles WGSL into a module. Always returns one; errors arrive through
  /// `GPUShaderModule.getCompilationInfo` and an error scope.
  external GPUShaderModule createShaderModule(GPUShaderModuleDescriptor d);

  /// Builds a render pipeline. An illegal descriptor still returns an
  /// object, an invalid one, and the refusal reaches only an error scope.
  external GPURenderPipeline createRenderPipeline(
    GPURenderPipelineDescriptor d,
  );

  /// [createRenderPipeline], compiled off the calling turn. The promise
  /// rejects with a `GPUPipelineError` where the descriptor is refused,
  /// rather than handing back an invalid pipeline.
  external JSPromise<GPURenderPipeline> createRenderPipelineAsync(
    GPURenderPipelineDescriptor d,
  );

  /// Allocates a buffer, unmapped unless `mappedAtCreation` is set.
  external GPUBuffer createBuffer(GPUBufferDescriptor d);

  /// Allocates a texture with its usage fixed for life.
  external GPUTexture createTexture(GPUTextureDescriptor d);

  /// Creates a sampler; immutable once made.
  external GPUSampler createSampler(GPUSamplerDescriptor d);

  /// Creates the layout of one bind group: which bindings, of what kind,
  /// visible to which stages.
  external GPUBindGroupLayout createBindGroupLayout(
    GPUBindGroupLayoutDescriptor d,
  );

  /// Creates a pipeline layout from bind group layouts in `@group` order.
  external GPUPipelineLayout createPipelineLayout(
    GPUPipelineLayoutDescriptor d,
  );

  /// Creates a bind group: actual resources against a layout's bindings.
  external GPUBindGroup createBindGroup(GPUBindGroupDescriptor d);

  /// Starts recording commands; one encoder yields one command buffer.
  external GPUCommandEncoder createCommandEncoder();

  /// A set of queries — `H2`'s timestamps.
  external GPUQuerySet createQuerySet(GPUQuerySetDescriptor d);

  /// A compute pipeline — `H6`.
  external GPUComputePipeline createComputePipeline(
    GPUComputePipelineDescriptor d,
  );

  /// [createComputePipeline], compiled off the calling turn; see
  /// [createRenderPipelineAsync].
  external JSPromise<GPUComputePipeline> createComputePipelineAsync(
    GPUComputePipelineDescriptor d,
  );

  /// An encoder whose draws are kept as a bundle and replayed into passes.
  external GPURenderBundleEncoder createRenderBundleEncoder(
    GPURenderBundleEncoderDescriptor d,
  );

  /// Starts catching errors of one kind instead of letting them reach the
  /// console.
  ///
  /// **Without this pair nothing a browser rejects can ever be thrown in
  /// Dart.** WebGPU validates asynchronously: `createRenderPipeline` returns a
  /// pipeline object whether or not the descriptor was legal, and the complaint
  /// arrives later, on the console, in a message the Dart program never sees.
  /// So a backend that means to report a refusal — which is what the
  /// conformance suite's refusal checks watch for — has to bracket the call.
  /// [gpuChecked] is that bracket, and is what a caller should reach for rather
  /// than this pair directly.
  external void pushErrorScope(String filter);

  /// The first error caught since the matching [pushErrorScope], or null.
  ///
  /// Rejects rather than resolving if no scope is open, which is why the two
  /// belong in one function and not at two ends of a method.
  external JSPromise<GPUError?> popErrorScope();

  /// `GPUDevice` is an `EventTarget`; the one event it fires is
  /// `uncapturederror`, a [GPUUncapturedErrorEvent] for every error no scope
  /// caught — which, unheard, goes to the console and nowhere else.
  external void addEventListener(String type, JSFunction listener);

  /// Loses the device on purpose: every resource on it becomes invalid and
  /// [lost] resolves with reason `"destroyed"`.
  external void destroy();
}

/// An error no error scope caught, as `GPUDevice` fires it.
extension type GPUUncapturedErrorEvent._(JSObject _) implements JSObject {
  /// A `GPUValidationError`, `GPUOutOfMemoryError` or `GPUInternalError`.
  external GPUError get error;
}

/// WebGPU's `GPUDeviceLostInfo`: why a device's `lost` promise resolved.
extension type GPUDeviceLostInfo._(JSObject _) implements JSObject {
  /// `"destroyed"` where something called `destroy`, `"unknown"` otherwise —
  /// which is the difference between a teardown and a crash.
  external String get reason;

  /// The browser's own words about the loss, for a log; no stable format.
  external String get message;
}

/// What a popped error scope hands back.
///
/// The three concrete kinds — validation, out of memory, internal — differ only
/// in which filter catches them, so one declaration covers all three and the
/// filter that was pushed says which arrived.
extension type GPUError._(JSObject _) implements JSObject {
  /// The browser's description of the error, usually naming the offending
  /// descriptor member; no stable format.
  external String get message;
}

/// WebGPU's `GPUQueue`: where buffers and textures are written and command
/// buffers are submitted.
extension type GPUQueue._(JSObject _) implements JSObject {
  /// Bytes into a buffer.
  ///
  /// [dataOffset] and [size] are counted in *elements of [data]*, not in bytes,
  /// which is the one place this API changes units on its caller. Omitted, the
  /// whole of [data] is written — which is what a backend uploading a whole
  /// mesh wants, and the reason they are optional rather than required zeros.
  external void writeBuffer(
    GPUBuffer buffer,
    int bufferOffset,
    JSObject data, [
    int dataOffset,
    int size,
  ]);

  /// Pixels into a texture, at a mip level and an array layer named by
  /// [destination].
  ///
  /// **This is how a cube face and a mip level get their contents.** There is
  /// no six-argument upload call and no face enumeration in WebGPU: a cube is a
  /// six-layer 2D array, a face is `origin.z`, and a level is `mipLevel`. The
  /// contract's `createCubeTextureFromPixels` becomes six of these per level.
  external void writeTexture(
    GPUTexelCopyTextureInfo destination,
    JSObject data,
    GPUTexelCopyBufferLayout dataLayout,
    GPUExtent3DDict size,
  );

  /// A browser-decoded image into a texture — `A4.16`. [source]'s `source`
  /// is an `ImageBitmap`; the destination texture needs `COPY_DST` and
  /// `RENDER_ATTACHMENT`, the second because the browser may draw the copy.
  external void copyExternalImageToTexture(
    GPUCopyExternalImageSourceInfo source,
    GPUCopyExternalImageDestInfo destination,
    GPUExtent3DDict copySize,
  );

  /// Hands finished command buffers to the GPU, in order. Each buffer can be
  /// submitted once; a second submission is a validation error.
  external void submit(JSArray<GPUCommandBuffer> buffers);

  /// Resolves when everything submitted before the call has finished, which is
  /// exactly what `GraphicsDevice.onFrameComplete` promises.
  external JSPromise<JSAny?> onSubmittedWorkDone();
}

/// WebGPU's `GPUShaderModule`: compiled WGSL that pipelines name entry points
/// of.
extension type GPUShaderModule._(JSObject _) implements JSObject {
  /// What the browser thought of the WGSL.
  ///
  /// **A module compiles whether or not the code was valid**, the same way a
  /// pipeline is created whether or not the descriptor was: the diagnostics
  /// arrive here and the failure arrives later as a pipeline that does not
  /// work. A backend loading a shader bundle wants the line and column, because
  /// the WGSL it is compiling was produced by a translator and nobody typed it.
  external JSPromise<GPUCompilationInfo> getCompilationInfo();
}

/// WebGPU's `GPUCompilationInfo`: the diagnostics of one shader module.
extension type GPUCompilationInfo._(JSObject _) implements JSObject {
  /// Every diagnostic, in no promised order; empty for clean WGSL.
  external JSArray<GPUCompilationMessage> get messages;
}

/// One diagnostic about a shader module's WGSL.
extension type GPUCompilationMessage._(JSObject _) implements JSObject {
  /// The compiler's text for the diagnostic.
  external String get message;

  /// `"error"`, `"warning"` or `"info"`. Only the first stops a pipeline
  /// working, and the other two are worth printing exactly once.
  external String get type;

  /// The line the diagnostic points at, counted from one; zero where it
  /// points at no line.
  external int get lineNum;

  /// The column on [lineNum], in UTF-16 code units counted from one; zero
  /// where it points at no position.
  external int get linePos;
}

/// WebGPU's `GPURenderPipeline`: compiled shaders with every piece of fixed
/// render state, bound into a pass with `setPipeline`.
extension type GPURenderPipeline._(JSObject _) implements JSObject {
  /// The name a GPU debugger and the browser's errors show for it —
  /// `GraphicsDevice.setLabel`.
  external set label(String value);

  /// The layout of one bind group, as the pipeline understood it.
  ///
  /// Only useful where the pipeline was built with `layout: "auto"`, and then
  /// it is the only way to get a layout object to build a bind group against.
  /// A backend that states its own [GPUPipelineLayout] never calls this — see
  /// [GPURenderPipelineDescriptor] for why stating one is the better half of
  /// that choice.
  external GPUBindGroupLayout getBindGroupLayout(int index);
}

/// WebGPU's `GPUPipelineLayout`: the bind group layouts a pipeline is built
/// against, one per `@group`.
extension type GPUPipelineLayout._(JSObject _) implements JSObject {}

/// WebGPU's `GPUBindGroupLayout`: the shape of one bind group, which a bind
/// group and a pipeline layout must both name.
extension type GPUBindGroupLayout._(JSObject _) implements JSObject {}

/// WebGPU's `GPUBindGroup`: buffers, samplers and texture views bound to a
/// layout's slots, set as a unit with `setBindGroup`.
extension type GPUBindGroup._(JSObject _) implements JSObject {}

/// WebGPU's `GPUSampler`: filtering, addressing and comparison state for
/// texture reads.
extension type GPUSampler._(JSObject _) implements JSObject {}

/// WebGPU's `GPUCommandBuffer`: a finished recording, submitted once through
/// `GPUQueue.submit`.
extension type GPUCommandBuffer._(JSObject _) implements JSObject {}

/// WebGPU's `GPUTextureView`: a window onto some levels, layers and aspects
/// of a texture, which is what bindings and attachments take.
extension type GPUTextureView._(JSObject _) implements JSObject {}

/// WebGPU's `GPUTexture`: an image allocation with its size, format and
/// usage fixed when it was made.
extension type GPUTexture._(JSObject _) implements JSObject {
  /// The name a GPU debugger and the browser's errors show for it —
  /// `GraphicsDevice.setLabel`.
  external set label(String value);

  /// Width of level zero, in texels.
  external int get width;

  /// Height of level zero, in texels; one for a `"1d"` texture.
  external int get height;

  /// Depth of level zero in texels for a `"3d"` texture, otherwise the
  /// count of array layers (six for a cube).
  external int get depthOrArrayLayers;

  /// Count of mip levels, at least one.
  external int get mipLevelCount;

  /// Samples per texel: one, or four for a multisampled target.
  external int get sampleCount;

  /// The texture format string, such as `"rgba8unorm"`.
  external String get format;

  /// `"1d"`, `"2d"` or `"3d"`.
  external String get dimension;

  /// The `GpuTextureUsage` bits it was made with — what a write or a copy
  /// asks before the browser would refuse it.
  external int get usage;

  /// A view of the whole texture, or of the slice [descriptor] names.
  ///
  /// **The descriptor is what makes cube faces and render-to-mip possible.**
  /// `baseArrayLayer` picks a cube face and `baseMipLevel` picks a level to
  /// attach, and both of those are things the contract asks for —
  /// `createCubeRenderTarget` and `supportsRenderToMip` — that OpenGL ES needs
  /// separate machinery for and WebGPU treats as one ordinary attachment.
  external GPUTextureView createView([GPUTextureViewDescriptor descriptor]);

  /// Frees the texture's memory now rather than at garbage collection; any
  /// later use of it or its views is a validation error.
  external void destroy();
}

/// WebGPU's `GPUBuffer`: a linear allocation with its size and usage fixed
/// when it was made.
extension type GPUBuffer._(JSObject _) implements JSObject {
  /// The name a GPU debugger and the browser's errors show for it —
  /// `GraphicsDevice.setLabel`.
  external set label(String value);

  /// Size in bytes, as it was created.
  external int get size;

  /// The `GpuBufferUsage` bits it was made with.
  external int get usage;

  /// Maps a range for reading or writing, which is how a readback gets at its
  /// staging buffer.
  ///
  /// [offset] and [size] are bytes here, unlike `writeBuffer`'s. Omitted, the
  /// whole buffer is mapped.
  external JSPromise<JSAny?> mapAsync(int mode, [int offset, int size]);

  /// The mapped bytes. Valid only until [unmap], and a view rather than a copy,
  /// so a caller keeping the data past the unmap has to copy it out.
  external JSArrayBuffer getMappedRange([int offset, int size]);

  /// Hands a mapped buffer back to the GPU, detaching every range
  /// [getMappedRange] returned.
  external void unmap();

  /// Frees the buffer's memory now rather than at garbage collection; any
  /// later use of it is a validation error.
  external void destroy();
}

/// WebGPU's `GPUCommandEncoder`: records passes and copies into one command
/// buffer.
extension type GPUCommandEncoder._(JSObject _) implements JSObject {
  /// The debug group a GPU debugger shows around the commands until the
  /// matching pop — `PassEncoder.pushDebugGroup`.
  external void pushDebugGroup(String groupLabel);

  /// Closes the innermost [pushDebugGroup]; popping with none open is a
  /// validation error.
  external void popDebugGroup();

  /// A single named point a GPU debugger shows among the commands.
  external void insertDebugMarker(String markerLabel);

  /// Opens a render pass; the encoder takes nothing else until the pass's
  /// `end`.
  external GPURenderPassEncoder beginRenderPass(GPURenderPassDescriptor d);

  /// Opens a compute pass — `H6`.
  external GPUComputePassEncoder beginComputePass([
    GPUComputePassDescriptor descriptor,
  ]);

  /// Straight buffer-to-buffer bytes, for whoever is moving a staged upload
  /// into its final home rather than writing it through the queue.
  external void copyBufferToBuffer(
    GPUBuffer source,
    int sourceOffset,
    GPUBuffer destination,
    int destinationOffset,
    int size,
  );

  /// Texture to texture, level and layer named by each side's info — which is
  /// how a rendered face reaches a cube map, and how `present` gets a frame
  /// into the canvas texture.
  external void copyTextureToTexture(
    GPUTexelCopyTextureInfo source,
    GPUTexelCopyTextureInfo destination,
    GPUExtent3DDict copySize,
  );

  /// Texture texels into buffer rows, the readback path. The buffer layout's
  /// `bytesPerRow` must be a multiple of 256.
  external void copyTextureToBuffer(
    GPUTexelCopyTextureInfo source,
    GPUTexelCopyBufferInfo destination,
    GPUExtent3DDict copySize,
  );

  /// Buffer rows into a texture — the encoded twin of `writeTexture`, with
  /// `copyTextureToBuffer`'s 256-byte row rule.
  external void copyBufferToTexture(
    GPUTexelCopyBufferInfo source,
    GPUTexelCopyTextureInfo destination,
    GPUExtent3DDict copySize,
  );

  /// Zeroes [size] bytes of [buffer] from [offset]; both multiples of four.
  external void clearBuffer(GPUBuffer buffer, [int offset, int size]);

  /// Writes [queryCount] query results from [querySet] into [destination] —
  /// `H2`. Timestamps come out as 64-bit nanoseconds.
  external void resolveQuerySet(
    GPUQuerySet querySet,
    int firstQuery,
    int queryCount,
    GPUBuffer destination,
    int destinationOffset,
  );

  /// Ends recording and returns the command buffer; the encoder is spent.
  external GPUCommandBuffer finish();
}

/// What a render pass and a render bundle can both record: the pipeline, the
/// bindings and the draws.
///
/// WebGPU's `GPURenderCommandsMixin`. One extension type that both encoders
/// implement, so the encoder in `webgpu_encoder.dart` resolves a draw once and
/// records it into whichever of the two it is filling.
extension type GPURenderCommands._(JSObject _) implements JSObject {
  /// The debug group a GPU debugger shows around the commands until the
  /// matching pop — `PassEncoder.pushDebugGroup`.
  external void pushDebugGroup(String groupLabel);

  /// Closes the innermost [pushDebugGroup]; popping with none open is a
  /// validation error.
  external void popDebugGroup();

  /// A single named point a GPU debugger shows among the commands.
  external void insertDebugMarker(String markerLabel);

  /// Makes [pipeline] the one the following draws use.
  external void setPipeline(GPURenderPipeline pipeline);

  /// One bind group into a slot, with its dynamic offsets if it has any.
  ///
  /// A null [group] unbinds the slot, and that spelling is allowed here — this
  /// is one of the few places in WebGPU where an explicit null means something
  /// rather than being refused. [dynamicOffsets] is in the order the layout's
  /// dynamic entries were declared, not by binding number, which is the sort of
  /// thing that draws the wrong object rather than failing.
  external void setBindGroup(
    int index,
    GPUBindGroup? group, [
    JSArray<JSNumber> dynamicOffsets,
  ]);

  /// A vertex buffer into a slot, optionally a window into it.
  ///
  /// **[offset] and [size] are what a backend packing several meshes into one
  /// buffer lives on.** Left out they are the whole buffer, which is right for
  /// one mesh per allocation and silently wrong the moment two share — the draw
  /// succeeds and reads somebody else's geometry. `GeometryBuffer` carries
  /// `offsetInBytes` and `lengthInBytes` for exactly this, so the two are here
  /// rather than assumed to be zero.
  external void setVertexBuffer(
    int slot,
    GPUBuffer buffer, [
    int offset,
    int size,
  ]);

  /// The index buffer, with the same window and for the same reason.
  external void setIndexBuffer(
    GPUBuffer buffer,
    String format, [
    int offset,
    int size,
  ]);

  /// A non-indexed draw.
  ///
  /// [firstVertex] and [firstInstance] are the other half of the window
  /// `setVertexBuffer` opens: a backend can address a sub-range either by
  /// binding a slice or by skipping vertices, and instanced drawing needs
  /// [firstInstance] to start anywhere but zero.
  external void draw(
    int vertexCount, [
    int instanceCount,
    int firstVertex,
    int firstInstance,
  ]);

  /// An indexed draw.
  ///
  /// [firstIndex] skips into the index buffer and [baseVertex] is added to
  /// every index read — which is how one buffer holds several meshes and each
  /// one keeps indices numbered from zero. Both default to zero, and both are
  /// a wrong picture rather than an error when they are left out by mistake.
  external void drawIndexed(
    int indexCount, [
    int instanceCount,
    int firstIndex,
    int baseVertex,
    int firstInstance,
  ]);

  /// A non-indexed draw whose four counts [indirectBuffer] holds.
  external void drawIndirect(GPUBuffer indirectBuffer, int indirectOffset);

  /// An indexed draw whose five counts [indirectBuffer] holds.
  external void drawIndexedIndirect(
    GPUBuffer indirectBuffer,
    int indirectOffset,
  );
}

/// WebGPU's `GPURenderPassEncoder`: records one render pass, adding viewport,
/// scissor, blend constant, stencil reference, occlusion queries and bundle
/// replay to what [GPURenderCommands] records.
extension type GPURenderPassEncoder._(JSObject _) implements GPURenderCommands {
  /// The viewport, in pixels of the attachments, with the depth range from
  /// [minDepth] to [maxDepth], each a fraction from nought to one.
  external void setViewport(
    double x,
    double y,
    double width,
    double height,
    double minDepth,
    double maxDepth,
  );

  /// The scissor rectangle, in pixels; it must lie inside the attachments.
  external void setScissorRect(int x, int y, int width, int height);

  /// The colour the `"constant"` blend factors read.
  external void setBlendConstant(GPUColorDict color);

  /// The stencil reference value the stencil tests and `"replace"` use.
  external void setStencilReference(int reference);

  /// Counts the samples the next draws pass into query [queryIndex] of the
  /// pass descriptor's `occlusionQuerySet`.
  external void beginOcclusionQuery(int queryIndex);

  /// Closes the query [beginOcclusionQuery] opened.
  external void endOcclusionQuery();

  /// Replays recorded bundles. Afterwards the pass's pipeline and bindings
  /// are unset, as the specification says.
  external void executeBundles(JSArray<GPURenderBundle> bundles);

  /// [maxDrawCount] indexed indirect draws, twenty bytes apart, the count
  /// read from [drawCountBuffer] where one is given. Only on a device
  /// granted [GpuFeature.multiDrawIndirect] or its experimental spelling.
  external void multiDrawIndexedIndirect(
    GPUBuffer indirectBuffer,
    int indirectOffset,
    int maxDrawCount, [
    GPUBuffer? drawCountBuffer,
    int drawCountBufferOffset,
  ]);

  /// Closes the pass and hands the encoder back to its command encoder.
  external void end();
}

/// Records draws into a bundle — `GraphicsDevice.createRenderBundleEncoder`.
extension type GPURenderBundleEncoder._(JSObject _)
    implements GPURenderCommands {
  /// Ends recording and returns the bundle; the encoder is spent.
  external GPURenderBundle finish([GPURenderBundleDescriptor descriptor]);
}

/// WebGPU's `GPURenderBundle`: recorded draws, replayed into any pass whose
/// attachment formats and sample count match the bundle's.
extension type GPURenderBundle._(JSObject _) implements JSObject {}

/// WebGPU's `GPURenderBundleDescriptor`, which carries only a label.
extension type GPURenderBundleDescriptor._(JSObject _) implements JSObject {
  /// A descriptor naming the bundle [label].
  external factory GPURenderBundleDescriptor({String label});
}

/// WebGPU's `GPURenderBundleEncoderDescriptor`: the attachment formats and
/// sample count a bundle will be replayed against.
extension type GPURenderBundleEncoderDescriptor._(JSObject _)
    implements JSObject {
  /// A bundle replayed into passes with no depth attachment.
  external factory GPURenderBundleEncoderDescriptor({
    JSArray<JSString> colorFormats,
    int sampleCount,
    String label,
  });

  /// A bundle replayed into passes with a depth attachment of
  /// [depthStencilFormat]. Separate for the reason every pair in this file
  /// is: a null format is refused, an absent one is not.
  external factory GPURenderBundleEncoderDescriptor.withDepth({
    JSArray<JSString> colorFormats,
    String depthStencilFormat,
    int sampleCount,
    String label,
  });
}

/// A canvas, reduced to the one call a backend makes on it.
///
/// **Typed over `JSObject` rather than over `package:web`'s canvas element on
/// purpose.** This package does not depend on `package:web`, and the whole of
/// what presenting needs from an element is `getContext("webgpu")` — so an
/// embedder that has an `HTMLCanvasElement` from a platform-view registration,
/// and a test that has an `OffscreenCanvas`, both wrap it here and get the same
/// context back.
extension type GpuCanvas(JSObject element) implements JSObject {
  /// The WebGPU context, or null where this canvas already has a context of
  /// another kind — which is a mistake somewhere else and not a browser
  /// without WebGPU.
  external GPUCanvasContext? getContext(String contextId);
}

/// WebGPU's `GPUCanvasContext`: the link between a canvas and a device that
/// hands out one texture per frame to present.
extension type GPUCanvasContext._(JSObject _) implements JSObject {
  /// Attaches a device and settles what the canvas texture will be.
  ///
  /// Called again on every resize: a configured canvas keeps its size from the
  /// element, and reconfiguring is how a backend says the drawing buffer should
  /// follow.
  external void configure(GPUCanvasConfiguration configuration);

  /// Detaches the device and drops the textures, for a backend being disposed
  /// while its canvas outlives it.
  external void unconfigure();

  /// The texture to draw this frame into.
  ///
  /// **Valid for the task it was asked in and no longer.** It cannot be held
  /// across an `await`, which is why presenting is a copy into it rather than
  /// rendering into it: the engine's target already exists and the copy is one
  /// command on an encoder that is submitted immediately.
  external GPUTexture getCurrentTexture();
}

// ---------------------------------------------------------------- descriptors

/// WebGPU's `GPURequestAdapterOptions`: which adapter `requestAdapter` should
/// prefer.
extension type GPURequestAdapterOptions._(JSObject _) implements JSObject {
  /// [powerPreference] is `"low-power"` or `"high-performance"`, and
  /// [forceFallbackAdapter] asks for the software implementation — which is
  /// how whoever is chasing a driver bug gets a second opinion on the same
  /// machine.
  external factory GPURequestAdapterOptions({
    String powerPreference,
    bool forceFallbackAdapter,
  });
}

/// WebGPU's `GPUDeviceDescriptor`: the features and limits a device is
/// requested with.
extension type GPUDeviceDescriptor._(JSObject _) implements JSObject {
  /// [requiredFeatures] are names from [GpuFeature]; asking for one the adapter
  /// does not have rejects the promise rather than answering a device without
  /// it. [requiredLimits] is a plain object of name to number — see
  /// [gpuRequiredLimits], which builds one.
  external factory GPUDeviceDescriptor({
    String label,
    JSArray<JSString> requiredFeatures,
    JSObject requiredLimits,
  });
}

/// WebGPU's `GPUShaderModuleDescriptor`: the WGSL source of a module.
extension type GPUShaderModuleDescriptor._(JSObject _) implements JSObject {
  /// A module compiled from the WGSL in [code].
  external factory GPUShaderModuleDescriptor({String code, String label});
}

/// WebGPU's `GPUBufferDescriptor`: the size and usage a buffer is made with.
extension type GPUBufferDescriptor._(JSObject _) implements JSObject {
  /// [usage] is a bitwise or of [GpuBufferUsage] values, and [size] must be a
  /// multiple of four whenever [mappedAtCreation] is set.
  external factory GPUBufferDescriptor({
    int size,
    int usage,
    bool mappedAtCreation,
    String label,
  });
}

/// WebGPU's `GPUTextureDescriptor`: the size, format, usage and level count a
/// texture is made with.
extension type GPUTextureDescriptor._(JSObject _) implements JSObject {
  /// [usage] is a bitwise or of [GpuTextureUsage] values.
  ///
  /// A cube map is [dimension] `"2d"` with a size whose `depthOrArrayLayers` is
  /// six — the cube-ness is a property of the *view*, not of the texture, which
  /// is the one place this API is simpler than the ones the other three
  /// backends sit on.
  external factory GPUTextureDescriptor({
    GPUExtent3DDict size,
    String format,
    int usage,
    int sampleCount,
    int mipLevelCount,
    String dimension,
    String label,
  });
}

/// WebGPU's `GPUTextureViewDescriptor`: which levels, layers and aspect of a
/// texture a view sees, and as what dimension.
extension type GPUTextureViewDescriptor._(JSObject _) implements JSObject {
  /// [dimension] is `"2d"` for one face or one layer and `"cube"` for a whole
  /// cube map; [baseMipLevel] with a [mipLevelCount] of one is a level to
  /// render into, and [baseArrayLayer] with an [arrayLayerCount] of one is a
  /// face to render into.
  ///
  /// [aspect] is `"all"`, `"depth-only"` or `"stencil-only"`, and a
  /// depth-stencil texture bound for sampling needs one of the last two: a
  /// combined aspect cannot be sampled at all.
  external factory GPUTextureViewDescriptor({
    String format,
    String dimension,
    String aspect,
    int baseMipLevel,
    int mipLevelCount,
    int baseArrayLayer,
    int arrayLayerCount,
    String label,
  });
}

/// WebGPU's `GPUSamplerDescriptor`: addressing, filtering, level-of-detail
/// clamps and, for a shadow sampler, the comparison.
extension type GPUSamplerDescriptor._(JSObject _) implements JSObject {
  /// An ordinary sampler.
  ///
  /// [maxAnisotropy] above one is only honoured where every filter is
  /// `"linear"`, which is the same condition the other backends impose and the
  /// reason `GraphicsDevice.maxAnisotropy` is a number rather than a flag.
  external factory GPUSamplerDescriptor({
    String addressModeU,
    String addressModeV,
    String addressModeW,
    String magFilter,
    String minFilter,
    String mipmapFilter,
    double lodMinClamp,
    double lodMaxClamp,
    int maxAnisotropy,
    String label,
  });

  /// A shadow-map sampler, which is a different kind of object here.
  ///
  /// **`compare` is absent or it is a comparison sampler, and there is no third
  /// state.** Writing `compare: null` is the same `TypeError` that
  /// [GPUColorTargetState] documents — an absent dictionary member and an
  /// explicit null are different things — and a comparison sampler can only be
  /// bound to a `sampler_comparison` binding, so the two are not
  /// interchangeable at the call site either. Two constructors, so the choice
  /// is made where the shadow map is set up rather than discovered in a
  /// browser.
  external factory GPUSamplerDescriptor.comparison({
    String addressModeU,
    String addressModeV,
    String addressModeW,
    String magFilter,
    String minFilter,
    String mipmapFilter,
    String compare,
    double lodMinClamp,
    double lodMaxClamp,
    int maxAnisotropy,
    String label,
  });
}

/// WebGPU's `GPUExtent3DDict`: a size in texels.
extension type GPUExtent3DDict._(JSObject _) implements JSObject {
  /// A size of [width] by [height] texels by [depthOrArrayLayers], which is
  /// depth for a `"3d"` texture and a layer count otherwise. Omitted members
  /// are one.
  external factory GPUExtent3DDict({
    int width,
    int height,
    int depthOrArrayLayers,
  });
}

/// WebGPU's `GPUOrigin3DDict`: a corner in texels, for copies.
extension type GPUOrigin3DDict._(JSObject _) implements JSObject {
  /// [z] is the array layer for a 2D array or a cube — so a cube face is an
  /// origin and not a separate call.
  external factory GPUOrigin3DDict({int x, int y, int z});
}

/// WebGPU's `GPUColorDict`: a colour for clears and the blend constant.
extension type GPUColorDict._(JSObject _) implements JSObject {
  /// A colour whose channels are in the attachment's own units: a fraction
  /// from nought to one for a normalised format.
  external factory GPUColorDict({double r, double g, double b, double a});
}

// ----------------------------------------------------------------- bind groups

/// WebGPU's `GPUBindGroupLayoutEntry`: one binding slot of a bind group
/// layout.
extension type GPUBindGroupLayoutEntry._(JSObject _) implements JSObject {
  /// A uniform or storage buffer at [binding].
  ///
  /// **Exactly one of `buffer`, `sampler`, `texture` and `storageTexture` may
  /// be present, and this is why there are three constructors here rather than
  /// one with four optional members.** A layout entry with two of them is a
  /// validation error, one with none is a validation error, and both arrive
  /// asynchronously as a pipeline that does not work. Named constructors turn
  /// the whole question into one the compiler answers.
  ///
  /// [visibility] is a bitwise or of [GpuShaderStage] values.
  external factory GPUBindGroupLayoutEntry.buffer({
    int binding,
    int visibility,
    GPUBufferBindingLayout buffer,
  });

  /// A sampler at [binding]. See the buffer constructor for why these are
  /// separate.
  external factory GPUBindGroupLayoutEntry.sampler({
    int binding,
    int visibility,
    GPUSamplerBindingLayout sampler,
  });

  /// A sampled texture at [binding]. See the buffer constructor for why these
  /// are separate.
  external factory GPUBindGroupLayoutEntry.texture({
    int binding,
    int visibility,
    GPUTextureBindingLayout texture,
  });

  /// A storage texture at [binding]. See the buffer constructor for why these
  /// are separate.
  external factory GPUBindGroupLayoutEntry.storageTexture({
    int binding,
    int visibility,
    GPUStorageTextureBindingLayout storageTexture,
  });
}

/// WebGPU's `GPUStorageTextureBindingLayout`: a storage texture slot's access,
/// format and view dimension.
extension type GPUStorageTextureBindingLayout._(JSObject _)
    implements JSObject {
  /// [access] is `"write-only"`, `"read-only"` or `"read-write"`; [format] is
  /// the texture format the stage declared, which the bound view must match.
  external factory GPUStorageTextureBindingLayout({
    String access,
    String format,
    String viewDimension,
  });
}

/// WebGPU's `GPUBufferBindingLayout`: a buffer slot's kind, dynamic offset
/// and minimum size.
extension type GPUBufferBindingLayout._(JSObject _) implements JSObject {
  /// [type] is `"uniform"`, `"storage"` or `"read-only-storage"`.
  ///
  /// [hasDynamicOffset] is what lets one buffer hold every object's uniform
  /// block and one bind group serve the whole frame, with
  /// `GPURenderPassEncoder.setBindGroup`'s offsets choosing between them — and
  /// [minBindingSize] is the size the shader will read, checked once here
  /// rather than on every draw.
  external factory GPUBufferBindingLayout({
    String type,
    bool hasDynamicOffset,
    int minBindingSize,
  });
}

/// WebGPU's `GPUSamplerBindingLayout`: which kind of sampler a slot takes.
extension type GPUSamplerBindingLayout._(JSObject _) implements JSObject {
  /// [type] is `"filtering"`, `"non-filtering"` or `"comparison"`, and it has
  /// to agree with how the sampler was made: a comparison sampler in a
  /// filtering slot is refused, which is the layout side of the split
  /// [GPUSamplerDescriptor] makes.
  external factory GPUSamplerBindingLayout({String type});
}

/// WebGPU's `GPUTextureBindingLayout`: a sampled texture slot's sample type,
/// view dimension and multisampling.
extension type GPUTextureBindingLayout._(JSObject _) implements JSObject {
  /// [sampleType] is `"float"`, `"unfilterable-float"`, `"depth"`, `"sint"` or
  /// `"uint"`; [viewDimension] is `"2d"`, `"2d-array"` or `"cube"`.
  ///
  /// A 32-bit float texture is `"unfilterable-float"` unless the device asked
  /// for `float32-filterable`, and getting that wrong is a pipeline that will
  /// not build rather than a blurry picture.
  external factory GPUTextureBindingLayout({
    String sampleType,
    String viewDimension,
    bool multisampled,
  });
}

/// WebGPU's `GPUBindGroupLayoutDescriptor`: the entries of one bind group
/// layout.
extension type GPUBindGroupLayoutDescriptor._(JSObject _) implements JSObject {
  /// A layout of [entries], whose `binding` numbers must be unique.
  external factory GPUBindGroupLayoutDescriptor({
    JSArray<GPUBindGroupLayoutEntry> entries,
    String label,
  });
}

/// WebGPU's `GPUPipelineLayoutDescriptor`: the bind group layouts of a
/// pipeline layout.
extension type GPUPipelineLayoutDescriptor._(JSObject _) implements JSObject {
  /// The layouts, in group order: index zero of this list is `@group(0)`.
  external factory GPUPipelineLayoutDescriptor({
    JSArray<GPUBindGroupLayout> bindGroupLayouts,
    String label,
  });
}

/// WebGPU's `GPUBufferBinding`: a byte range of a buffer, as a bind group
/// entry's resource.
extension type GPUBufferBinding._(JSObject _) implements JSObject {
  /// [offset] must be a multiple of the device's
  /// `minUniformBufferOffsetAlignment`, and [size] omitted means the rest of
  /// the buffer.
  external factory GPUBufferBinding({GPUBuffer buffer, int offset, int size});
}

/// WebGPU's `GPUBindGroupEntry`: the resource bound at one binding number.
extension type GPUBindGroupEntry._(JSObject _) implements JSObject {
  /// A slice of a buffer at [binding].
  ///
  /// The IDL types `resource` as a union of three unrelated things, so this is
  /// three constructors for the reason [GPUBindGroupLayoutEntry] is three: a
  /// union typed as `JSAny` accepts anything at all, including the texture a
  /// caller meant to put in the next slot.
  external factory GPUBindGroupEntry.buffer({
    int binding,
    GPUBufferBinding resource,
  });

  /// A sampler at [binding].
  external factory GPUBindGroupEntry.sampler({
    int binding,
    GPUSampler resource,
  });

  /// A texture view at [binding].
  external factory GPUBindGroupEntry.textureView({
    int binding,
    GPUTextureView resource,
  });
}

/// WebGPU's `GPUBindGroupDescriptor`: a layout and the resources for each of
/// its bindings.
extension type GPUBindGroupDescriptor._(JSObject _) implements JSObject {
  /// A bind group against [layout]; [entries] must cover every binding the
  /// layout declares, each with a resource of the declared kind.
  external factory GPUBindGroupDescriptor({
    GPUBindGroupLayout layout,
    JSArray<GPUBindGroupEntry> entries,
    String label,
  });
}

// ----------------------------------------------------------------- the pass

/// WebGPU's `GPURenderPassColorAttachment`: one colour target of a pass, with
/// its load and store operations.
extension type GPURenderPassColorAttachment._(JSObject _) implements JSObject {
  /// A colour attachment with no resolve.
  external factory GPURenderPassColorAttachment({
    GPUTextureView view,
    GPUColorDict clearValue,
    String loadOp,
    String storeOp,
  });

  /// A multisampled attachment and the single-sampled texture it resolves into.
  ///
  /// **Absent and null differ here too.** `resolveTarget` is not a nullable
  /// member in the IDL, so the obvious translation of "resolve if the store
  /// action asks for one" — a nullable field written straight through — is the
  /// spelling this API refuses. `gpuResolves` answers which of the two
  /// constructors a `StoreAction` wants.
  external factory GPURenderPassColorAttachment.resolving({
    GPUTextureView view,
    GPUTextureView resolveTarget,
    GPUColorDict clearValue,
    String loadOp,
    String storeOp,
  });

  /// One slice of a 3D texture: [view] is a `"3d"` view of one level and
  /// [depthSlice] picks the slice. Required for a 3D view and refused for any
  /// other, so it is a constructor of its own.
  external factory GPURenderPassColorAttachment.slice({
    GPUTextureView view,
    int depthSlice,
    GPUColorDict clearValue,
    String loadOp,
    String storeOp,
  });
}

/// WebGPU's `GPURenderPassDepthStencilAttachment`: the depth-stencil target of
/// a pass, with per-aspect load, store and read-only state.
extension type GPURenderPassDepthStencilAttachment._(JSObject _)
    implements JSObject {
  /// A depth attachment on a format with no stencil aspect.
  ///
  /// **Naming the stencil operations on a depth-only format is an error, not a
  /// no-op**, so a single constructor with four optional members would let a
  /// shadow pass on `depth32float` be written the same way as one on
  /// `depth24plus-stencil8` and fail only on the first. The two are separated
  /// here, and `TextureFormat` already says which is which.
  external factory GPURenderPassDepthStencilAttachment.depthOnly({
    GPUTextureView view,
    double depthClearValue,
    String depthLoadOp,
    String depthStoreOp,
  });

  /// A combined depth-stencil attachment, both aspects stated.
  external factory GPURenderPassDepthStencilAttachment({
    GPUTextureView view,
    double depthClearValue,
    String depthLoadOp,
    String depthStoreOp,
    int stencilClearValue,
    String stencilLoadOp,
    String stencilStoreOp,
  });

  /// Every aspect the format has read-only: no load or store operation may
  /// be named for a read-only aspect, so this states none.
  external factory GPURenderPassDepthStencilAttachment.readOnly({
    GPUTextureView view,
    bool depthReadOnly,
    bool stencilReadOnly,
  });

  /// Depth read-only, the stencil loaded and stored as usual.
  external factory GPURenderPassDepthStencilAttachment.depthReadOnly({
    GPUTextureView view,
    bool depthReadOnly,
    int stencilClearValue,
    String stencilLoadOp,
    String stencilStoreOp,
  });

  /// The stencil read-only, depth loaded and stored as usual.
  external factory GPURenderPassDepthStencilAttachment.stencilReadOnly({
    GPUTextureView view,
    double depthClearValue,
    String depthLoadOp,
    String depthStoreOp,
    bool stencilReadOnly,
  });
}

/// WebGPU's `GPURenderPassDescriptor`: the attachments and queries of one
/// render pass.
extension type GPURenderPassDescriptor._(JSObject _) implements JSObject {
  /// A pass with colour attachments and no depth.
  external factory GPURenderPassDescriptor({
    JSArray<GPURenderPassColorAttachment> colorAttachments,
    String label,
  });

  /// A pass with a depth-stencil attachment as well.
  ///
  /// Separate for the reason every other pair in this file is separate:
  /// `depthStencilAttachment: null` is refused, and a `RenderPassDescriptor`
  /// whose `depth` is null is exactly what the contract hands a backend for
  /// every pass that does not want one.
  external factory GPURenderPassDescriptor.withDepth({
    JSArray<GPURenderPassColorAttachment> colorAttachments,
    GPURenderPassDepthStencilAttachment depthStencilAttachment,
    String label,
  });

  /// Where the pass writes its start and end times — `H2`. Set after the
  /// descriptor is built, only when there is one: the member left out means
  /// "none", and `null` is refused.
  external set timestampWrites(GPURenderPassTimestampWrites value);

  /// The occlusion query set `beginOcclusionQuery` writes into. Set only when
  /// there is one, for the reason [timestampWrites] is.
  external set occlusionQuerySet(GPUQuerySet value);
}

/// The two queries a pass writes its start and end times into. The same
/// dictionary serves a compute pass, whose IDL name differs and whose members
/// do not.
extension type GPURenderPassTimestampWrites._(JSObject _) implements JSObject {
  /// Both times written, at indices [beginningOfPassWriteIndex] and
  /// [endOfPassWriteIndex] of [querySet].
  external factory GPURenderPassTimestampWrites({
    GPUQuerySet querySet,
    int beginningOfPassWriteIndex,
    int endOfPassWriteIndex,
  });

  /// Only the start written: an absent index means "not written", and null is
  /// refused.
  external factory GPURenderPassTimestampWrites.beginning({
    GPUQuerySet querySet,
    int beginningOfPassWriteIndex,
  });

  /// Only the end written.
  external factory GPURenderPassTimestampWrites.end({
    GPUQuerySet querySet,
    int endOfPassWriteIndex,
  });
}

/// [set]'s writes at [beginning] and [end], each left out where null — the
/// one spelling `PassTimestampWrites` turns into. Null when neither is named.
GPURenderPassTimestampWrites? gpuTimestampWrites(
  GPUQuerySet set,
  int? beginning,
  int? end,
) => switch ((beginning, end)) {
  (final int b, final int e) => GPURenderPassTimestampWrites(
    querySet: set,
    beginningOfPassWriteIndex: b,
    endOfPassWriteIndex: e,
  ),
  (final int b, null) => GPURenderPassTimestampWrites.beginning(
    querySet: set,
    beginningOfPassWriteIndex: b,
  ),
  (null, final int e) => GPURenderPassTimestampWrites.end(
    querySet: set,
    endOfPassWriteIndex: e,
  ),
  (null, null) => null,
};

/// A set of queries — here only ever timestamps — `H2`.
extension type GPUQuerySet._(JSObject _) implements JSObject {
  /// The name a GPU debugger and the browser's errors show for it —
  /// `GraphicsDevice.setLabel`.
  external set label(String value);

  /// Frees the query set now; any later use of it is a validation error.
  external void destroy();
}

/// WebGPU's `GPUQuerySetDescriptor`: the kind and number of queries in a set.
extension type GPUQuerySetDescriptor._(JSObject _) implements JSObject {
  /// [count] queries of [type], `"timestamp"` or `"occlusion"`; a timestamp
  /// set needs [GpuFeature.timestampQuery] granted.
  external factory GPUQuerySetDescriptor({
    String type,
    int count,
    String label,
  });
}

// -------------------------------------------------------------- the pipeline

/// WebGPU's `GPUVertexAttribute`: one attribute inside a vertex buffer.
extension type GPUVertexAttribute._(JSObject _) implements JSObject {
  /// An attribute of [format] (such as `"float32x3"`), [offset] bytes into
  /// each element, read by the shader at `@location(shaderLocation)`.
  external factory GPUVertexAttribute({
    String format,
    int offset,
    int shaderLocation,
  });
}

/// WebGPU's `GPUVertexBufferLayout`: the stride, step mode and attributes of
/// one vertex buffer slot.
extension type GPUVertexBufferLayout._(JSObject _) implements JSObject {
  /// A slot whose elements are [arrayStride] bytes apart, stepping per
  /// `"vertex"` or per `"instance"` as [stepMode] says.
  external factory GPUVertexBufferLayout({
    int arrayStride,
    String stepMode,
    JSArray<GPUVertexAttribute> attributes,
  });
}

/// WebGPU's `GPUVertexState`: the vertex stage of a render pipeline.
extension type GPUVertexState._(JSObject _) implements JSObject {
  /// The vertex stage: [entryPoint] of [module], fed by [buffers] in slot
  /// order.
  external factory GPUVertexState({
    GPUShaderModule module,
    String entryPoint,
    JSArray<GPUVertexBufferLayout> buffers,
  });
}

/// WebGPU's `GPUBlendComponent`: the blend equation for the colour or the
/// alpha channel.
extension type GPUBlendComponent._(JSObject _) implements JSObject {
  /// `source * srcFactor (operation) destination * dstFactor`, where
  /// [operation] is `"add"`, `"subtract"`, `"reverse-subtract"`, `"min"` or
  /// `"max"`.
  external factory GPUBlendComponent({
    String operation,
    String srcFactor,
    String dstFactor,
  });
}

/// WebGPU's `GPUBlendState`: the colour and alpha blend equations of one
/// target.
extension type GPUBlendState._(JSObject _) implements JSObject {
  /// Blending with separate equations for [color] and [alpha].
  external factory GPUBlendState({
    GPUBlendComponent color,
    GPUBlendComponent alpha,
  });
}

/// WebGPU's `GPUColorTargetState`: the format, blending and write mask of one
/// colour target of a pipeline.
extension type GPUColorTargetState._(JSObject _) implements JSObject {
  /// A target with blending on. [writeMask] is a bitwise or of [GpuColorWrite]
  /// values and defaults to all four channels when it is left out.
  external factory GPUColorTargetState({
    String format,
    GPUBlendState blend,
    int writeMask,
  });

  /// Blending off, said by leaving the member out.
  ///
  /// **An absent key and an explicit null are different things to WebGPU**, and
  /// the difference is a `TypeError` at `createRenderPipeline` reading "the
  /// provided value is not of type 'GPUBlendState'". `PassEncoder.setBlend`
  /// takes a nullable state and null means off, so the obvious translation
  /// writes `blend: null` — which is the one spelling this API refuses. Two
  /// constructors rather than one nullable member, so the difference is made at
  /// the call site instead of discovered in a browser.
  external factory GPUColorTargetState.opaque({String format, int writeMask});
}

/// WebGPU's `GPUFragmentState`: the fragment stage of a render pipeline.
extension type GPUFragmentState._(JSObject _) implements JSObject {
  /// The fragment stage: [entryPoint] of [module], writing [targets] in
  /// `@location` order.
  external factory GPUFragmentState({
    GPUShaderModule module,
    String entryPoint,
    JSArray<GPUColorTargetState> targets,
  });
}

/// WebGPU's `GPUPrimitiveState`: topology, culling and winding of a render
/// pipeline.
extension type GPUPrimitiveState._(JSObject _) implements JSObject {
  /// A list topology — triangles, lines or points.
  ///
  /// [unclippedDepth] true needs `depth-clip-control`; false is legal on
  /// every device.
  external factory GPUPrimitiveState({
    String topology,
    String cullMode,
    String frontFace,
    bool unclippedDepth,
  });

  /// A strip topology, which needs the index format stated in the pipeline.
  ///
  /// **A strip pipeline that leaves `stripIndexFormat` out cannot be used for
  /// an indexed draw at all**, because a strip's restart value depends on the
  /// index width and WebGPU settles that when the pipeline is built rather than
  /// when the buffer is bound. `PrimitiveType.triangleStrip` and
  /// `PrimitiveType.lineStrip` are both in the contract, so this is a case a
  /// backend meets rather than a corner of the specification.
  external factory GPUPrimitiveState.strip({
    String topology,
    String cullMode,
    String frontFace,
    String stripIndexFormat,
    bool unclippedDepth,
  });
}

/// WebGPU's `GPUStencilFaceState`: the stencil test and operations for one
/// face orientation.
extension type GPUStencilFaceState._(JSObject _) implements JSObject {
  /// The test [compare] against the reference, and what to do to the stored
  /// value when the stencil test fails, the depth test fails, or both pass.
  external factory GPUStencilFaceState({
    String compare,
    String failOp,
    String depthFailOp,
    String passOp,
  });
}

/// WebGPU's `GPUDepthStencilState`: the depth and stencil state of a render
/// pipeline.
extension type GPUDepthStencilState._(JSObject _) implements JSObject {
  /// The depth and stencil half of a pipeline.
  ///
  /// All of it is pipeline state here and per-draw state in the contract, which
  /// is the divergence `command_encoder.dart` already names: the setters are
  /// accumulated and a pipeline is looked up at the draw. [stencilReadMask] and
  /// [stencilWriteMask] are pipeline state too — only the reference value is
  /// dynamic, which is why `setStencilReference` exists on the pass and its two
  /// masks do not.
  external factory GPUDepthStencilState({
    String format,
    bool depthWriteEnabled,
    String depthCompare,
    GPUStencilFaceState stencilFront,
    GPUStencilFaceState stencilBack,
    int stencilReadMask,
    int stencilWriteMask,
    int depthBias,
    double depthBiasSlopeScale,
    double depthBiasClamp,
  });
}

/// WebGPU's `GPUMultisampleState`: sample count, sample mask and
/// alpha-to-coverage of a render pipeline.
extension type GPUMultisampleState._(JSObject _) implements JSObject {
  /// [count] has to equal the sample count of every attachment the pipeline
  /// will be used with, which is why it is part of `WebGpuPipelineKey`.
  external factory GPUMultisampleState({
    int count,
    int mask,
    bool alphaToCoverageEnabled,
  });
}

/// WebGPU's `GPURenderPipelineDescriptor`: every stage and piece of state a
/// render pipeline is built from.
extension type GPURenderPipelineDescriptor._(JSObject _) implements JSObject {
  /// A pipeline for a pass with a depth-stencil attachment.
  ///
  /// [layout] is `GPUPipelineLayout | "auto"`, so it is typed as `JSAny`. A
  /// backend that hands over the string gets a layout inferred from the shader
  /// and a pipeline whose bind groups belong to it alone — two pipelines built
  /// that way cannot share a bind group even when their bindings are
  /// identical, which for a renderer with one camera block and forty materials
  /// is forty copies of the camera. So the string is for a spike and a real
  /// [GPUPipelineLayout] is for a backend.
  external factory GPURenderPipelineDescriptor({
    JSAny layout,
    GPUVertexState vertex,
    GPUFragmentState fragment,
    GPUPrimitiveState primitive,
    GPUDepthStencilState depthStencil,
    GPUMultisampleState multisample,
    String label,
  });

  /// A pipeline for a pass with colour attachments only.
  ///
  /// `depthStencil: null` is refused the way every other absent member in this
  /// file is, and a pass without depth is the common case rather than the
  /// corner: the whole of the post-processing chain is one.
  external factory GPURenderPipelineDescriptor.withoutDepth({
    JSAny layout,
    GPUVertexState vertex,
    GPUFragmentState fragment,
    GPUPrimitiveState primitive,
    GPUMultisampleState multisample,
    String label,
  });
}

// ------------------------------------------------------------------- copies

/// WebGPU's `GPUTexelCopyTextureInfo`: the texture side of a copy, down to a
/// level, an origin and an aspect.
extension type GPUTexelCopyTextureInfo._(JSObject _) implements JSObject {
  /// One side of a copy, or the destination of a `writeTexture`.
  ///
  /// [mipLevel] and [origin] together name a level of a face, which is what a
  /// mip chain upload and a cube-map readback both need and what the spike this
  /// file grew from left at zero.
  external factory GPUTexelCopyTextureInfo({
    GPUTexture texture,
    int mipLevel,
    GPUOrigin3DDict origin,
    String aspect,
  });
}

/// WebGPU's `GPUTexelCopyBufferLayout`: how texel rows and images are laid out
/// in linear memory.
extension type GPUTexelCopyBufferLayout._(JSObject _) implements JSObject {
  /// How texels are arranged in a buffer.
  ///
  /// [bytesPerRow] must be a multiple of 256 for a copy — `paddedBytesPerRow`
  /// is that arithmetic — and may be anything for a `writeTexture`, which is
  /// the one asymmetry in this API worth remembering.
  external factory GPUTexelCopyBufferLayout({
    int offset,
    int bytesPerRow,
    int rowsPerImage,
  });
}

/// Where `copyExternalImageToTexture` reads from: an `ImageBitmap` (typed as
/// the object it is, since nothing else in this file names a DOM type).
extension type GPUCopyExternalImageSourceInfo._(JSObject _)
    implements JSObject {
  /// The image [source]; [flipY] true copies it upside down, the bottom row
  /// first.
  external factory GPUCopyExternalImageSourceInfo({
    JSObject source,
    bool flipY,
  });
}

/// Where `copyExternalImageToTexture` writes. [premultipliedAlpha] false keeps
/// the straight alpha the bitmap was decoded with.
extension type GPUCopyExternalImageDestInfo._(JSObject _) implements JSObject {
  /// Level [mipLevel] of [texture], with alpha premultiplied into the colour
  /// where [premultipliedAlpha] is true.
  external factory GPUCopyExternalImageDestInfo({
    GPUTexture texture,
    int mipLevel,
    bool premultipliedAlpha,
  });
}

/// WebGPU's `GPUTexelCopyBufferInfo`: the buffer side of a copy, a buffer with
/// its row layout.
extension type GPUTexelCopyBufferInfo._(JSObject _) implements JSObject {
  /// [buffer] from byte [offset], rows [bytesPerRow] apart (a multiple of
  /// 256) and images [rowsPerImage] rows apart.
  external factory GPUTexelCopyBufferInfo({
    GPUBuffer buffer,
    int offset,
    int bytesPerRow,
    int rowsPerImage,
  });
}

/// WebGPU's `GPUCanvasConfiguration`: the device, format, usage and alpha
/// mode a canvas context is configured with.
extension type GPUCanvasConfiguration._(JSObject _) implements JSObject {
  /// [format] should be `GPU.getPreferredCanvasFormat`'s answer, [usage] a
  /// bitwise or of [GpuTextureUsage] values — `COPY_DST` and not
  /// `RENDER_ATTACHMENT` where presenting is a copy — and [alphaMode] is
  /// `"opaque"` or `"premultiplied"`.
  external factory GPUCanvasConfiguration({
    GPUDevice device,
    String format,
    int usage,
    String alphaMode,
    GPUCanvasToneMapping? toneMapping,
  });
}

/// How the browser maps a canvas's values to the display — `R9`: `standard`
/// clamps to the SDR range, `extended` lets an `rgba16float` canvas past it
/// on a display that can show it.
extension type GPUCanvasToneMapping._(JSObject _) implements JSObject {
  /// Tone mapping of [mode], `"standard"` or `"extended"`.
  external factory GPUCanvasToneMapping({String mode});
}

// -------------------------------------------------------------- error scopes

/// The three kinds of error a scope can be pushed for.
abstract final class GpuErrorFilter {
  /// A descriptor this API refused, which is every mistake in this file.
  static const String validation = 'validation';

  /// An allocation that did not fit.
  static const String outOfMemory = 'out-of-memory';

  /// The implementation's own failure, which a caller can do nothing about
  /// except report it.
  static const String internal = 'internal';
}

/// A WebGPU error that reached Dart, which without [gpuChecked] none of them
/// do.
final class GpuDeviceException extends ResourceException {
  /// A refusal of [what], carrying the browser's [message].
  const GpuDeviceException(this.what, this.message);

  /// What was being attempted — a caller's own words, since the browser's
  /// message names a dictionary member and not the pipeline it belonged to.
  final String what;

  /// The browser's own text, which is usually precise about which member was
  /// wrong and never says where in Dart it came from.
  @override
  final String message;

  @override
  String toString() => 'WebGPU refused $what: $message';
}

/// Runs [body] with a validation scope open, and throws where the browser
/// complained.
///
/// **This is the whole reason a backend on this API can report anything.**
/// WebGPU validates asynchronously: `createRenderPipeline` hands back a
/// pipeline object whether or not the descriptor was legal, and the complaint
/// goes to the browser console some time later, where no Dart program will ever
/// see it. A `GraphicsDevice` that means to throw — and the conformance suite's
/// refusal checks are written expecting one — has to bracket the call in a
/// scope and await the answer.
///
/// The cost is that every guarded call becomes asynchronous, which is why this
/// takes a synchronous [body] and returns its result: the object exists
/// immediately and only the verdict is awaited, so a backend can hand the
/// object on and let the check settle behind it.
///
/// Validation only. Out-of-memory and internal errors want a different response
/// from a caller — freeing something, or giving up — and a scope catches one
/// filter, so mixing them here would report an allocation failure as a
/// programming mistake.
Future<T> gpuChecked<T>(
  GPUDevice device,
  String what,
  T Function() body,
) async {
  device.pushErrorScope(GpuErrorFilter.validation);
  final T result;
  try {
    result = body();
  } catch (_) {
    // The scope is popped either way: leaving one open makes the *next*
    // pop answer for this call's errors, which reports the mistake against
    // whatever ran afterwards.
    await device.popErrorScope().toDart;
    rethrow;
  }
  final error = await device.popErrorScope().toDart;
  if (error != null) throw GpuDeviceException(what, error.message);
  return result;
}

/// [limits] as `GPUDeviceDescriptor.requiredLimits` takes them.
///
/// The IDL types it as a record of name to number, which has no Dart spelling
/// past `JSObject` — so the map is built here rather than at every call site
/// that wants one limit raised.
JSObject gpuRequiredLimits(Map<String, int> limits) {
  final object = JSObject();
  for (final entry in limits.entries) {
    object.setProperty(entry.key.toJS, entry.value.toJS);
  }
  return object;
}

/// [names] as this API takes a list of strings.
JSArray<JSString> gpuStrings(Iterable<String> names) =>
    <JSString>[for (final name in names) name.toJS].toJS;

// ----------------------------------------------------------------- the flags

/// What a buffer may be used for, declared when it is made and never after.
///
/// **Not a hint.** A buffer created with [vertex] cannot be bound as an index
/// buffer later, which is why `GeometryUsage` reaches this far down and is one
/// of the places the contract turned out not to be describing a single API.
abstract final class GpuBufferUsage {
  /// `MAP_READ`: mappable for reading; only with [copyDst] alongside.
  static const int mapRead = 0x0001;

  /// `MAP_WRITE`: mappable for writing; only with [copySrc] alongside.
  static const int mapWrite = 0x0002;

  /// `COPY_SRC`: the source of a copy command.
  static const int copySrc = 0x0004;

  /// `COPY_DST`: the destination of a copy or of `writeBuffer`.
  static const int copyDst = 0x0008;

  /// `INDEX`: bindable with `setIndexBuffer`.
  static const int index = 0x0010;

  /// `VERTEX`: bindable with `setVertexBuffer`.
  static const int vertex = 0x0020;

  /// `UNIFORM`: bindable as a uniform buffer.
  static const int uniform = 0x0040;

  /// `STORAGE`: bindable as a storage or read-only storage buffer.
  static const int storage = 0x0080;

  /// `INDIRECT`: holds the arguments of an indirect draw or dispatch.
  static const int indirect = 0x0100;

  /// `QUERY_RESOLVE`: the destination of `resolveQuerySet`.
  static const int queryResolve = 0x0200;
}

/// What a texture may be used for.
///
/// [renderAttachment] and [textureBinding] together are the ordinary case for
/// anything the renderer draws into and then samples; [copySrc] is what a
/// readback needs and is worth leaving off the textures nobody reads back.
abstract final class GpuTextureUsage {
  /// `COPY_SRC`: the source of a copy command.
  static const int copySrc = 0x01;

  /// `COPY_DST`: the destination of a copy, a `writeTexture` or an external
  /// image copy.
  static const int copyDst = 0x02;

  /// `TEXTURE_BINDING`: bindable as a sampled texture.
  static const int textureBinding = 0x04;

  /// `STORAGE_BINDING`: bindable as a storage texture.
  static const int storageBinding = 0x08;

  /// `RENDER_ATTACHMENT`: usable as a colour or depth-stencil attachment.
  static const int renderAttachment = 0x10;

  /// Contents that live for one pass and may never be given memory — `H7`.
  /// Only with [renderAttachment] and nothing else, and only where
  /// [gpuKnowsTransientAttachments] says the browser has it.
  static const int transientAttachment = 0x20;
}

/// Whether this browser's `GPUTextureUsage` has `TRANSIENT_ATTACHMENT`.
///
/// A property of the API rather than a feature the adapter grants, so it is
/// asked of the namespace object: a browser that predates the flag rejects a
/// texture that names it, and one that has it lists it there.
bool gpuKnowsTransientAttachments() {
  final usage = globalContext.getProperty<JSObject?>('GPUTextureUsage'.toJS);
  return usage != null && usage.has('TRANSIENT_ATTACHMENT');
}

/// Which stages a binding is visible to, for `GPUBindGroupLayoutEntry`.
abstract final class GpuShaderStage {
  /// `VERTEX`: the vertex stage sees the binding.
  static const int vertex = 0x1;

  /// `FRAGMENT`: the fragment stage sees the binding.
  static const int fragment = 0x2;

  /// `COMPUTE`: the compute stage sees the binding.
  static const int compute = 0x4;
}

/// The channels a colour target writes, for `GPUColorTargetState.writeMask`.
abstract final class GpuColorWrite {
  /// No channel: what a target the fragment stage writes nothing to must say.
  static const int none = 0x0;

  /// The red channel is written.
  static const int red = 0x1;

  /// The green channel is written.
  static const int green = 0x2;

  /// The blue channel is written.
  static const int blue = 0x4;

  /// The alpha channel is written.
  static const int alpha = 0x8;

  /// All four channels are written, the default when the mask is left out.
  static const int all = 0xF;
}

/// Which way a mapped buffer may be read, for `GPUBuffer.mapAsync`.
abstract final class GpuMapMode {
  /// Maps for reading; the buffer needs [GpuBufferUsage.mapRead].
  static const int read = 0x1;

  /// Maps for writing; the buffer needs [GpuBufferUsage.mapWrite].
  static const int write = 0x2;
}

/// The optional features worth asking an adapter about.
///
/// **Written out because a name this API does not know answers `false` rather
/// than failing**, so a misspelt feature string is a backend quietly reporting
/// that this machine cannot sample BC7 — on a machine that can.
///
/// The three compression families are the whole of why this list exists:
/// `TextureFormat` names compressed formats, `supportsTextureFormat` has to
/// answer for them honestly, and the honest answer is whether the adapter
/// carries the feature and the device asked for it.
abstract final class GpuFeature {
  /// Desktop block compression — BC1 through BC7.
  static const String textureCompressionBc = 'texture-compression-bc';

  /// The mobile OpenGL ES family.
  static const String textureCompressionEtc2 = 'texture-compression-etc2';

  /// The other mobile family, which most phones and no desktop carry.
  static const String textureCompressionAstc = 'texture-compression-astc';

  /// A combined depth-stencil format at full float precision, which shadow
  /// mapping on a large world wants and the baseline does not promise.
  static const String depth32FloatStencil8 = 'depth32float-stencil8';

  /// Linear filtering of 32-bit float textures. Without it an HDR target is
  /// `"unfilterable-float"` in a bind group layout and can only be read
  /// texel by texel.
  static const String float32Filterable = 'float32-filterable';

  /// Timestamps written at the start and end of a pass — `H2`.
  static const String timestampQuery = 'timestamp-query';

  /// `unclippedDepth` on a pipeline — `DeviceFeature.depthClamp`.
  static const String depthClipControl = 'depth-clip-control';

  /// A non-zero first instance in an indirect draw's arguments.
  static const String indirectFirstInstance = 'indirect-first-instance';

  /// The four `src1` blend factors.
  static const String dualSourceBlending = 'dual-source-blending';

  /// Blending into a 32-bit float attachment.
  static const String float32Blendable = 'float32-blendable';

  /// `rg11b10ufloat` as a colour attachment.
  static const String rg11b10Renderable = 'rg11b10ufloat-renderable';

  /// `f16` in WGSL.
  static const String shaderF16 = 'shader-f16';

  /// Subgroup built-ins in WGSL.
  static const String subgroups = 'subgroups';

  /// `clip_distances` in a vertex stage.
  static const String clipDistances = 'clip-distances';

  /// `multiDrawIndexedIndirect`, under the name the proposal gives it.
  static const String multiDrawIndirect = 'multi-draw-indirect';

  /// The same call, under the name Chromium ships it behind while the
  /// proposal settles. Either one granted is the feature.
  static const String multiDrawIndirectExperimental =
      'chromium-experimental-multi-draw-indirect';

  /// Every name this backend asks an adapter for, so the request and the
  /// test that holds the spellings read one list.
  static const List<String> requested = <String>[
    float32Filterable,
    depth32FloatStencil8,
    textureCompressionBc,
    textureCompressionEtc2,
    textureCompressionAstc,
    timestampQuery,
    depthClipControl,
    indirectFirstInstance,
    dualSourceBlending,
    float32Blendable,
    rg11b10Renderable,
    shaderF16,
    subgroups,
    clipDistances,
    multiDrawIndirect,
    multiDrawIndirectExperimental,
  ];
}

// ------------------------------------------------------------------ compute

/// A compiled compute pipeline — `H6`.
extension type GPUComputePipeline._(JSObject _) implements JSObject {
  /// The name a GPU debugger and the browser's errors show for it —
  /// `GraphicsDevice.setLabel`.
  external set label(String value);

  /// The layout of bind group [index] as the pipeline inferred it; only
  /// useful for a pipeline built with `layout: "auto"`.
  external GPUBindGroupLayout getBindGroupLayout(int index);
}

/// The stage a compute pipeline runs: a module and its entry point.
extension type GPUProgrammableStage._(JSObject _) implements JSObject {
  /// The stage running [entryPoint] of [module].
  external factory GPUProgrammableStage({
    GPUShaderModule module,
    String entryPoint,
  });
}

/// WebGPU's `GPUComputePipelineDescriptor`: a layout and the compute stage.
extension type GPUComputePipelineDescriptor._(JSObject _) implements JSObject {
  /// A pipeline running [compute] against the bind groups [layout] declares.
  external factory GPUComputePipelineDescriptor({
    GPUPipelineLayout layout,
    GPUProgrammableStage compute,
    String label,
  });
}

/// WebGPU's `GPUComputePassDescriptor`: a label and, optionally, timestamp
/// writes.
extension type GPUComputePassDescriptor._(JSObject _) implements JSObject {
  /// A compute pass named [label], with no timestamp writes.
  external factory GPUComputePassDescriptor({String label});

  /// Where the pass writes its start and end times; set only when there is
  /// one, as on a render pass.
  external set timestampWrites(GPURenderPassTimestampWrites value);
}

/// WebGPU's `GPUComputePassEncoder`: records the dispatches of one compute
/// pass.
extension type GPUComputePassEncoder._(JSObject _) implements JSObject {
  /// The debug group a GPU debugger shows around the commands until the
  /// matching pop — `PassEncoder.pushDebugGroup`.
  external void pushDebugGroup(String groupLabel);

  /// Closes the innermost [pushDebugGroup]; popping with none open is a
  /// validation error.
  external void popDebugGroup();

  /// A single named point a GPU debugger shows among the commands.
  external void insertDebugMarker(String markerLabel);

  /// Makes [pipeline] the one the following dispatches run.
  external void setPipeline(GPUComputePipeline pipeline);

  /// Binds [group] at `@group(index)`, for groups with no dynamic offsets.
  external void setBindGroup(int index, GPUBindGroup group);

  /// Runs [x] by [y] by [z] workgroups, the omitted counts one; each count
  /// is at most `maxComputeWorkgroupsPerDimension`.
  external void dispatchWorkgroups(int x, [int y, int z]);

  /// A dispatch whose grid [indirectBuffer] holds at [indirectOffset].
  external void dispatchWorkgroupsIndirect(
    GPUBuffer indirectBuffer,
    int indirectOffset,
  );

  /// Closes the pass and hands the encoder back to its command encoder.
  external void end();
}
