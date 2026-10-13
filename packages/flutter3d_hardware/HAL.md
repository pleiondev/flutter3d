# The hardware abstraction layer

`flutter3d_hardware` is the interface the engine draws through and a graphics
backend implements. This file describes all of it, for two readers: a
contributor changing the engine or one of its four backends, and the author of
a backend outside the repository (Vulkan, Metal without Flutter GPU, a
console, a headless server renderer).

The authority is the API snapshot,
[`api/flutter3d_hardware.api`](api/flutter3d_hardware.api): every public
name and signature below is checked against it. The rationale behind the
rules lives elsewhere and is linked rather than repeated:
[ARCHITECTURE.md §7](../../ARCHITECTURE.md#7-the-backend-contract) for the
backend contract, [CONTRACTS.md, "The shader ABI"](../../docs/CONTRACTS.md#the-shader-abi)
for what shaders agree on, [CONTRIBUTING.md, "The API is a snapshot"](../../CONTRIBUTING.md#the-api-is-a-snapshot)
for what counts as a break, and the site's
[backend guide](https://flutter3d.pleion.dev/core/backends/) for the
walkthrough.

Contents:

1. [What the HAL is and is not](#what-the-hal-is-and-is-not)
2. [The stability promise](#the-stability-promise)
3. [`GraphicsDevice`](#graphicsdevice)
4. [Capabilities](#capabilities)
5. [Resources](#resources)
6. [Descriptors and `checkFeatures`](#descriptors-and-checkfeatures)
7. [Pipelines](#pipelines)
8. [Encoders](#encoders)
9. [Compute](#compute)
10. [Shaders](#shaders)
11. [Lifetime](#lifetime)
12. [Threading and asynchronous answers](#threading-and-asynchronous-answers)
13. [Refusals](#refusals)
14. [Conformance](#conformance)
15. [The backends](#the-backends)
16. [Testing helpers](#testing-helpers)
17. [Coverage and growth](#coverage-and-growth)
18. [Writing a fifth backend](#writing-a-fifth-backend)

## What the HAL is and is not

The HAL is a vocabulary: texture, buffer and geometry handles, formats,
samplers, render targets, pipelines, four kinds of encoder, a shader library
and the bundle format a library is loaded from, capabilities as one typed
answer, and the refusals a device gives. It contains no implementation of any
of it. An engine written against it is handed a backend as a value, so the
software rasteriser draws the same frame a GPU does and a test can check that
it did.

Two structure rules in `tool/structure.dart` keep the layering honest, and
both run on every check of the repository:

| Rule | What it holds |
|---|---|
| `the hardware layer names no graphics API` | No file under this package's `lib/` reaches `flutter_gpu`, and the pubspec does not depend on it. Backends depend on the HAL, never the reverse. |
| `the hardware layer names no Flutter` | No file here imports `dart:ui` or `package:flutter/`. The vocabulary is the package's own. |
| `the engine names no backend` | `flutter3d_core` names no `flutter_gpu` and depends on neither `flutter_gpu` nor `flutter3d_impeller`, and does depend on this package. An application chooses a backend; the engine does not. |

What is deliberately absent:

- **Device enumeration, swapchains and windows.** An application opens a
  backend and hands it over. Each engine owns a `DeviceRegistry`
  (`addBackend`, `open`), and what shows a finished frame is a presenter
  added with `addPresenter<T>` and found with `presenterFor`. A device never
  presents.
- **Globals.** A `GraphicsDevice` is a value. Two engines in one isolate open
  devices of their own, and a fake can stand in for any device.
- **Anything a backend can decide for itself**: memory allocation, staging,
  pipeline state objects and their caches, descriptor layouts, barriers.

## The stability promise

From 1.0 this package follows strict semver, and every backend depends on it
through a caret range. The engine's packages share one major.minor, and each
takes patches of its own; `flutter3d_hardware` is versioned with them. This package has
no `internal.dart`: everything it exports is promised.

| A 1.x minor may | A 1.x minor may not |
|---|---|
| add a member with a body to `GraphicsDevice`, `PassEncoder`, `ComputeEncoder`, `TransferEncoder` (a feature-gated one refuses by its feature) | add a member without a body to any type a backend extends |
| add a named parameter with a default to a descriptor's constructor, and the field behind it | change or remove anything listed in the snapshot |
| add a constant to an open class: `DeviceFeature`, `TextureFormat`, `TextureDimension`, `ShaderStageKind`, `QueryType`, `NativeHandleKind`, `ComputePlacement`, `StorageMode` and the rest | add a value to one of the five enums that remain (`CompareFunction`, `FramebufferOrigin`, `StencilFace`, `StorageTextureAccess`, `WindingOrder`), each closed for good with its reason in `tool/structure/repository.dart` |
| turn a reserved `DeviceFeature` stable and give it calls | change what an existing call means to a backend that already implements it |
| add a field with a default to `StageBindings` or `UniformMemberLayout` (a new binding kind) | change an abstract member's signature, including adding an optional parameter to a member backends override |
| add a top-level type or function | |

**Open classes, not enums.** Every set that can grow is a `final class` with
`static const` members, a private constructor, `values`, `name` and `byName`
(the shape of `DeviceFeature`). A `switch` over one ends with a wildcard that
refuses the value by name or answers something it can name. CONTRIBUTING has
the rule and the classifier that enforces it.

`package:flutter3d_hardware/backend.dart` (the handle constructors and
`debugCheckLive`) and `package:flutter3d_hardware/testing.dart` are in the
snapshot and held to the same rule: a constructor there gains only optional
named parameters within a major, so a backend written against 1.0.0 compiles
against every 1.x.

## `GraphicsDevice`

`abstract base class GraphicsDevice with TextureAllocator`. A backend
`extends` it.

### What every backend implements

These members have no body. A backend does not compile until each is there.

| Member | What it answers or does |
|---|---|
| `TextureFormat get defaultColorFormat` | The colour format this device prefers. |
| `TextureFormat get defaultDepthStencilFormat` | The depth/stencil format it prefers; `TextureFormat.unknown` on a context with none. |
| `TextureFormat get hdrColorFormat` | A colour target with range above one that this device can render into. A wrong answer is an incomplete framebuffer and a frame of transparent black. |
| `FramebufferOrigin get framebufferOrigin` | Where row zero of a render target is (`topLeft` or `bottomLeft`). |
| `DepthRange get depthRange` | What clip space maps depth onto (`zeroToOne` or `negativeOneToOne`). |
| `int get preferredSampleCount` | Samples for multisampled targets, 1 for none. |
| `DeviceFeatures get features` | Every optional capability, as one set. |
| `DeviceLimits get limits` | How much of everything. |
| `TextureFormatSupport textureFormatSupport(TextureFormat format)` | What a format can be used for; `TextureFormatSupport.none` for one the device cannot allocate. |
| `ShaderLibrary get shaders` | The engine's stages, by name. |
| `Future<LoadedShaderLibrary> loadShaders(ByteData bytes)` | A library from a `ShaderBundle` that arrived as bytes. |
| `PipelineHandle createPipeline(ShaderHandle vertex, ShaderHandle fragment, {VertexLayoutDescriptor? layout})` | Links a stage pair. |
| `GeometryBuffer uploadGeometry(ByteData bytes, GeometryUsage usage)` | Geometry that outlives the frame. |
| `void overwriteGeometry(GeometryBuffer target, int offsetInBytes, ByteData bytes)` | Writes into it in place, visible from the next pass. |
| `void releaseGeometry(GeometryBuffer geometry)` | Gives one buffer back. |
| `TextureHandle createTexture(TextureDescriptor descriptor)` | From `TextureAllocator`, so `RenderTargetPool` takes the device directly. |
| `void releaseTexture(TextureHandle texture)` | From `TextureAllocator`. |
| `TextureHandle createTextureFromPixels({required int width, required int height, required TextureFormat format, required ByteData pixels, List<ByteData>? mipLevels})` | One call rather than create-then-write. The chain is supplied (`MipChain.build`), never generated. |
| `TextureHandle createCubeTextureFromPixels({required int size, required TextureFormat format, required List<ByteData> faces, List<List<ByteData>>? mipLevels})` | Six faces in the order +X, −X, +Y, −Y, +Z, −Z. |
| `TextureHandle createCubeRenderTarget({required int size, required TextureFormat format, int mipLevels = 1})` | A cube a pass draws into, face by face and level by level. |
| `Future<void> overwriteTexture(TextureHandle target, ByteData rgba, {ScreenRect? region, int mipLevel = 0})` | RGBA8 into the base level of a texture in `readbackFormats`. |
| `Future<ByteData> readback(TextureHandle texture, {ScreenRect? region})` | The pixels as the passes submitted before the call left them, RGBA8, rows from the top. |
| `void beginFrame()` | A new frame starts; rotate whatever has to rotate. |
| `void onFrameComplete(void Function() whenDone)` | Runs `whenDone` once the GPU has finished the frame being encoded. |
| `CommandEncoder beginRenderPass(RenderPassDescriptor descriptor)` | Opens a pass. |
| `void dispose()` | Releases everything the device made. |

A device that cannot do what one of these asks (a cube on a device without
`cubeTextures`) still implements it, and the body refuses:
`throw refuse(DeviceFeature.cubeTextures)`.

### What has a default

Every other member has a body. A feature-gated default throws
`UnsupportedCapabilityException` naming its feature; a debugging courtesy
does nothing. A backend overrides a member when it implements the feature and
adds the feature to `features` in the same change.

| Group | Member | Default |
|---|---|---|
| Identity | `String get backendName` | the runtime type |
| | `String get backendId` | `backendName` in lower case; override with a constant |
| Refusal builders (`@protected`) | `refuse(DeviceFeature feature, {String? reason})` | an `UnsupportedCapabilityException` naming `backendName` |
| | `refuseResource(String operation, String reason, {Object? cause})` | a `DeviceResourceException` naming `backendName` |
| Pipelines | `createPipelineAsync(...)` | `createPipeline` in the calling turn, as a completed future |
| | `releasePipeline(PipelineHandle)` | nothing |
| | `PipelineRefusals get pipelineRefusals` | a record kept by the base class |
| Compute | `createComputePipeline(ShaderHandle)` | refuses `compute` |
| | `createComputePipelineAsync(ShaderHandle)` | `createComputePipeline`, as a future |
| | `beginComputePass({String? label, PassTimestampWrites? timestampWrites})` | refuses `compute` |
| | `releaseComputePipeline(ComputePipelineHandle)` | nothing |
| Buffers | `createBuffer(BufferDescriptor, {ByteData? contents})` | refuses `buffers` |
| | `writeBuffer(StorageBuffer, int, ByteData)` | refuses `buffers` |
| | `readBuffer(StorageBuffer)` | a future failing with the `compute` refusal |
| | `mapBuffer(StorageBuffer, MapMode, {int offsetInBytes, int? sizeInBytes})` | a future failing with the `mappedBuffers` refusal |
| | `releaseStorageBuffer(StorageBuffer)` | nothing |
| Textures | `writeTexture(TextureHandle, ByteData, {TextureRegion? region, int mipLevel, int? bytesPerRow})` | refuses `textureWrites` |
| | `releaseSampler(SamplerDescriptor)` | nothing |
| | `List<TextureFormat> get hdrOutputFormats` | empty |
| Transfers | `beginTransferPass({String? label})` | a pass whose every copy refuses by its own feature |
| Queries | `createQuerySet(QueryType, int)` | refuses the type's feature |
| | `readQueryResults(QuerySet, {int first, int? count})` | a future failing with the type's refusal |
| | `releaseQuerySet(QuerySet)` | nothing |
| Bundles | `createRenderBundleEncoder(RenderBundleDescriptor)` | refuses `renderBundles` |
| | `releaseRenderBundle(RenderBundle)` | nothing |
| Sharing | `Set<NativeHandleKind> get shareableKinds` | empty |
| | `exportTexture`, `importTexture` | refuse `sharedTextures` |
| | `exportBuffer`, `importBuffer` | refuse `sharedBuffers` |
| | `createFence`, `signalFence`, `waitFence`, `exportFence`, `importFence` | refuse `sharedFences` |
| | `releaseFence(GpuFence)` | nothing |
| Loss | `Stream<DeviceLoss> get lost` | an empty stream ("never lost") |
| | `bool get isLost` | false |
| Timing | `onGpuTimings(void Function(GpuFrameTimings)? listener)` | nothing |
| Labels | `setLabel(Object resource, String label)`, `labelOf(Object resource)` | kept in an `Expando`, read back by `labelOf` |

A backend whose API carries labels passes `setLabel` on as well. The empty
`lost` stream is a default to replace, not an answer: every backend owes a
`DeviceLoss` at least for its own `dispose`.

### `TextureAllocator`

`abstract base mixin class TextureAllocator` has two members,
`createTexture(TextureDescriptor)` and `releaseTexture(TextureHandle)`. It
exists so `RenderTargetPool` can take a device (or a test's allocator)
directly: every texture in the engine is created by one rule.
`RenderTargetPool` lends by `RenderTargetDescriptor` and by identity
(`TextureHandle` has no `==` on purpose), and a cube never enters it.

### `backendName` and `backendId`

`backendName` is for people: refusals carry it ("WebGL2", "the software
rasteriser"). `backendId` is for matching: a `MaterialCompiler`'s `backend`,
a plugin manifest and `RuntimeShaders` compare it exactly. It is short, lower
case and fixed for good once a backend ships: `cpu`, `webgl`, `webgpu`,
`impeller`, and `wgpu` for the compute sidecar. The default follows
`backendName`, so a backend that rewords its name for people would silently
change its id; override `backendId` with a constant.

**What grows in a minor**: members with bodies. **What is frozen**: every
member in the first table and its signature, and the meaning of every
default.

## Capabilities

`features`, `limits` and `textureFormatSupport` are the whole report. The
pre-1.0 `supportsX` getters are gone; `dart run flutter3d_build:migrate`
rewrites each into the question that replaced it.

### `DeviceFeature` and `Capability`

`DeviceFeature` is a `final class` extending `Capability` from
`flutter3d_foundation`, so a refusal of one is the foundation's
`UnsupportedCapabilityException`, the type every layer throws. Its `name` is
WebGPU's spelling where WebGPU has the feature and the engine's own
otherwise; `askedBy` answers `` `GraphicsDevice.features` ``. Each carries a
`FeatureStability`:

- **`stable`**: the calls exist and are promised. A device without the
  feature refuses them.
- **`reserved`**: named so nothing else takes the name, implemented nowhere.
  `DeviceFeatures` throws an `ArgumentError` for a set that lists one. A minor
  gives one its calls and turns it stable. The reserved features at 1.0:
  `asyncCompute`, `bindlessResources`, `conservativeRasterization`,
  `depthBounds`, `depthResolve`, `immediateData`, `meshShaders`,
  `presenterColorSpaces`, `rayQuery`, `shaderInt64`, `variableRateShading`.

Compare features by identity or by `name`. `DeviceFeature.values` lists all
of them; `byName` reads a name a report wrote.

### `DeviceFeatures`

An immutable set. `has(feature)` asks one question; `all` lists what the
device has and `missing` what it lacks (reserved ones included);
`union` and `without` derive another set (a test narrows a real device's
answer with `without`). `require(feature, backend:, reason:)` throws the
refusal and is what a backend calls on the way into every gated call, so all
backends refuse in the same words. `DeviceFeatures.none` is what a fake
starts from.

**Three capabilities are types rather than members**, asked with `is`:

| Type | Mixed into | The feature that names the same thing |
|---|---|---|
| `EncodedImageUpload` (`decodeTexture`) | a device | none |
| `SynchronousBufferReadback` (`readBufferSync`) | a device; exported from `backend.dart` and `testing.dart`, not the main library | `synchronousReadback` |
| `RenderBundleEncoder` (`finish`) | an encoder | `renderBundles` |

Where a feature names the same thing, a device lists it exactly when it is
the type.

### Limits and formats

`DeviceLimits` is a value with one field per limit; its constructor's
defaults are WebGPU's guaranteed minimums (`DeviceLimits.webgpuDefaults`),
plus `maxImmediateDataSize` and `maxMultiviewViews`, both 0 by default. A
device without compute sets the compute limits to 0. Two limits behave
differently from the rest:

- `maxSamplerAnisotropy` is the one limit a request may exceed: a backend
  clamps `SamplerDescriptor.anisotropy` to it rather than refusing.
- `maxColorAttachments` refuses: a backend calls
  `descriptor.checkAttachmentLimit(limits.maxColorAttachments, backend:)` in
  `beginRenderPass`.

`textureFormatSupport` answers a `TextureFormatSupport` (`sampled`,
`filterable`, `renderable`, `blendable`, `multisample`, `resolve`,
`depthStencil`, `storage`, `storageReadWrite`). A compression family's
feature (`textureCompressionBC` and its siblings) must agree with the
per-format answers, which the honesty check verifies.

**Answer honestly, in both directions.** A feature listed must work when its
probe calls it, and a feature not listed must be refused by that feature's
name. The cost of each wrong answer is tabled in the
[backend guide](https://flutter3d.pleion.dev/core/backends/#features).

**What grows in a minor**: `DeviceFeature` constants (stable or reserved),
`DeviceLimits` fields with defaults, `TextureFormatSupport` fields,
`FeatureStability` values. **What is frozen**: every feature's `name`, the
meaning of every limit, and the rule that a reserved feature is never
reported.

## Resources

A handle carries a description and an opaque `backend` object. Its
constructor is private: a backend makes handles through `backend.dart`
(`wrapTexture`, `wrapGeometry`, `wrapPipeline`, `wrapShader`,
`wrapStorageBuffer`, `wrapQuerySet`, `wrapFence`, `wrapComputePipeline`,
`wrapRenderBundle`), naming itself as the `owner` so that a handle's
`dispose` comes back to its `release…` member. `wrapGeometry` and
`wrapShader` take a `release` callback instead.

### Textures

`TextureDescriptor` (`base class`, extended by `RenderTargetDescriptor`)
takes `width`, `height`, `format`, `dimension` (`TextureDimension.d2` by
default), `depthOrArrayLayers` (1), `mipLevelCount` (1), `sampleCount` (1),
`usage` (`TextureUsage.standard`), `storageMode`
(`StorageMode.devicePrivate`) and `label`.

| Field | Values |
|---|---|
| `dimension` | `d1`, `d2`, `d2Array`, `d3`, `cube`, `cubeArray` (an open class) |
| `usage` | bits: `sampled`, `renderTarget`, `storage`, `copySource`, `copyDestination`; `standard` is all but `storage` |
| `storageMode` | `hostVisible`, `devicePrivate`, `deviceTransient` (tile memory: never loaded, never read back) |
| `format` | `TextureFormat`, an open class with a fixed `index` per value: eight-bit colour in linear and sRGB, the float and integer colour formats, the packed `r10g10b10a2UNormInt`, `r11g11b10UFloat` and `r9g9b9e5UFloat`, the BC, ETC2 and ASTC families (ASTC with HDR variants), and depth and stencil (`d16UNormInt`, `d24UnormS8Uint`, `d32Float`, `d32FloatS8UInt`, `s8UInt`) |

`TextureFormatInfo`, `TextureFormatCompression` and `TextureFormatStencil`
answer per format: `bytesPerTexel`, `sampleKind`, `isDepthOrStencil`,
`isInteger`, `isSrgb`, `isCompressed`, `blockLayout`, `hasStencil`.

**The derived fields.** A `TextureHandle` carries the descriptor's facts and
two derived from `dimension`: `type` (`TextureType.textureCube` for a cube
or a cube array, otherwise what the backend named, `texture2D` unless it said
`textureExternalOES`) and `sliceCount` (6 for a cube or cube array, 1
otherwise). `wrapTexture` reads the shape from `dimension`; the pre-1.0
`type:` alone still works, and an `ArgumentError` refuses a `type` and a
`dimension` that disagree. Multisampling is said by `sampleCount`, never by
`type`. `estimatedBytes` counts every level, layer and sample.

### Buffers

There are two kinds. `GeometryBuffer` is what `uploadGeometry` makes: vertices
or indices for life (`GeometryUsage` is not a hint; WebGL binds a buffer to
its target permanently), sliceable with `slice`. `StorageBuffer` is what
`createBuffer(BufferDescriptor)` makes, the general form:

| `BufferUsage` bit | Needs |
|---|---|
| `vertex`, `index` | `buffers`; reachable as `StorageBuffer.asVertices` / `asIndices` |
| `uniform` | `buffers` |
| `storage` | `compute` or `renderStageStorage` |
| `indirect` | `indirectDraw` or `indirectDispatch` |
| `copySource`, `copyDestination` | `buffers` |
| `hostReadable`, `hostWritable` | `buffers`; mapping needs `mappedBuffers` |

`BufferUsage.standardStorage` is storage plus both copies, a compute pass's
buffer. `createBuffer` is the one way to make a storage buffer since 1.0.

### Samplers

A sampler is a value, never a handle: a `SamplerDescriptor` is handed to every
`bindTexture`. Fields: `minFilter`, `magFilter` (`MinMagFilter`),
`mipFilter` (`MipFilter`), `widthAddressMode`, `heightAddressMode`,
`depthAddressMode` (`SamplerAddressMode`: `clampToEdge`, `repeat`,
`mirror`), `anisotropy` (1; above 1 only on a trilinear sampler),
`compare` (`samplerCompare`), `lodMinClamp` and `lodMaxClamp` (0 and 32;
`samplerLodClamp` when changed), `borderColor` (`samplerBorderColor`).
Named values: `nearestClamp`, `linearClamp`, `linearRepeat`,
`trilinearRepeat`. **A null sampler means `linearRepeat`**, not the
constructor's own defaults. A backend whose API wants an object per
description makes one and keeps it until `releaseSampler`.

### Render targets

A pass draws into `ColorTarget`s and an optional `DepthTarget`, each naming
a texture, a `face`, a `mipLevel` and a `layer`, a `LoadAction` (`dontCare`,
`load`, `clear`) and a `StoreAction` (`dontCare`, `store`,
`multisampleResolve`, `storeAndMultisampleResolve`). A colour target may
name a `resolveTexture`; a depth target carries the stencil's actions and
clear value and `depthReadOnly` / `stencilReadOnly`. `RenderTargetPool`
lends 2D targets keyed by `RenderTargetDescriptor` and `trim`s what is
unused; `createCubeRenderTarget` makes the cubes, outside the pool.

### Sharing: `SharedTexture`, `SharedBuffer`, `GpuFence`

`SharedTexture.create(producer:, consumer:, descriptor:, demand:)` and its
buffer twin give two devices one resource. Zero copy (`SharingMode.zeroCopy`)
needs `sharedTextures` (or `sharedBuffers`) on both, a `NativeHandleKind` in
both `shareableKinds`, and `sharedFences` to order them; otherwise the copy
through host memory (`SharingMode.hostCopy`) runs, which is the path every
backend takes today and the one conformance runs. A `demand` that cannot be
met throws `SharingException` naming the missing half. `publish()` makes what
the producer wrote visible to the consumer.

A `GpuFence` is a timeline: `createFence` starts it at zero,
`signalFence(fence, value)` raises it once the work submitted before the
call is done, `waitFence(fence, value)` holds later work on the GPU without
blocking the CPU, and values only grow. `NativeHandle(kind, address)` is
what crosses: an IOSurface, an `MTLTexture`, an `AHardwareBuffer`, Vulkan
memory or a semaphore as a file descriptor or a Win32 handle.

### Queries

`createQuerySet(QueryType, count)` for `occlusion` (`occlusionQuery`),
`timestamp` (`timestampQuery`) and `pipelineStatistics`
(`pipelineStatisticsQuery`; `PipelineStatistic` names the counters).
A pass names its occlusion set in `RenderPassDescriptor.occlusionQuerySet`
and its timestamps in `timestampWrites`; `readQueryResults` answers once
every pass submitted before it has finished, reading zero for a query no pass
wrote. `gpuTimestamps` is a different thing: whole-frame timings delivered
to `onGpuTimings`.

**What grows in a minor**: constants of `TextureFormat`, `TextureDimension`,
`StorageMode`, `TextureUsage` and `BufferUsage` bits, `QueryType`,
`NativeHandleKind`, `SharingMode`; descriptor fields with defaults; new
handle types. **What is frozen**: every existing format's `name` and
`index`, every usage bit's value, the face order of a cube, and the rule
that `TextureHandle` has no `==`.

## Descriptors and `checkFeatures`

Every descriptor whose fields can need a feature carries
`checkFeatures(DeviceFeatures features, {required String backend})`, which
throws `UnsupportedCapabilityException` for the first field the device
cannot honour. **A backend calls it on the way in**, so every backend
refuses the same requests in the same words, and a field a minor adds with
its feature is refused by a backend written before it rather than ignored.

| Descriptor | Called from | What it asks |
|---|---|---|
| `TextureDescriptor.checkFeatures` | `createTexture` | a shape other than 2D (`texture1D`, `textureArrays`, `texture3D`, `cubeTextures`, `cubeArrayTextures`), a storage usage (`storageTextures`), more than one sample (`offscreenMultisample`) |
| `BufferDescriptor.checkFeatures` | `createBuffer` | a storage usage (`compute` or `renderStageStorage`), an indirect usage (`indirectDraw` or `indirectDispatch`), then `buffers` |
| `SamplerDescriptor.checkFeatures` | `bindTexture` | `samplerCompare`, `samplerLodClamp`, `samplerBorderColor`, each alone |
| `BlendState.checkFeatures` | `setBlend` | `blendConstant`, `minMaxBlend`, `dualSourceBlending` |
| `DepthBias.checkFeatures` | `setDepthBias` | `depthBias`, and `depthBiasClamp` for a non-zero clamp |
| `RenderPassDescriptor.checkFeatures` | `beginRenderPass` | `renderToArrayLayer`, `renderToMipLevel`, `occlusionQuery`, `timestampQuery`, `multiview` for a `viewMask` |

`RenderPassDescriptor.checkAttachmentLimit(limit, backend:)` sits beside the
last one. What a descriptor cannot know (which formats a device holds,
whether it creates general textures at all) is the device's to refuse.

**What grows in a minor**: a descriptor field and the clause in its
`checkFeatures` that asks for it. **What is frozen**: the order of the
existing questions and the feature each names.

## Pipelines

`createPipeline(vertex, fragment, {layout})` links two stages. It is
expensive, so callers cache, keyed on the pair **and** the layout: two
layouts over one pair are two pipelines. A null `layout` means the backend
works the vertex inputs out from the shader. `VertexLayoutDescriptor` is a
list of `BufferLayout`s, each with a `strideInBytes`, a `VertexStepMode`
(`vertex` or `instance`) and `InputAttribute`s (`name`, `VertexFormat`,
`offsetInBytes`).

Everything else a pipeline state object holds in an explicit API is pass
state here, set on the encoder: `setPrimitiveType`, `setPolygonMode`,
`setCullMode`, `setWindingOrder`, `setDepthWrite`, `setDepthCompare`,
`setStencil` (front and back `StencilState`: compare, three operations,
eight-bit masks; `StencilState.narrowReference` decides the reference's
eight bits once), `setBlend` (a `BlendState` or null for off, per
attachment), `setColorWriteMask`, `setAlphaToCoverage`, `setDepthBias`
(`DepthBias`: `constant`, `slopeScale`, `clamp`), `setDepthClamp`. A backend
built on pipeline state objects accumulates this state and looks a PSO up at
`draw()`; `PassState` and the `setState` extension exist for it, a hashable
value whose unset fields mean "emit nothing".

`createPipelineAsync` is where a backend that can compile off the calling
turn does so; the default links synchronously. `releasePipeline` gives a
pipeline back; the default does nothing, which is right for a backend whose
pipelines are reclaimed with their last reference.

**A pipeline the API will not build is reported, never thrown from a draw.**
The backend calls `pipelineRefusals.report(handle, PipelineRefusedException(...))`
(reasons: `compile`, `link`, `unsupportedFormat`, `deviceLost`, `other`),
skips the draw, builds again at the next use while `report` answers true,
and skips every draw once `isRefused` says so. `retry: false` reports a
refusal no rebuild can change. The renderer `drain`s the reports after each
frame, so each refusal is told once and the rest of the frame draws.

**What grows in a minor**: `BlendFactor`, `BlendOperation`, `PrimitiveType`,
`PolygonMode`, `CullMode`, `VertexFormat`, `PipelineRefusalReason`
constants; setters with refusing defaults. **What is frozen**:
`createPipeline`'s signature and the report-not-throw rule.

## Encoders

| Encoder | Kind | Opened by | Ends with |
|---|---|---|---|
| `PassEncoder` | `abstract base mixin class` | (the recording half) | |
| `CommandEncoder` | `base mixin on PassEncoder` | `beginRenderPass` | `submit()` |
| `RenderBundleEncoder` | `base mixin on PassEncoder` | `createRenderBundleEncoder` | `finish()` |
| `TransferEncoder` | `abstract base class` | `beginTransferPass` | `submit()` |
| `ComputeEncoder` | `abstract base class` | `beginComputePass` | `submit()` |

A backend's render pass is `extends PassEncoder with CommandEncoder`. The
split is a type-level guard: a contributor drawing into somebody else's pass
is handed a `PassEncoder` and cannot submit it. Passes execute in submission
order.

### `PassEncoder`

Members without a body: the setters `setViewport`, `setScissor`,
`setPrimitiveType`, `setPolygonMode`, `setCullMode`, `setWindingOrder`,
`setDepthWrite`, `setDepthCompare`, `setStencil`, `setStencilReference`,
`setBlend`; the binds `bindPipeline`, `bindVertexBuffer`, `bindVertexData`,
`bindIndexBuffer`, `bindIndexData`, `bindUniformBlock`, `bindTexture`;
`clearBindings` and `draw`.

Members with a body, and the feature their default refuses with:

| Member | Default |
|---|---|
| `drawIndexed(IndexedDraw)` | `draw` when both bases are zero, otherwise refuses `baseVertexBaseInstance` |
| `drawNonIndexed(...)` | `nonIndexedDraw` |
| `multiDraw(List<IndexedDraw>)` | `multiDraw` |
| `drawIndirect(StorageBuffer, {offsetInBytes})` | `indirectDraw` |
| `multiDrawIndirect(...)` | `multiDrawIndirect` |
| `executeBundles(List<RenderBundle>)` | `renderBundles` |
| `bindStorageBuffer`, `bindStorageTexture` | `renderStageStorage` |
| `bindUniformBytes(ShaderHandle, String, ByteData)` | `uniformBytes` |
| `setBlendColor(LinearColor)` | `blendConstant` |
| `setColorWriteMask(ColorWriteMask, {attachment})` | `colorWriteMask` |
| `setDepthBias(DepthBias)` | `depthBias` |
| `setDepthClamp({enabled})` | `depthClamp` |
| `beginOcclusionQuery`, `endOcclusionQuery` | `occlusionQuery` |
| `beginPipelineStatisticsQuery`, `endPipelineStatisticsQuery` | `pipelineStatisticsQuery` |
| `setAlphaToCoverage({enabled})` | ignored, by contract |
| `pushDebugGroup`, `popDebugGroup`, `insertDebugMarker` | nothing |

The rules no signature shows (a clear covers the whole attachment; a pass
starts with the full viewport and scissor and the stencil test off;
rectangles are stated from the top left; `bindPipeline` forgets every
binding; `bindTexture` and `bindUniformBlock` answer false for a slot the
stage does not declare and never throw for one) are listed with what each
costs in [ARCHITECTURE.md §7.2](../../ARCHITECTURE.md#72-semantics-a-signature-cannot-show)
and in the [backend guide](https://flutter3d.pleion.dev/core/backends/#semantics).
`indexWindow` refuses an index window outside the binding with a
`RangeError`, the same on every backend. `bindBlock` (an extension) binds a
generated `UniformBlock` with only the members that stage's layout has.

A `RenderBundleEncoder` throws `StateError` for what belongs to a pass
(`setViewport`, `setScissor`, `setBlendColor`, `setStencilReference`, the
queries, `executeBundles`), and its binds answer from the stage's
declarations at recording time.

### `TransferEncoder`

`submit` has no body. Each copy has a default refusing its feature:
`copyBufferToBuffer` and `clearBuffer` (`bufferCopy`),
`copyTextureToTexture` (`textureCopy`), `copyBufferToTexture` and
`copyTextureToBuffer` (`bufferTextureCopy`, with a `BufferTextureLayout`),
`resolveTexture` (`offscreenMultisample`). Debug groups do nothing by
default. `beginTransferPass` is never refused.

### `ComputeEncoder`

Members without a body: `bindPipeline(ComputePipelineHandle)`,
`bindStorageBuffer`, `bindTexture`, `bindUniformBlock`,
`dispatch(int x, [int y = 1, int z = 1])` and `submit`. Defaults:
`bindStorageTexture` (`storageTextures`), `bindUniformBytes`
(`uniformBytes`), `dispatchIndirect` (`indirectDispatch`), the
pipeline-statistics queries, and debug groups that do nothing. A binding the
stage does not declare answers false, and `bindPipeline` forgets every
binding, as in a render pass. `dispatchIndirectArguments` and
`drawIndexedIndirectArguments` write the argument layouts.

### Multiview

`RenderPassDescriptor.viewMask` names the views of one pass, a bit each;
`views` lists them and `forView(view)` is the same pass drawing one view into
layer `view` of each attachment. `ViewPasses.draw(device, descriptor, draw)`
is the fallback written once: one multiview pass where the device has
`multiview` and the views fit `limits.maxMultiviewViews`, otherwise one pass
per view, each needing `renderToArrayLayer` above view zero. The callback is
handed a `ViewPass` whose `viewIndex` is null in the multiview case.
`ViewPasses.inOnePass` answers which it will be. No backend reports
`multiview` at 1.0.

**What grows in a minor**: encoder members with refusing defaults,
`RenderPassDescriptor` fields. **What is frozen**: the bodiless members
above, `CommandEncoder.submit`, and the semantics in §7.2.

## Compute

A compute step is encoded the same way wherever it runs, because each place
it can run is a `GraphicsDevice` with `compute`. `ComputePlacement` (an open
class) names three: `device` (the device that draws the frame), `sidecar` (a
compute-only device beside it, `flutter3d_wgpu`) and `cpu` (the software
rasteriser's compute as a device of its own). `values` is also the order a
step that demands nothing is placed in.

`ComputeExecutors(device:, sidecar:, cpu:)` writes the placement rule once.
`place(step:, demand:, accepts:)` runs a step at its `demand` or refuses
with `ComputePlacementException` (`ComputeRefusalReason`: `noExecutor`,
`placementUnavailable`, `kernelRefused`, `notPlaced`), and never moves it
quietly; a step demanding nothing goes to the first executor with compute
that `accepts` it. `DeviceRegistry.addComputeDevice(placement, name, open)`
registers a sidecar or CPU device, and `registry.computeExecutors(device)`
builds the executors for a frame, leaving out (and reporting) one that will
not start.

**Kernels** are written once in `.f3dmat compute` and travel in a bundle's
`kernel` section as source (`encodeKernelSection`, `decodeKernelSection`,
`kernelSectionVersion`). Each device translates them as it loads them:
to WGSL on WebGPU and the wgpu sidecar, to a Dart kernel on the software
rasteriser. A device without compute refuses a bundle that claims a kernel,
by name. The conformance suite's kernels hold every placement to the same
bytes.

**What grows in a minor**: `ComputePlacement` values (a second queue, a
remote device), `ComputeRefusalReason` values, kernel section versions.
**What is frozen**: the placement order of the three existing values and the
never-moved-quietly rule.

## Shaders

### Stages and libraries

`ShaderStageKind` is an open class: `vertex` (code 0), `fragment` (1),
`compute` (2). A kind's `code` is the byte a bundle writes, fixed once it
ships; a reader meeting an unknown code refuses the bundle as stale. A
`ShaderLibrary` answers a `ShaderHandle` by name (`LayeredShaderLibrary` and
`ShaderLibraryStack` layer several); a `LoadedShaderLibrary` adds `name` and
`refresh(bytes)`, which reparses in place and **keeps the identity of every
handle already handed out**. A loaded library lives as long as the device.

A `ShaderHandle` carries `kept`, a `StageBindings` (the uniform blocks and
samplers the compiled stage kept, by name), and `layouts`, each block's
`UniformMemberLayout`s (`offset`, `byteLength`, `elements`, reflected
`type`). Both are null for a stage the library cannot describe;
`mayBindBlock` and `mayBindSampler` then answer true. `StageBindings` is a
class so a binding kind (storage buffers, storage textures, acceleration
structures) arrives as one more defaulted field.

### Bundles: the F3SB container, version 2

A `ShaderBundle` is a name, the `sdk` a compiled section was built with, the
`stages` it claims (`ShaderBundleStage`: name and kind) and one section per
backend that needs one. `encode` writes, `decode` reads, little-endian
throughout: the magic `F3SB`, the version word, the header strings, each
stage as a string and its kind's code, and each section as a string id, a
length and the bytes. Version 2 writes a stage's kind as its code; version 1
wrote 1 for a fragment and 0 for anything else, and `decode` reads both.
A newer container, an unknown kind or a newer section payload is refused as
`ShaderBundleException.stale`: bundles are build artifacts, so a mismatch is
a rebuild.

| Section id | Read by | Holds |
|---|---|---|
| `impeller` (`ShaderBundle.impellerSection`) | Impeller | `impellerc` output, checked against `sdk` with `compiledFor` |
| `webgl` | WebGL2 | GLSL ES 3.00 sources by name, as JSON |
| `webgpu` | WebGPU | WGSL and the reflection that goes with it, versioned inside the document |
| `material` | the software rasteriser | each material-language stage's source (`encodeMaterialSection`) |
| `kernel` | every device with compute | each `.f3dmat compute` kernel's source |
| `flutter3d.stamp` | the build and `doctor` | the `EngineBundleStamp` |
| a backend's own | that backend | whatever its `MaterialCompiler` writes; no two backends share one |

`EngineBundleStamp` (in `flutter3d_shaders`) is what the engine's own bundle
carries besides its compiled sections: the Dart (`dart`) and the Flutter
engine revision (`engine`) that built it, the `needs` it was written for,
whether it is `full`, and its stage count. The project's build hook writes
the engine bundle to `EngineBundleStamp.projectAsset` and keeps the previous
one beside it for a hot reload across the rebuild.

### The material compiler

A backend turns the material language into its section with a
`MaterialCompiler` (`package:flutter3d_shaders/backend.dart`): `backend`
(its device's `backendId`), `bundleSection`, `compilesAtRunTime` (false by
default), `isSectionWrittenByBuild` (false), and
`compile(MaterialCompileRequest)` to a `MaterialCompileResult` or a
`MaterialCompileException`. A `MaterialCompilerRegistry` finds a compiler by
`backendId`, exactly. `compileStage` in `package:flutter3d_shaders/compile.dart`
hands a backend SPIR-V and text for a `ShaderTarget` (`spirv`, `wgsl`, `msl`,
`hlsl`, `glsl`), with glslang and naga on the machine.

**Today and in rc.2.** `RuntimeShaders` asks the registered compiler of the
backend the game runs on. `runShaderBuild(registry:)` asks every compiler it
holds for a backend from outside for its section of the engine's bundle and
of each material's. In 1.0.0-rc.1 **no shipped path hands `runShaderBuild` a
registry** (the build hook, `flutter3d shaders` and `material_build.dart` call
it without one), so a backend from outside reaches the engine's stages by
shipping its section in a bundle of its own, by compiling at run time, or
through a tool of its own that calls `runShaderBuild(registry:)`. Discovering
compilers from a marker the `--kind backend` template writes into the
pubspec is planned for rc.2. CONTRACTS, ["A backend's material compiler"](../../docs/CONTRACTS.md#a-backends-material-compiler),
has the details.

### The shader ABI

The engine asks for entry points (`requiredShaders`, and `computeShaders`
for a backend that computes), uniform blocks and members by name.
`stageBindings` and `uniformBlocks` in `flutter3d_shaders/backend.dart` are
the same facts as code, and `checkStageAgreement` holds each pipeline's two
stages to each other before a bundle is written.
`packages/flutter3d_shaders/api/flutter3d_shaders.abi` records the whole ABI
one fact a line, and the structure rule **`the shader ABI only grows`** fails
on any line of the base recorded at 1.0.0-rc.1 that is gone: a dropped stage,
a removed or reordered member, a moved offset, a renumbered vertex input.

**The material binding budget.** One stage binds at most 16 textures, 16
samplers and 12 uniform blocks, the engine's and the material's together
(`MaterialStageBudget`); a lit model's own share is 3 textures and 4 uniform
blocks in every 1.x (`materialTextures`, `materialUniformBlocks`). Every
build counts each emitted stage and refuses one over budget, naming it.

**What grows in a minor**: entry points, blocks, members appended,
`ShaderStageKind` values, section ids, section payload versions, binding
kinds in `StageBindings`, budget-neutral engine bindings. **What is frozen**:
every line of the ABI base, the container's layout per version, each kind's
code, the budget's material share.

## Lifetime

Every handle a device makes has one owner, the code that asked for it, and a
`dispose` that gives it back once; the device's `release…` member is the
same call from the other side. A second `dispose` asserts in a debug build,
and a backend calls `debugCheckLive(handle, operation)` before it binds,
draws from, copies or reads a handle, so a debug build names the call that
used a disposed one. A `ShaderHandle` is the exception: the library hands one
stage to every caller, so its `dispose` gives back a reference
(`forgetShader` drops it from a library's map).

**Deferred destruction.** A release may come as soon as the caller has
*submitted* its last use, while the GPU may still read the object. The
device keeps it alive until the work that reads it is done, by
`onFrameComplete` at the latest, then destroys it. WebGL2 and WebGPU get this
from their APIs, the software rasteriser has finished every pass by
`submit`, Impeller's objects go through the collector. **A backend over
Vulkan or Metal directly must queue the destruction itself**; destroying at
once is a use-after-free on the GPU.

**Frames in flight.** The HAL has no frame count. `beginFrame` tells the
backend to rotate what it rotates (a ring of uniform allocators, say), and
`onFrameComplete(whenDone)` tells the engine when the frame being encoded is
finished, so a presented texture goes back into rotation exactly when the
work that read it is done. A backend whose submission is synchronous calls
`whenDone` at once.

**Device loss.** `lost` is a stream of `DeviceLoss` (`reason`:
`DeviceLossReason.destroyed` or `unknown`, an open class; `message`;
`isRecoverable`; `restored`); `isLost` is the current state for a late
subscriber. After a loss every handle is spent. A recoverable loss (a WebGL
context) is followed by an event with `restored` true, after which the
application rebuilds its renderer on the same device; any other means a new
device. `PipelineRefusalReason.deviceLost` reports a pipeline lost with it.
`dispose` releases everything, and a handle used afterwards draws nothing.

**What is frozen**: one owner and one `dispose` per handle, deferred
destruction, and `lost` as the one place a loss is reported.

## Threading and asynchronous answers

The contract names no threads. A device is a Dart object and is called from
the isolate that opened it, one call at a time; nothing in the HAL is sent
between isolates. What may wait on the GPU is a `Future`, and none of them
stalls the caller:

| Member | Completes |
|---|---|
| `readback` | when the copy queued at the call is done, usually a frame or two later; a whole texture outside `readbackFormats` is converted (`readbackConverts`), which may wait |
| `readBuffer`, `mapBuffer`, `readQueryResults` | once every pass submitted before the call has finished with the buffer or set |
| `loadShaders`, `overwriteTexture` | in the same turn on the engine's backends; asynchronous because one backend's own call is |
| `createPipelineAsync`, `createComputePipelineAsync` | when the pipeline is linked, off the calling turn where the API allows |
| `SharedTexture.publish`, `SharedBuffer.publish` | when the consumer can read what was written |

Writes (`overwriteGeometry`, `writeBuffer`, `writeTexture`,
`overwriteTexture`) are visible from the next pass, never the one already
encoded. A stall belongs in a test: `SynchronousBufferReadback.readBufferSync`
reads a buffer in the calling turn and is reached through `testing.dart`.

## Refusals

Every refusal is a typed exception, thrown where the request is made and
never answered with null (the creators answered null before 1.0).

| Exception | Base | When |
|---|---|---|
| `UnsupportedCapabilityException` (foundation) | `CapabilityException` | a feature the device does not list; carries `feature` (a `Capability`), `backend`, `reason` |
| `DeviceResourceException` | `ResourceException` | the device has the feature and still cannot honour the request (`operation`, `backend`, `reason`, `cause`) |
| `DeviceUnavailableException` | `ResourceException` | a device would not open, or every backend a registry holds refused (`refusals`) |
| `PipelineRefusedException` | `ResourceException` | reported on `pipelineRefusals`, not thrown from a draw |
| `ShaderBundleException` | `ResourceException` | a bundle a device will not load; `stale` when rebuilding cures it |
| `ComputePlacementException` | `CapabilityException` | a compute step nothing can run |
| `SharingException` | `CapabilityException` | a sharing mode demanded and not available |
| `ArgumentError` | | a request the caller could have checked: a readback of a multisampled, transient or cube texture, a region outside the texture |

`refuse` and `refuseResource` on `GraphicsDevice`, `DeviceFeatures.require`
and the descriptors' `checkFeatures` build the first two, so the words are
the same everywhere. **A refusal is never a substitution**: a backend that
cannot draw wireframe refuses `setPolygonMode(PolygonMode.line)` rather than
filling the triangles. A backend that has not built a feature yet says so
the same way, with a `TODO(<backend>)` at the refusal.

In conformance, a check a device cannot be asked **declines**:
`decline(device, why)` throws `ConformanceDeclinedException` with the
device's `backendName` at the front of the sentence, and the runner reports
the check skipped with that sentence. A decline is never a pass.
`makeDevice` may decline too, on a machine with no device for the backend.

## Conformance

`flutter3d_conformance` turns the contract into executable checks. A backend
is finished when they pass.

```dart
import 'package:flutter3d_conformance/flutter3d_conformance.dart';

void main() => runDeviceConformance(
  backend: VulkanDevice.id,
  makeDevice: VulkanDevice.open,
  checks: coreChecks,
);
```

`runDeviceConformance(backend:, makeDevice:, ownShaders:, checks:)` calls
the factory fresh for each check and disposes the device after it. Leave
`checks:` out and `conformanceChecks` runs; `ownShaders` adds the
loaded-bundle check (`loadedBundleChecks`, also in `conformanceChecksWith`).
The suite uses its own `require`, not `expect`, so the same list runs from an
application where there is no test runner (Impeller's harness).

| Tier | What it needs |
|---|---|
| `coreChecks` | clears, uploads, readback and the refusals; no shader |
| `capabilityChecks` | the honesty check, `every capability a device reports is honest`: each listed feature passes a minimal call, each unlisted one is refused by that feature's name. `unprobedFeatures` names what it cannot probe and why |
| `computeChecks` (with `kernelChecks`) | `compute`; declines otherwise |
| `multiviewChecks`, `sharingChecks`, `fieldResidenceChecks`, `xrChecks` | pass or decline on a device that does not draw |
| `shaderChecks` | the engine's stages compiled for the backend, and a rasteriser |
| `loadedBundleChecks(ownShaders)` | a backend that can pack its own shaders as a loadable bundle |

A new backend runs `coreChecks` first, then everything but the shader tier
(`conformanceChecks.where((c) => !shaderChecks.contains(c))`, the null
backend's line), then the whole list once it draws. The fuzzer
(`generateFuzzProgram`, `fuzzSeed`, `fuzzDifference`, `shrinkFinding`)
compares a backend's pixels with a reference device's.

**What grows in a minor**: checks and tiers, as the contract grows. A check
for a feature declines on a device that does not list it, so a new feature's
checks ask nothing of a backend written before it.

## The backends

| Backend | Package | `backendId` | `backendName` | Origin | Depth range | Notes |
|---|---|---|---|---|---|---|
| Software rasteriser | `flutter3d_cpu` | `cpu` | the software rasteriser | top left | 0 to 1 | the reference; no GPU, runs in CI |
| WebGL2 | `flutter3d_webgl` | `webgl` | WebGL2 | bottom left | 0 to 1 with `EXT_clip_control`, else −1 to 1 | features decided per context |
| WebGPU | `flutter3d_webgpu` | `webgpu` | WebGPU | top left | 0 to 1 | asks the adapter for every feature it knows |
| Impeller | `flutter3d_impeller` | `impeller` | Impeller | top left | 0 to 1 | over `flutter_gpu`; gaps are refusals with `TODO(impeller)` |
| wgpu sidecar | `flutter3d_wgpu` | `wgpu` | the wgpu sidecar | top left | 0 to 1 | computes, draws nothing; `ComputePlacement.sidecar` |

What each reports, at this commit. "if …" is decided when the device opens;
"adapter" means the WebGPU adapter offered the feature.

| Feature | cpu | webgl | webgpu | impeller | wgpu |
|---|---|---|---|---|---|
| `alphaToCoverage` | no | if MSAA proven | yes | no | no |
| `baseVertexBaseInstance` | yes | if `WEBGL_draw_instanced_base_vertex_base_instance` | yes | no | no |
| `blendConstant` | yes | yes | no | no | no |
| `bufferCopy`, `bufferTextureCopy` | yes | yes | yes | no | no |
| `buffers` | yes | yes | yes | yes | yes |
| `clipDistances` | no | no | if adapter | no | no |
| `colorWriteMask` | yes | yes | yes | no | no |
| `compute` | yes | no | yes | no | yes |
| `cubeArrayTextures` | yes | no | yes | no | no |
| `cubeTextures` | yes | yes | yes | if a probe cube allocates | no |
| `depthBias` | yes | yes | yes | no | no |
| `depthBiasClamp` | no | no | yes | no | no |
| `depthClamp` | yes | if `EXT_depth_clamp` | if adapter | no | no |
| `dualSourceBlending` | yes | if `WEBGL_blend_func_extended` | if adapter | no | no |
| `float32Blendable` | yes | if `EXT_color_buffer_float` and `EXT_float_blend` | if adapter | Metal on macOS | no |
| `float32Filterable` | yes | if `OES_texture_float_linear` | if adapter | Metal on macOS | no |
| `float32Renderable` | yes | if `EXT_color_buffer_float` | yes | Metal on macOS | no |
| `gpuTimestamps` | no | no | if adapter | no | no |
| `independentBlend` | yes | if `OES_draw_buffers_indexed` | yes | yes | no |
| `indirectDispatch`, `indirectDraw` | yes | no | yes | no | no |
| `indirectFirstInstance` | yes | no | if adapter | no | no |
| `manualMipmaps` | yes | yes | yes | if `flutter_gpu` says so | no |
| `mappedBuffers` | yes | yes | yes | no | no |
| `minMaxBlend` | yes | yes | yes | no | no |
| `multiDraw`, `nonIndexedDraw` | yes | yes | yes | yes | no |
| `multiDrawIndirect` | yes | no | if adapter | no | no |
| `multiview` | no | no | no | no | no |
| `occlusionQuery` | yes | yes | yes | no | no |
| `offscreenMultisample` | no | if MSAA proven | yes | if `flutter_gpu` says so | no |
| `pipelineStatisticsQuery` | yes | no | no | no | no |
| `readWriteStorageTextures` | yes | no | yes | no | no |
| `renderBundles` | yes | yes | yes | no | no |
| `renderStageStorage` | yes | no | no | no | no |
| `renderToArrayLayer` | yes | yes | yes | no | no |
| `renderToMipLevel` | yes | yes | yes | Metal and Vulkan | no |
| `reversedDepth` | yes | if `EXT_clip_control` | if adapter has `depth32float-stencil8` | if the depth format is `d32FloatS8UInt` | no |
| `rg11b10Renderable` | no | if `EXT_color_buffer_float` | if adapter | no | no |
| `samplerBorderColor` | yes | no | no | no | no |
| `samplerCompare`, `samplerLodClamp` | yes | yes | yes | no | no |
| `shaderF16`, `subgroups` | no | no | if adapter | no | no |
| `sharedBuffers`, `sharedFences`, `sharedTextures` | no | no | no | no | no |
| `stencil` | yes | yes | yes | if there is a depth-stencil format | no |
| `storageTextures` | yes | no | yes | no | yes |
| `synchronousReadback` | yes | yes | no | no | yes |
| `texture1D` | yes | no | yes | yes | no |
| `texture3D`, `textureArrays` | yes | yes | yes | no | no |
| `textureCompressionASTC` | no | if `WEBGL_compressed_texture_astc` | if adapter | if `flutter_gpu` has the family | no |
| `textureCompressionASTCHdr` | no | no | no | if `flutter_gpu` has the family | no |
| `textureCompressionBC` | no | if the S3TC, RGTC and BPTC extensions are all there | if adapter | if `flutter_gpu` has the family | no |
| `textureCompressionETC2` | no | if `WEBGL_compressed_texture_etc` | if adapter | if `flutter_gpu` has the family | no |
| `textureCopy` | yes | yes | yes | no | no |
| `textureWrites` | yes | yes | yes | yes | no |
| `timestampQuery` | yes | if the timer extension counts timestamps | if adapter | no | no |
| `uniformBytes` | no | yes | yes | yes | no |
| `viewportBeyondTarget` | yes | yes | no | no | no |
| `wireframe` | no | no | no | yes | no |

The software rasteriser's constructor can withhold any feature
(`withhold:`), which is how a refusal is exercised with real pixels behind
it. Its full reasons are on `CpuDevice`; each backend's are beside its
`features`.

**The starting point for a fifth** is `examples/flutter3d_backend_null`: a
device with no GPU that keeps textures in memory, clears, uploads,
overwrites, copies and reads them back, refuses every pipeline at its first
draw, and passes every check but the shader tier. It imports only published
libraries, and the structure rule `an outside example reaches only the
published API` keeps it so. `flutter3d create plugin --kind backend --name
<name>` writes the same backend under a new name (`<Name>Device`,
`<Name>Pass`, `register<Name>Backend`, `<Name>MaterialCompiler`, two tests);
a test in `flutter3d_build` holds the template to the example file for file.

## Testing helpers

| Helper | Library | What it is for |
|---|---|---|
| `FakeBackend` | `testing.dart` | a device that records instead of drawing: `calls`, `passes` (`FakePass`, with `commands` of `Recorded` subtypes), `bindingViolations`, `liveHandles` (what a test made and did not give back), `pipelineBuilds`; switches for missing shaders, refused pipelines, missing features, `lose(DeviceLoss)`, and `finishOldestFrame` to drive `onFrameComplete` |
| `RecordingDevice` | `trace.dart` | wraps any device and keeps every call as a `TraceEvent`; `Trace.encode` writes it (`.f3dtrace`), `replayTrace(trace, device)` draws it again on any backend; `unrecorded` lists calls it passed through without recording |
| `renderFrame(device:)` | `flutter3d_testing` | opens a `BackendOpener` at the frame's size, draws the engine's frame, reads the pixels back, disposes the device; the software rasteriser when `device` is left out |
| `testReplay(device:)`, `expectReplayMatches(device:)` | `flutter3d_testing` | replay a tape and compare goldens on one device opened for the run |
| `drawOnce` | `flutter3d_testing` | the layer under both, for a test that keeps its own device and renderer |

A golden set drawn on a backend belongs to that backend: keep it in a
directory of its own.

## Coverage and growth

What the HAL covers at 1.0, measured against the capability areas of
explicit graphics APIs, and how each missing piece would arrive. "Minor"
means a 1.x minor can add it without breaking an outside backend, through
the mechanism named; "shape" means it would need a change to an existing
declaration.

| Area | Have at 1.0 | Can be added in a minor | Needs a shape change |
|---|---|---|---|
| Texture shapes | 1D, 2D, 2D arrays, 3D, cubes, cube arrays (`TextureDimension`, each gated by its feature) | a new shape: a `TextureDimension` constant and a feature; texture views: a member with a default returning a `TextureHandle` | none |
| Multisampling | sample counts, resolve targets, `StoreAction.multisampleResolve`, `resolveTexture` in a transfer pass, alpha to coverage | depth and stencil resolve (`depthResolve` is reserved): a `DepthTarget` field with a default | none |
| Transient and tile memory | `StorageMode.deviceTransient`, load and store actions per attachment | subpasses and input attachments: descriptor fields and a feature | none |
| Sparse, aliased and heap memory | none; allocation is the backend's | new members with refusing defaults, a `TextureUsage` bit and a feature | none |
| Formats | eight-bit, half and full float, integer, packed, BC1, BC3, BC5, BC7, ETC2, ASTC 4x4 and 8x8 (LDR and HDR), depth and stencil; `textureFormatSupport` per format | 16-bit normalised and small integer formats, BC4, BC6H, EAC and other ASTC block sizes: `TextureFormat` constants with new indices; half and packed vertex formats: `VertexFormat` constants; 8-bit indices: an `IndexType` constant | none |
| Samplers | filters, address modes, anisotropy (clamped), comparison, level clamps, border colour | a level-of-detail bias, a min or max reduction, a mirrored clamp: `SamplerDescriptor` fields with defaults, `SamplerAddressMode` constants, features; a sampler bound apart from its texture: an encoder member with a default and a `StageBindings` field | a border on one axis and the edge on another: `borderColor` applies to every `clampToEdge` axis, so a per-axis border needs a `clampToBorder` address mode and that rule decided before 1.0 |
| Pipeline state | a stage pair and a vertex layout per pipeline; raster, depth, stencil and blend state set on the pass; `PassState` for a backend that builds state objects | none needed | none |
| Pipeline compilation | `createPipelineAsync`, `createComputePipelineAsync`, `pipelineRefusals` | a pipeline cache to save and load, a warm-up hint: members with defaults | none, though every new pipeline input arrives as a new entry point while pipeline creation takes bare parameters; a descriptor-taking entry point with a default body would gather them |
| Specialisation and constants | uniform blocks by member name, uniform bytes (`uniformBytes`) | specialisation constants: a new creation member with a default that refuses when constants are given; immediate data (`immediateData` is reserved) with `maxImmediateDataSize` already in `DeviceLimits` | `createPipeline`'s signature cannot gain a parameter, so the new member has to be a second entry point |
| Binding model | by name per stage (`bindTexture`, `bindUniformBlock`, `bindStorageBuffer`, `bindStorageTexture`), reflected in `StageBindings` and `UniformMemberLayout` | bindless resources (`bindlessResources` is reserved) and binding kinds: `StageBindings` fields and encoder members with defaults | none |
| Render passes | load and store actions, several colour targets, a depth-stencil target, read-only depth, rendering into a face, level or layer, multiview by `viewMask` with a fallback, render bundles | variable rate shading (reserved), depth bounds (reserved) | none |
| Compute | dispatch, indirect dispatch, storage buffers and textures, workgroup limits, `subgroups`, `shaderF16`, three placements | a second queue (`asyncCompute` is reserved) as a `ComputePlacement` | none |
| Draws | indexed, non-indexed, instanced, base vertex and instance, indexed indirect, multi-draw, multi-draw indirect with a count buffer | non-indexed indirect draws, mesh and task stages (`meshShaders` is reserved): `ShaderStageKind` values and encoder members with defaults | none |
| Ray tracing | none | `rayQuery` is reserved; acceleration structures as a new handle type, a `StageBindings` field and members with defaults | none |
| Synchronisation | ordering by submission; the backend tracks hazards and defers destruction; timeline fences for sharing | a second queue: a new pass-opening member with a default (`beginComputePass` cannot gain a parameter); fences without export, a CPU wait on a fence: a feature and members with defaults | none |
| Queries | occlusion, timestamp, pipeline statistics (five counters, a fixed stride); whole-frame timings through `onGpuTimings` | timestamps inside a pass, results resolved into a buffer, binary occlusion and conditional drawing: members with defaults and `QueryType` constants; more statistics as a new `QueryType`, since the five are frozen | none |
| Readback and staging | `readback`, `readBuffer`, `mapBuffer`, transfer copies, synchronous readback for tests | a region readback of another format: a new member with a default, since `readbackFormats` decides for every backend at once | none |
| Sharing and interop | `NativeHandle` export and import of textures, buffers and fences, `SharedTexture` and `SharedBuffer` with a host-memory fallback | `NativeHandleKind` constants | none |
| Debugging | debug groups, markers, labels, `RecordingDevice` and replayable traces | a GPU capture trigger: a member with a default | none |
| Device loss | `lost`, `isLost`, recoverable and restored losses | `DeviceLossReason` constants | none |
| Capabilities | `DeviceFeatures`, `DeviceLimits`, `TextureFormatSupport`, reserved features | features, limit fields with defaults | none |
| Shader code and reflection | GLSL source compiled per backend into bundle sections, SPIR-V and text through `compileStage`, reflection in the bundle and in `flutter3d_shaders` | a stage kind, a section, a payload version | none |

Some absences are design rather than gaps: the HAL has no swapchain or
present (presenters live in `DeviceRegistry`), no explicit barriers or layout
transitions (the backend tracks hazards and orders by submission), no mip
generation on the device (`MipChain.build` makes the chain once, above the
seam, so every backend samples the same bytes), and uniforms are bound as
named members rather than as offsets into buffers the caller manages.

One rule of Dart decides much of the third column: an override must accept
every parameter of the member it overrides, so a member an outside backend
overrides can never gain a parameter within a major. Growth therefore comes
as new members with default bodies, new fields on the descriptor classes
those members take, and new constants of open classes, which is why the
descriptors (`TextureDescriptor`, `BufferDescriptor`, `SamplerDescriptor`,
`RenderPassDescriptor`) carry the shape.

## Writing a fifth backend

1. **Start from the template.**
   `dart run flutter3d_build:flutter3d create plugin --kind backend --name flutter3d_vulkan`
   writes the null backend under your name. Run its tests: every check but
   the shader tier passes on the first day.
2. **Implement the bodiless members against your API**: textures, geometry,
   `readback`, `beginRenderPass`. Keep `features` empty while you do, and
   refuse what you have not built with `refuse(feature)`. Run `coreChecks`.
3. **Report each feature as you implement it**, overriding the member whose
   default refused it. The honesty check fails on a feature reported and not
   done, and on one done and not reported. Run everything but the shader
   tier.
4. **Queue destruction until the GPU is done** (`onFrameComplete` at the
   latest) and report a loss on `lost`, including your own `dispose`.
5. **Compile the engine's stages** with `compileStage` (or your own
   toolchain), answer them from `shaders`, bind by `stageBindings` and
   `uniformBlocks`, and stop refusing pipelines in `draw`. Report a pipeline
   your API will not build on `pipelineRefusals`. Add `shaderChecks`.
6. **Write a `MaterialCompiler`** with your `backendId` and a section of
   your own, and register it beside the backend.
7. **A presenter**, if the backend shows frames in a widget, added with
   `registry.addPresenter<YourDevice>(…)`.
8. **A golden set of your own** through `renderFrame(device:)` and
   `testReplay(device:)`.

### A minimal compiling skeleton

Every member without a body, and nothing else. It compiles against the
published libraries (`flutter3d_hardware`, `flutter3d_foundation` for
`Registration`, and `flutter3d_conformance` for the test) and refuses
everything it does not do by the feature that would make it possible.

```dart
import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Registration;
import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

final class VulkanDevice extends GraphicsDevice {
  VulkanDevice._();

  /// The `BackendOpener` shape: asynchronous, at the surface's size.
  static Future<VulkanDevice> open({
    required int width,
    required int height,
  }) async => VulkanDevice._();

  static const String id = 'vulkan';

  @override
  String get backendName => 'Vulkan';

  @override
  String get backendId => id;

  // What the device is.

  @override
  final DeviceFeatures features = DeviceFeatures(const <DeviceFeature>[]);

  @override
  final DeviceLimits limits = const DeviceLimits();

  @override
  TextureFormatSupport textureFormatSupport(TextureFormat format) =>
      format == TextureFormat.r8g8b8a8UNormInt
      ? const TextureFormatSupport(sampled: true, renderable: true)
      : TextureFormatSupport.none;

  @override
  TextureFormat get defaultColorFormat => TextureFormat.r8g8b8a8UNormInt;

  @override
  TextureFormat get defaultDepthStencilFormat => TextureFormat.d32Float;

  @override
  TextureFormat get hdrColorFormat => TextureFormat.r16g16b16a16Float;

  @override
  FramebufferOrigin get framebufferOrigin => FramebufferOrigin.topLeft;

  @override
  DepthRange get depthRange => DepthRange.zeroToOne;

  @override
  int get preferredSampleCount => 1;

  // Shaders.

  @override
  ShaderLibrary get shaders => throw UnimplementedError();

  @override
  Future<LoadedShaderLibrary> loadShaders(ByteData bytes) async =>
      throw ShaderBundleException(
        name: ShaderBundle.decode(bytes).name,
        reason: 'this backend has no section reader yet',
      );

  @override
  PipelineHandle createPipeline(
    ShaderHandle vertex,
    ShaderHandle fragment, {
    VertexLayoutDescriptor? layout,
  }) => wrapPipeline(
    owner: this,
    backend: Object(),
    name: '${vertex.name}+${fragment.name}',
  );

  // Textures.

  @override
  TextureHandle createTexture(TextureDescriptor descriptor) {
    descriptor.checkFeatures(features, backend: backendName);
    return wrapTexture(
      owner: this,
      backend: Object(),
      width: descriptor.width,
      height: descriptor.height,
      format: descriptor.format,
      dimension: descriptor.dimension,
      depthOrArrayLayers: descriptor.depthOrArrayLayers,
      mipLevelCount: descriptor.mipLevelCount,
      sampleCount: descriptor.sampleCount,
      usage: descriptor.usage,
      storageMode: descriptor.storageMode,
    );
  }

  @override
  void releaseTexture(TextureHandle texture) {}

  @override
  TextureHandle createTextureFromPixels({
    required int width,
    required int height,
    required TextureFormat format,
    required ByteData pixels,
    List<ByteData>? mipLevels,
  }) => createTexture(
    TextureDescriptor(width: width, height: height, format: format),
  );

  @override
  TextureHandle createCubeTextureFromPixels({
    required int size,
    required TextureFormat format,
    required List<ByteData> faces,
    List<List<ByteData>>? mipLevels,
  }) => throw refuse(DeviceFeature.cubeTextures);

  @override
  TextureHandle createCubeRenderTarget({
    required int size,
    required TextureFormat format,
    int mipLevels = 1,
  }) => throw refuse(DeviceFeature.cubeTextures);

  @override
  Future<void> overwriteTexture(
    TextureHandle target,
    ByteData rgba, {
    ScreenRect? region,
    int mipLevel = 0,
  }) async {}

  @override
  Future<ByteData> readback(TextureHandle texture, {ScreenRect? region}) async {
    final rect = readbackRegionOf(texture, region);
    return ByteData(rect.width * rect.height * 4);
  }

  // Geometry.

  @override
  GeometryBuffer uploadGeometry(ByteData bytes, GeometryUsage usage) =>
      wrapGeometry(
        backend: Object(),
        offsetInBytes: 0,
        lengthInBytes: bytes.lengthInBytes,
        release: releaseGeometry,
      );

  @override
  void overwriteGeometry(
    GeometryBuffer target,
    int offsetInBytes,
    ByteData bytes,
  ) {}

  @override
  void releaseGeometry(GeometryBuffer geometry) {}

  // Frames.

  @override
  void beginFrame() {}

  @override
  void onFrameComplete(void Function() whenDone) => whenDone();

  @override
  CommandEncoder beginRenderPass(RenderPassDescriptor descriptor) {
    descriptor
      ..checkAttachmentLimit(limits.maxColorAttachments, backend: backendName)
      ..checkFeatures(features, backend: backendName);
    return VulkanPass(this);
  }

  @override
  void dispose() {}
}

final class VulkanPass extends PassEncoder with CommandEncoder {
  VulkanPass(this.device);

  final VulkanDevice device;

  @override
  void setViewport(ScreenRect rect) {}

  @override
  void setScissor(ScreenRect rect) {}

  @override
  void setPrimitiveType(PrimitiveType type) {}

  @override
  void setPolygonMode(PolygonMode mode) {
    if (mode != PolygonMode.fill) {
      device.features.require(
        DeviceFeature.wireframe,
        backend: device.backendName,
      );
    }
  }

  @override
  void setCullMode(CullMode mode) {}

  @override
  void setWindingOrder(WindingOrder order) {}

  @override
  void setDepthWrite({required bool enabled}) {}

  @override
  void setDepthCompare(CompareFunction compare) {}

  @override
  void setStencil(StencilState front, {StencilState? back}) => device.features
      .require(DeviceFeature.stencil, backend: device.backendName);

  @override
  void setStencilReference(int value) => device.features.require(
    DeviceFeature.stencil,
    backend: device.backendName,
  );

  @override
  void setBlend(BlendState? state, {int attachment = 0}) =>
      state?.checkFeatures(device.features, backend: device.backendName);

  @override
  void bindPipeline(PipelineHandle pipeline) =>
      debugCheckLive(pipeline, 'bindPipeline');

  @override
  void bindVertexBuffer(
    GeometryBuffer buffer,
    int vertexCount, {
    int slot = 0,
  }) => debugCheckLive(buffer, 'bindVertexBuffer');

  @override
  void bindVertexData(ByteData bytes, int vertexCount, {int slot = 0}) {}

  @override
  void bindIndexBuffer(GeometryBuffer buffer, IndexType type, int indexCount) =>
      debugCheckLive(buffer, 'bindIndexBuffer');

  @override
  void bindIndexData(ByteData bytes, IndexType type, int indexCount) {}

  @override
  bool bindUniformBlock(
    ShaderHandle shader,
    String blockName,
    Map<String, Float32List> members,
  ) => shader.mayBindBlock(blockName);

  @override
  bool bindTexture(
    ShaderHandle shader,
    String slot,
    TextureHandle texture, {
    SamplerDescriptor? sampler,
  }) {
    debugCheckLive(texture, 'bindTexture');
    sampler?.checkFeatures(device.features, backend: device.backendName);
    return shader.mayBindSampler(slot);
  }

  @override
  void clearBindings() {}

  @override
  void draw({int instanceCount = 1, int firstIndex = 0, int? indexCount}) {}

  @override
  void submit() {}
}

/// What an application calls to add the backend to an engine.
Registration registerVulkanBackend(DeviceRegistry<Object> registry) =>
    registry.addBackend('Vulkan', VulkanDevice.open);
```

The conformance test beside it is the snippet in [Conformance](#conformance).
This skeleton compiles and is not yet conforming: its `readback` answers
zeros, so `coreChecks` tells you what to build first. Everything the base
class gives (compute, buffers, transfers, queries, sharing, loss, labels)
refuses or does nothing until you override it, which is the honest answer of
a device that has not built it yet.
