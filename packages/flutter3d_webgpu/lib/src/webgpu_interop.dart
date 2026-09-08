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
/// **What is deliberately absent:** compute pipelines, query sets, render
/// bundles, indirect draws and external textures. `flutter3d_hardware` asks for
/// none of them, and a declaration nobody calls is a declaration nobody has
/// checked against a browser.
@JS()
library;

import 'dart:js_interop';

// The one place a property is set by a name that is not known until run time:
// `GPUDeviceDescriptor.requiredLimits` is a record of limit name to number, and
// a record has no Dart spelling past `JSObject`. See [gpuRequiredLimits], which
// is the whole of this import's use.
import 'dart:js_interop_unsafe';

// ------------------------------------------------------------ getting a device

/// `navigator`, for the one property that says whether this browser has WebGPU
/// at all.
@JS('navigator')
external GpuNavigator get gpuNavigator;

extension type GpuNavigator._(JSObject _) implements JSObject {
  /// Null where the browser has no WebGPU, which is the answer a test runner on
  /// a machine with no GPU is most likely to get, and an ordinary case rather
  /// than a failure: a caller's move is to pick another backend.
  external GPU? get gpu;
}

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
/// A small slice of a long list: the ones a renderer actually plans around.
/// Everything else is a limit no scene in this repository comes near, and a
/// declaration nobody reads is a declaration nobody has checked.
extension type GPUSupportedLimits._(JSObject _) implements JSObject {
  external int get maxTextureDimension2D;
  external int get maxTextureArrayLayers;
  external int get maxBindGroups;
  external int get maxSamplersPerShaderStage;
  external int get maxSampledTexturesPerShaderStage;
  external int get maxUniformBufferBindingSize;
  external int get maxBufferSize;
  external int get maxVertexBuffers;
  external int get maxVertexAttributes;
  external int get maxColorAttachments;

  /// The alignment a dynamic uniform offset has to satisfy — 256 on every
  /// implementation so far, and the reason a per-object uniform block is padded
  /// out rather than packed.
  external int get minUniformBufferOffsetAlignment;
}

extension type GPUAdapterInfo._(JSObject _) implements JSObject {
  external String get vendor;
  external String get architecture;
  external String get device;
  external String get description;
}

extension type GPUDevice._(JSObject _) implements JSObject {
  external GPUQueue get queue;

  /// What was actually granted, which is not always what was asked for.
  external GPUSupportedFeatures get features;

  external GPUSupportedLimits get limits;

  /// Resolves when the device is gone — the tab lost its GPU, or something
  /// called [destroy].
  ///
  /// Never rejects, so a listener on it is a listener and not an error path.
  /// Read by whoever wants to tear the renderer down rather than let every
  /// subsequent call fail one at a time.
  external JSPromise<GPUDeviceLostInfo> get lost;

  external GPUShaderModule createShaderModule(GPUShaderModuleDescriptor d);
  external GPURenderPipeline createRenderPipeline(
    GPURenderPipelineDescriptor d,
  );
  external GPUBuffer createBuffer(GPUBufferDescriptor d);
  external GPUTexture createTexture(GPUTextureDescriptor d);
  external GPUSampler createSampler(GPUSamplerDescriptor d);
  external GPUBindGroupLayout createBindGroupLayout(
    GPUBindGroupLayoutDescriptor d,
  );
  external GPUPipelineLayout createPipelineLayout(
    GPUPipelineLayoutDescriptor d,
  );
  external GPUBindGroup createBindGroup(GPUBindGroupDescriptor d);
  external GPUCommandEncoder createCommandEncoder();

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

  external void destroy();
}

extension type GPUDeviceLostInfo._(JSObject _) implements JSObject {
  /// `"destroyed"` where something called `destroy`, `"unknown"` otherwise —
  /// which is the difference between a teardown and a crash.
  external String get reason;
  external String get message;
}

/// What a popped error scope hands back.
///
/// The three concrete kinds — validation, out of memory, internal — differ only
/// in which filter catches them, so one declaration covers all three and the
/// filter that was pushed says which arrived.
extension type GPUError._(JSObject _) implements JSObject {
  external String get message;
}

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

  external void submit(JSArray<GPUCommandBuffer> buffers);

  /// Resolves when everything submitted before the call has finished, which is
  /// exactly what `GraphicsDevice.onFrameComplete` promises.
  external JSPromise<JSAny?> onSubmittedWorkDone();
}

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

extension type GPUCompilationInfo._(JSObject _) implements JSObject {
  external JSArray<GPUCompilationMessage> get messages;
}

extension type GPUCompilationMessage._(JSObject _) implements JSObject {
  external String get message;

  /// `"error"`, `"warning"` or `"info"`. Only the first stops a pipeline
  /// working, and the other two are worth printing exactly once.
  external String get type;
  external int get lineNum;
  external int get linePos;
}

extension type GPURenderPipeline._(JSObject _) implements JSObject {
  /// The layout of one bind group, as the pipeline understood it.
  ///
  /// Only useful where the pipeline was built with `layout: "auto"`, and then
  /// it is the only way to get a layout object to build a bind group against.
  /// A backend that states its own [GPUPipelineLayout] never calls this — see
  /// [GPURenderPipelineDescriptor] for why stating one is the better half of
  /// that choice.
  external GPUBindGroupLayout getBindGroupLayout(int index);
}

extension type GPUPipelineLayout._(JSObject _) implements JSObject {}

extension type GPUBindGroupLayout._(JSObject _) implements JSObject {}

extension type GPUBindGroup._(JSObject _) implements JSObject {}

extension type GPUSampler._(JSObject _) implements JSObject {}

extension type GPUCommandBuffer._(JSObject _) implements JSObject {}

extension type GPUTextureView._(JSObject _) implements JSObject {}

extension type GPUTexture._(JSObject _) implements JSObject {
  external int get width;
  external int get height;
  external int get depthOrArrayLayers;
  external int get mipLevelCount;
  external int get sampleCount;
  external String get format;

  /// A view of the whole texture, or of the slice [descriptor] names.
  ///
  /// **The descriptor is what makes cube faces and render-to-mip possible.**
  /// `baseArrayLayer` picks a cube face and `baseMipLevel` picks a level to
  /// attach, and both of those are things the contract asks for —
  /// `createCubeRenderTarget` and `supportsRenderToMip` — that OpenGL ES needs
  /// separate machinery for and WebGPU treats as one ordinary attachment.
  external GPUTextureView createView([GPUTextureViewDescriptor descriptor]);

  external void destroy();
}

extension type GPUBuffer._(JSObject _) implements JSObject {
  external int get size;

  /// Maps a range for reading or writing, which is how a readback gets at its
  /// staging buffer.
  ///
  /// [offset] and [size] are bytes here, unlike `writeBuffer`'s. Omitted, the
  /// whole buffer is mapped.
  external JSPromise<JSAny?> mapAsync(int mode, [int offset, int size]);

  /// The mapped bytes. Valid only until [unmap], and a view rather than a copy,
  /// so a caller keeping the data past the unmap has to copy it out.
  external JSArrayBuffer getMappedRange([int offset, int size]);

  external void unmap();
  external void destroy();
}

extension type GPUCommandEncoder._(JSObject _) implements JSObject {
  external GPURenderPassEncoder beginRenderPass(GPURenderPassDescriptor d);

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

  external void copyTextureToBuffer(
    GPUTexelCopyTextureInfo source,
    GPUTexelCopyBufferInfo destination,
    GPUExtent3DDict copySize,
  );

  external GPUCommandBuffer finish();
}

extension type GPURenderPassEncoder._(JSObject _) implements JSObject {
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

  external void end();
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

extension type GPUShaderModuleDescriptor._(JSObject _) implements JSObject {
  external factory GPUShaderModuleDescriptor({String code, String label});
}

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
    String label,
  });
}

extension type GPUExtent3DDict._(JSObject _) implements JSObject {
  external factory GPUExtent3DDict({
    int width,
    int height,
    int depthOrArrayLayers,
  });
}

extension type GPUOrigin3DDict._(JSObject _) implements JSObject {
  /// [z] is the array layer for a 2D array or a cube — so a cube face is an
  /// origin and not a separate call.
  external factory GPUOrigin3DDict({int x, int y, int z});
}

extension type GPUColorDict._(JSObject _) implements JSObject {
  external factory GPUColorDict({double r, double g, double b, double a});
}

// ----------------------------------------------------------------- bind groups

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
}

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

extension type GPUSamplerBindingLayout._(JSObject _) implements JSObject {
  /// [type] is `"filtering"`, `"non-filtering"` or `"comparison"`, and it has
  /// to agree with how the sampler was made: a comparison sampler in a
  /// filtering slot is refused, which is the layout side of the split
  /// [GPUSamplerDescriptor] makes.
  external factory GPUSamplerBindingLayout({String type});
}

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

extension type GPUBindGroupLayoutDescriptor._(JSObject _) implements JSObject {
  external factory GPUBindGroupLayoutDescriptor({
    JSArray<GPUBindGroupLayoutEntry> entries,
    String label,
  });
}

extension type GPUPipelineLayoutDescriptor._(JSObject _) implements JSObject {
  /// The layouts, in group order: index zero of this list is `@group(0)`.
  external factory GPUPipelineLayoutDescriptor({
    JSArray<GPUBindGroupLayout> bindGroupLayouts,
    String label,
  });
}

extension type GPUBufferBinding._(JSObject _) implements JSObject {
  /// [offset] must be a multiple of the device's
  /// `minUniformBufferOffsetAlignment`, and [size] omitted means the rest of
  /// the buffer.
  external factory GPUBufferBinding({GPUBuffer buffer, int offset, int size});
}

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

extension type GPUBindGroupDescriptor._(JSObject _) implements JSObject {
  external factory GPUBindGroupDescriptor({
    GPUBindGroupLayout layout,
    JSArray<GPUBindGroupEntry> entries,
    String label,
  });
}

// ----------------------------------------------------------------- the pass

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
}

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
}

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
}

// -------------------------------------------------------------- the pipeline

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

extension type GPUFragmentState._(JSObject _) implements JSObject {
  external factory GPUFragmentState({
    GPUShaderModule module,
    String entryPoint,
    JSArray<GPUColorTargetState> targets,
  });
}

extension type GPUPrimitiveState._(JSObject _) implements JSObject {
  /// A list topology — triangles, lines or points.
  external factory GPUPrimitiveState({
    String topology,
    String cullMode,
    String frontFace,
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
  });
}

extension type GPUStencilFaceState._(JSObject _) implements JSObject {
  external factory GPUStencilFaceState({
    String compare,
    String failOp,
    String depthFailOp,
    String passOp,
  });
}

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

extension type GPUMultisampleState._(JSObject _) implements JSObject {
  /// [count] has to equal the sample count of every attachment the pipeline
  /// will be used with, which is why it is part of `WebGpuPipelineKey`.
  external factory GPUMultisampleState({
    int count,
    int mask,
    bool alphaToCoverageEnabled,
  });
}

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

extension type GPUTexelCopyBufferInfo._(JSObject _) implements JSObject {
  external factory GPUTexelCopyBufferInfo({
    GPUBuffer buffer,
    int offset,
    int bytesPerRow,
    int rowsPerImage,
  });
}

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
  });
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
final class GpuDeviceError implements Exception {
  const GpuDeviceError(this.what, this.message);

  /// What was being attempted — a caller's own words, since the browser's
  /// message names a dictionary member and not the pipeline it belonged to.
  final String what;

  /// The browser's own text, which is usually precise about which member was
  /// wrong and never says where in Dart it came from.
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
  if (error != null) throw GpuDeviceError(what, error.message);
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
  static const int mapRead = 0x0001;
  static const int mapWrite = 0x0002;
  static const int copySrc = 0x0004;
  static const int copyDst = 0x0008;
  static const int index = 0x0010;
  static const int vertex = 0x0020;
  static const int uniform = 0x0040;
  static const int storage = 0x0080;
  static const int indirect = 0x0100;
  static const int queryResolve = 0x0200;
}

/// What a texture may be used for.
///
/// [renderAttachment] and [textureBinding] together are the ordinary case for
/// anything the renderer draws into and then samples; [copySrc] is what a
/// readback needs and is worth leaving off the textures nobody reads back.
abstract final class GpuTextureUsage {
  static const int copySrc = 0x01;
  static const int copyDst = 0x02;
  static const int textureBinding = 0x04;
  static const int storageBinding = 0x08;
  static const int renderAttachment = 0x10;
}

/// Which stages a binding is visible to, for `GPUBindGroupLayoutEntry`.
abstract final class GpuShaderStage {
  static const int vertex = 0x1;
  static const int fragment = 0x2;
  static const int compute = 0x4;
}

/// The channels a colour target writes, for `GPUColorTargetState.writeMask`.
abstract final class GpuColorWrite {
  static const int red = 0x1;
  static const int green = 0x2;
  static const int blue = 0x4;
  static const int alpha = 0x8;
  static const int all = 0xF;
}

/// Which way a mapped buffer may be read, for `GPUBuffer.mapAsync`.
abstract final class GpuMapMode {
  static const int read = 0x1;
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
}
