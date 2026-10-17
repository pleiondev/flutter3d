# 26. The HAL surface against its backends and the APIs under them (branch 1.0.0, 2026-10-14)

Agent notes. Read-only on code; this file is the only write. Compute is a
separate audit and is touched here only where it meets the render contract.
Line numbers are the working tree of 2026-10-14 (HEAD `9f4312f64`).

## Verdict

The HAL can be frozen at 1.0 with one small shape change. D25 is done:
on 2026-10-09 `PassEncoder` had 38 bodiless members, `ComputeEncoder` 11
and `TransferEncoder` 7. Today the counts are 20, 6 and 1, and every member
still without a body is a core verb that predates 1.0. The snapshot
classifier now treats a bodiless addition to an extended type as a major.
Descriptors carry `checkFeatures`, so a field added in a minor is refused by
a backend written before it. Every set that can grow is an open class. The
null backend, the `--kind backend` template, `renderFrame(device:)` and the
compiler registry exist, and their tests pass. Against WebGPU, WebGL2 and
flutter_gpu 3.47, nearly every missing capability can arrive in a 1.x minor.

**The blocker:** capabilities that every 1.0 backend is assumed to have
cannot become `DeviceFeature`s later. These are strip and point topologies,
32-bit indices and primitive restart. Adding one later would make the honesty
check fail a 1.0 backend that does not list it. The software rasteriser
already refuses strips and points with an untyped `UnsupportedError`.

**The weakest part is conformance.** For most 1.0 features it only checks
that the call does not throw.

## 1. The contract, mapped

**Checked** against `packages/flutter3d_hardware/api/flutter3d_hardware.api`, now
and at `21730382b` (the last commit of 2026-10-09).

| Type | Kind | Abstract members 2026-10-09 | Abstract members now | Notes |
|---|---|---|---|---|
| `GraphicsDevice` | `abstract base class … with TextureAllocator` | 24 | 24 | Unchanged. The same 24 audit 11 listed ("~22" there, but the list had 24): formats/origin/depth range/sample count, cube creators, `shaders`, `loadShaders`, `createPipeline`, geometry upload/overwrite/release, pixel creators, `overwriteTexture`, `readback`, `beginFrame`, `onFrameComplete`, `beginRenderPass`, `dispose`, `features`, `limits`, `textureFormatSupport` (`graphics_device.dart:98-614`). About 50 more members have bodies (`:541-1031`). |
| `TextureAllocator` | `abstract base mixin class` | 2 | 2 | `createTexture`, `releaseTexture` (`render_target_pool.dart:91`). |
| `PassEncoder` | `abstract base mixin class` | **38** | **20** | Bodiless: 11 setters, 7 binds, `clearBindings`, `draw` (`command_encoder.dart:127-436`). Every feature-gated member has a refusing body (`:466-617`) and debug groups do nothing (`:628-634`). D25 is done. |
| `CommandEncoder` | `base mixin on PassEncoder` | 1 | 1 | `submit` (`:705`). |
| `RenderBundleEncoder` | `base mixin on PassEncoder` | 1 | 1 | `finish` (`:663`). |
| `ComputeEncoder` | `abstract base class` | 11 | 6 | `bindPipeline`, `bindStorageBuffer`, `bindTexture`, `bindUniformBlock`, `dispatch`, `submit` (`compute.dart:144-226`). The compute audit owns the rest. |
| `TransferEncoder` | `abstract base class` | 7 | 1 | `submit` only (`transfer.dart:57-139`). |
| `ShaderLibrary` / `LoadedShaderLibrary` | base mixin class / base mixin | 1 / 2 | 1 / 2 | `operator []`; `name`, `refresh`. |
| `MappedBuffer` | `abstract base class` | 2 | 2 | `bytes`, `unmap` (`resources.dart:611`). |
| `SynchronousBufferReadback` | `base mixin on GraphicsDevice` | 1 | 1 (listed in `backend.dart` and `testing.dart`) | Moved out of the main library (2A). |
| `EncodedImageUpload` | `base mixin on GraphicsDevice` | 1 | 1 | `decodeTexture` is non-null now (2A). |
| `ComputeWorkload`, `WorkloadRecorder` | `abstract base class` | — | 4, 3 | New since 10-09; the compute audit covers them. |

`DeviceFeature` had 61 values on 10-09 and has 75 now: 64 stable and 11
reserved (`capabilities.dart:104-692`). The four enums that remain
(`WindingOrder`, `CompareFunction`, `FramebufferOrigin`,
`StorageTextureAccess`) are closed on purpose. Every other set is a
`final class` with `values`/`byName` (`formats.dart`, `resources.dart`,
`vertex_layout_spec.dart`, `sharing.dart`).

The rule that keeps D25 true is mechanical. In `tool/structure/api.dart:514-529`,
a member added as `abstract` to a type outside code extends is `Bump.major`,
and a member that loses its body is a major too (`:463-472`).
`backend.dart` carries its stability sentence (`lib/backend.dart:17-22`),
README carries the D25 sentence (`README.md:85-97`), and the CHANGELOG labels
each 2A break "for outside backends" (`CHANGELOG.md:191-235`).

## 2. Capability coverage

Columns: **HAL** says how the contract expresses the feature. The five
backend columns are taken from the reporting table in `HAL.md:900-957`. I
spot-checked that table against `gpu_capabilities.dart`, `webgpu_encoder.dart`,
the WebGL extension probes, `wgpu_device.dart:134-138` and
`null_device.dart:56-58`, and found no disagreement. **Gate** names the
capability flag or refusal. **Conf.** shows what the shared suite holds:
**P** means pixels or bytes are compared, **H** means the honesty probe only
(the call does not throw where the feature is listed, and is refused by name
where it is not), **R** means the refusal half only, and **—** means nothing.

| Feature | HAL | cpu | webgl | webgpu | impeller | wgpu | Gate | Conf. |
|---|---|---|---|---|---|---|---|---|
| Vertex / index geometry | `uploadGeometry`, `bindVertexBuffer/Data`, `bindIndexBuffer/Data` | yes | yes | yes | yes | no draw | core | P (`a buffer is uploaded for its declared use`) |
| General buffers + usage flags | `createBuffer(BufferDescriptor)`, `BufferUsage` bits | yes | yes | yes | yes | yes | `buffers` + `BufferDescriptor.checkFeatures` | H |
| Uniform buffers bound by range, dynamic offsets | **no verb**; `BufferUsage.uniform` exists, but nothing binds a buffer to a block (`resources.dart:342`) | — | — | — | — | — | none | — |
| Uniforms by member / by bytes | `bindUniformBlock` (floats), `bindUniformBytes` | yes / no | yes / yes | yes / yes | yes / yes | — | core / `uniformBytes` | P (block member refusal) / H |
| Storage buffers in render stages | `bindStorageBuffer/Texture` on `PassEncoder` | yes | no | no (reflection gap, `webgpu_encoder.dart:525-543`) | no | — | `renderStageStorage` | H |
| Mapping | `mapBuffer`, `MappedBuffer` | yes | yes | yes | no | — | `mappedBuffers` | H |
| Partial updates | `overwriteGeometry`, `writeBuffer`, `writeTexture`, `overwriteTexture` | yes | yes | yes | yes | — | core / `buffers` / `textureWrites` | P for geometry and the RGBA8 region, H for the rest |
| 2D / mip chains | `createTexture`, `createTextureFromPixels(mipLevels:)` | yes | yes | yes | yes | — | `manualMipmaps` | P |
| 3D / 2D array / cube / cube array / 1D | `TextureDimension` | all | 3D, array, cube | all | cube (probe), 1D | — | per-shape features via `TextureDescriptor.checkFeatures` | P (cube faces, 3D field, array layers via XR checks), H (cube array, 1D) |
| MSAA + resolve | `sampleCount`, `StoreAction.multisampleResolve`, `resolveTexture` | no | if proven | yes | if flutter_gpu | — | `offscreenMultisample`, limit `maxSampleCount` | P |
| Depth / stencil formats | `d16`, `d24S8`, `d32F`, `d32FS8`, `s8` | yes | yes | yes | context's | — | `textureFormatSupport.depthStencil`, `stencil` | P (stencil, depth write) |
| sRGB | `*SRGB` formats | yes | yes | yes | yes | — | `textureFormatSupport` | **—** (no encode/decode check) |
| HDR float formats | `rgba16F`, `rgba32F`, `r11g11b10`, `rgb9e5`, … | yes | per extension | per adapter | Metal on macOS | — | `float32Filterable/Renderable/Blendable`, `rg11b10Renderable` | P |
| Compressed BC / ETC2 / ASTC | BC1/3/5/7, ETC2, ASTC 4x4 and 8x8 LDR/HDR | no | per extension | per adapter | per family | — | `textureCompression*` | P |
| Storage textures | `bindStorageTexture`, `TextureUsage.storage` | yes | no | yes | no | yes | `storageTextures`, `readWriteStorageTextures` | H / compute kernels |
| Texture views, swizzle, sRGB reinterpretation | **absent** | — | — | — | — | — | — | — |
| Sampler anisotropy / compare / border / LOD clamp | `SamplerDescriptor` | yes | aniso, compare, LOD | aniso, compare, LOD | aniso only | — | limit (clamped), `samplerCompare`, `samplerBorderColor`, `samplerLodClamp` | P (aniso accepted, null sampler), H (rest) |
| Blend per attachment, MRT | `setBlend(attachment:)`, `RenderPassDescriptor.colors` | yes | if `OES_draw_buffers_indexed` | yes | yes | — | `independentBlend`, `maxColorAttachments` | P (attachment limit both ways) |
| Blend constant | `setBlendColor` | yes | yes | **no** (feature too coarse, see S5) | no | — | `blendConstant` | P/R |
| Min/max, dual-source blend | `BlendOperation`, `BlendFactor.source1*` | yes | yes / ext | yes / adapter | no | — | `minMaxBlend`, `dualSourceBlending` | H |
| Depth bias (+clamp) | `setDepthBias(DepthBias)` | yes | yes / no | yes | no | — | `depthBias`, `depthBiasClamp` | H |
| Stencil ops | `setStencil` front/back, masks | yes | yes | yes | yes | — | `stencil` | P |
| Cull / front face | `setCullMode`, `setWindingOrder` | yes | yes | yes | yes | — | core | P (via draws) |
| Topology incl. strips, points | `setPrimitiveType` (5 values) | tri + line only, others `UnsupportedError` | all | all | all | — | **no feature; untyped refusal** | P (`assembled as itself or refused`) |
| Primitive restart | **unspecified** | n/a | always on | always on for strips | driver | — | none | — |
| Polygon mode | `setPolygonMode` | no | no | no | Metal/Vulkan | — | `wireframe` | P |
| Alpha to coverage | `setAlphaToCoverage` (ignored by default) | no | if proven | yes | no | — | `alphaToCoverage` (ignore, not refuse) | — |
| Sample mask | **absent** | — | — | — | — | — | — | — |
| Depth clamp | `setDepthClamp` | yes | ext | adapter | no | — | `depthClamp` | H |
| Color write mask | `setColorWriteMask` | yes | yes | yes | no | — | `colorWriteMask` | H |
| Async compile / pipeline cache | `createPipelineAsync`, `createPipelineFrom[Async]`; cache absent | sync | `KHR_parallel_shader_compile` | async, warms guessed states | sync | — | none (default links synchronously) | — |
| Load/store, clear values | `ColorTarget`/`DepthTarget` actions, `clearValue` | yes | yes | yes | yes | — | core | P (`a clear covers the whole attachment`) |
| Viewport / scissor | `setViewport/setScissor(ScreenRect)` (int, no depth range) | yes | yes | yes | yes | — | `viewportBeyondTarget` | P |
| Multiview | `RenderPassDescriptor.viewMask`, `ViewPasses` fallback | no | no (`OVR_multiview2` not wired) | no | no | — | `multiview`, `maxMultiviewViews` | P (declines everywhere) |
| Instanced, base vertex/instance | `draw(instanceCount:)`, `drawIndexed(IndexedDraw)` | yes | ext | yes | no | — | `baseVertexBaseInstance` | P (instancing) / H |
| Non-indexed, multi-draw | `drawNonIndexed`, `multiDraw` | yes | yes | yes | yes | — | `nonIndexedDraw`, `multiDraw` | H |
| Indirect, multi-draw-indirect (+count) | `drawIndirect`, `multiDrawIndirect` | yes | no | yes / adapter | no | — | `indirectDraw`, `indirectFirstInstance`, `multiDrawIndirect` | H |
| Render bundles | `createRenderBundleEncoder`, `executeBundles` | yes | yes | yes | no | — | `renderBundles` | H |
| Occlusion / timestamp / statistics queries | `createQuerySet`, `readQueryResults`, `PassTimestampWrites` | yes / yes / yes | yes / if timer counts / no | yes / adapter / no | no | timestamp | per `QueryType.feature` | H |
| Frame GPU timings | `onGpuTimings` | no | no | adapter | own timeline | — | `gpuTimestamps` | — (unprobed) |
| Readback async / sync | `readback` (RGBA8 premultiplied), `readBuffer`, `readBufferSync` | yes / yes | yes / yes | yes / no | yes / no | yes / yes | core / `synchronousReadback` | P / H |
| Readback of a mip, layer, face or depth | **absent from `readback`**, reachable only through `copyTextureToBuffer` + map | — | — | — | — | — | `bufferTextureCopy` | — |
| Buffer↔buffer, buffer↔texture, texture↔texture | `TransferEncoder` | yes | yes | yes | no (partial, refused whole) | no | `bufferCopy`, `bufferTextureCopy`, `textureCopy` | H, P for texture copies (XR) |
| Blit (scaled), clear texture, mip generation | **absent** by design (`MipChain` above the seam) | — | — | — | — | — | — | — |
| External / imported textures | `importTexture(NativeHandle)`, `TextureType.textureExternalOES`, `SharedTexture` host copy | host copy | host copy | host copy | host copy | host copy | `sharedTextures/Buffers/Fences` | P (host copy), R (zero copy) |
| ui.Image, Flutter `Texture`, video, camera | **absent**; widget surfaces round-trip GPU→CPU→GPU (`flutter3d_app/.../widget_texture.dart:24-25`) | — | — | — | — | — | — | — |
| Presentation | out of the HAL by design: `DeviceRegistry<P>.addPresenter`; `hdrOutputFormats` | — | — | — | — | — | `presenterColorSpaces` reserved | — |
| Device loss | `lost`, `isLost`, `DeviceLoss` | dispose | context events | `device.lost` | dispose | **none** | — | **—** |
| Lifetime / leaks | owner + `dispose`, `debugCheckLive`, `FakeBackend.liveHandles` | | | | | | debug asserts | — (no double-dispose check in the suite) |
| Memory budget | **absent**; engine-side `estimatedBytes` (`texture.dart:154`) | — | — | — | — | — | — | — |
| Labels, debug groups | `setLabel`/`labelOf`, push/pop/insert | | | passes on | | | none | — |
| Error scopes, validation | **absent**; WebGPU throws last frame's errors at `beginFrame` | — | — | ledger | — | — | — | — |
| Threading | one isolate, one call at a time (`HAL.md:797-815`) | | | | | | — | — |

**Compute meets rendering** in four places: `StorageBuffer.asVertices`/`asIndices`
(`compute.dart:66, 91`), indirect arguments, `renderStageStorage` (CPU only), and
`SharedBuffer` across the sidecar boundary (host copy only). In all four,
ordering comes from submission order and hazard tracking is the backend's job.
On WebGPU, GPU-driven rendering therefore reaches the frame only through
`asVertices`/`asIndices` and indirect draws, never through storage reads in a
render stage. The compute audit has the details.

## 3. Against the target APIs: additive in 1.x, or a break?

**Checked** against flutter_gpu in the installed SDK 3.47.0
(`~/.local/share/mise/installs/flutter/3.47.0/bin/cache/pkg/flutter_gpu/lib/src`)
and the Impeller sources in the same SDK (`engine/src/flutter/impeller/renderer`).
WebGL2 and WebGPU are compared from the extension probes the two backends make
and from the WebGPU feature list.

**How growth works.** Dart forbids widening an overridden member, so a
backend-overridden member can never gain a parameter. Growth comes as (a) a new
member with a refusing body, (b) a defaulted descriptor field that
`checkFeatures` gates by a new feature, (c) a constant of an open class, or
(d) a defaulted field on a value class. HAL.md's growth table
(`HAL.md:995-1018`) answers "needs a shape change: none" for every area. That
is right for almost everything, and wrong in three cases: B1, S2 and S5 below.

| Feature | Source | Additive in 1.x? | How, or why not |
|---|---|---|---|
| Strip/point topologies as a capability, 32-bit index support, primitive restart | Impeller `capabilities.h:87-94` (`SupportsTriangleFan`, `SupportsPrimitiveRestart`, `Supports32BitPrimitiveIndices`); WebGL2 and WebGPU always restart on strips; the CPU refuses strips | **No** | A feature added later gates a call that 1.0 backends already accept. The honesty check then demands that a backend not listing it refuse it, so a 1.0 backend fails a 1.x conformance run. See B1. |
| Device-creation options (required features and limits, power preference, adapter, validation, colour space) | WebGPU `requestAdapter`/`requestDevice` | **Only beside the old API** | `BackendOpener` is a function typedef (`device_registry.dart:42-43`), and a new named parameter makes every existing `open` unassignable. Needs a second typedef and `addBackendWith`. See S2. |
| Blend constant on WebGPU | WebGPU `setBlendConstant` (colour constant only) | **Only with an OR rule** | `blendConstant` covers four factors, including GL's `CONSTANT_ALPHA` (`formats.dart:638-646`), so WebGPU refuses all four (`webgpu_encoder.dart:1325-1336`). A narrower feature later has to be accepted as "either one" by `BlendState.checkFeatures`. See S5. |
| Texture views (mip/layer range, dimension, sRGB reinterpret, `texture-component-swizzle`) | WebGPU `createView`; flutter_gpu has none | Yes | A `createTextureView` member refusing by a new feature, returning a `TextureHandle` (`wrapTexture` gains optional fields). An old backend never creates one, so it never receives one. `bindTexture` itself cannot grow (`command_encoder.dart:373-378`). |
| Viewport depth range, fractional viewport | WebGPU `setViewport(…, minDepth, maxDepth)`; **flutter_gpu 3.47 `Viewport.depthRange`** (`render_pass.dart:210-224`) | Yes | A new member (`setViewportRange`) with a refusing body. `ScreenRect` is int (`render_pass_descriptor.dart:38-41`). |
| Bind a buffer range as a uniform block, dynamic offsets | WebGPU dynamic offsets; flutter_gpu `bindUniform(slot, BufferView)` (`render_pass.dart:470`); Impeller `BindDynamicResource` | Yes | A new member plus a feature. `BufferUsage.uniform` is a bit with no verb today (S10). |
| Readback of a mip, layer, face or depth aspect | WebGPU `copyTextureToBuffer` with `aspect` | Yes | A `readbackFrom(ReadbackDescriptor)` member, and an `aspect` field on `TextureCopyLocation` (`transfer.dart:27-55`). |
| Device-side mip generation, scaled blit, clear texture | Impeller `BlitPass::GenerateMipmap`, `ResizeTexture` (`blit_pass.h:48, 143`); WebGL `generateMipmap` | Yes | `TransferEncoder` members with refusing bodies. "Supplied, not generated" (`graphics_device.dart:300-307`) stays the rule for uploads. |
| ui.Image import, Flutter `Texture`, video | flutter_gpu `Texture.fromImage` (`texture.dart:102`), `asImage` (`:248`), `GpuImageSurface` (`surface.dart:95`) | Yes | A backend-package mixin (the HAL may not name `dart:ui`), asked with `is`, which is the `EncodedImageUpload` pattern. An engine-generic entry would need an opaque handle type. |
| Formats: BC4, BC6H, EAC R11/RG11, other ASTC block sizes, norm16, snorm8, rg8 integer | WebGPU `texture-formats-tier1/2`, `EXT_texture_norm16` | Yes | `TextureFormat` constants with new indices. Backends must end every `switch` with a refusing wildcard (`HAL.md:88-92`). |
| Compressed 3D (`texture-compression-*-sliced-3d`) | WebGPU | Yes | A feature that `TextureDescriptor.checkFeatures` asks for a compressed format with `d3`. |
| Half and normalised vertex formats | WebGPU `float16x2`, `unorm8x4`, `snorm16x2`…; glTF quantisation | Yes | `VertexFormat` constants. Only 32-bit formats exist today (`vertex_layout_spec.dart:58-135`). |
| Sample mask | WebGPU `multisample.mask` | Yes | A member with a body that ignores the call (the alpha-to-coverage pattern), or a refusing one. |
| Pipeline cache, warm-up state hint | WebGPU needs formats, sample count and blend state at pipeline creation | Yes | `PipelineDescriptor` fields with defaults (`pipeline_descriptor.dart:29-52`). WebGPU's `createPipelineAsync` guesses states today (`webgpu_device.dart:1528-1591`). |
| Storage bindings reflected for render stages | WebGPU core (fragment storage) | Yes | A `StageBindings` field. This unblocks `renderStageStorage` on WebGPU. |
| Non-fatal validation errors | WebGPU error scopes and `uncapturederror` | Yes, if the `beginFrame` semantics are decided first (S3) | A `Stream<DeviceError>` with an empty default. |
| Memory budget | `VK_EXT_memory_budget`, Metal `recommendedMaxWorkingSetSize`; none in WebGPU | Yes | A getter with a null default. |
| Conditional rendering, timestamps inside a pass, query resolve to a buffer | Vulkan, Metal, D3D | Yes | Members and `QueryType` constants (already in the HAL.md table). |
| Shader-language features (`shader-f16`, `subgroups`, `clip-distances`, `primitive-index`) | WebGPU, `WEBGL_clip_cull_distance` | Yes | `DeviceFeature` constants that `loadShaders` refuses by. `primitive-index` is not named yet. |
| Ray query, mesh shaders, bindless, immediate data, VRS, depth resolve, async compute, int64, conservative raster, depth bounds, presenter colour spaces | Vulkan, Metal, D3D12 | Yes | Already reserved (`capabilities.dart:612-692`). `maxImmediateDataSize` is already in `DeviceLimits`. |
| New limits | WebGPU adds limits per spec revision | Yes, **with a rule** | A field with a default on a `final class` (`capabilities.dart:884-916`). The defaults are WebGPU minimums, so a 1.0 backend inherits a new limit's minimum without having asserted it. A limit that may be below the minimum on some backend must default to 0 or 1, as `maxMultiviewViews` does. The rule should be written down (S9). |

**Where implementations lag APIs that already exist** (LATER, not a contract
matter). Impeller: flutter_gpu 3.47 has `copyBufferToTexture`,
`copyTextureToBuffer` and `copyTextureToTexture` on `CommandBuffer`
(`command_buffer.dart:140-240`). The backend uses them internally but reports
no copy feature, because the support is partial and features are
all-or-nothing (`gpu_capabilities.dart`, closing comment). It also has
`Viewport.depthRange`, `Texture.fromImage` and `GpuImageSurface`, and Impeller
has `SetBaseVertex` internally (`render_pass.h:68`). WebGL2:
`WEBGL_polygon_mode` (wireframe), `EXT_polygon_offset_clamp` (bias clamp),
`WEBGL_clip_cull_distance`, `OVR_multiview2`, and `TIME_ELAPSED` timer queries
for `gpuTimestamps` all exist and are not wired; none of them appears in the
`flutter3d_webgl` extension probes. WebGPU: `renderStageStorage` waits on
reflection (`webgpu_encoder.dart:525-529`).

## 4. The outside-backend story (D25–D28)

**Checked**, with the tests run where marked.

| Promise | State |
|---|---|
| D25: bodies on every feature-gated encoder member; the `backend.dart` sentence; CHANGELOG labels | **Done.** See §1. A mechanical classifier holds it (`tool/structure/api.dart:514-529`). |
| D26: `MaterialCompilerRegistry`; `RuntimeShaders` and the build consult it; the four backends register | **Half done.** Run time: `RuntimeShaders(compilers:)` asks the backend's compiler first (`flutter3d_core/lib/src/data_plugin/runtime_shaders.dart:129-157, 252`). Registration: `registerGpuBackend`/`registerWebGlBackend(compilers:)` (`gpu_backend_registration.dart:24`, `webgl_backend_registration.dart:24`). Build time: **no shipped path hands `runShaderBuild` a registry** (`commands.dart:308`, `build_steps.dart:312`). HAL.md says so itself (`HAL.md:721-731`) and moves pubspec discovery to rc.2. |
| D27: `compileStage({target})`, `stageBindings`/`uniformBlocks` in `flutter3d_shaders/backend.dart`, the ABI file | Present according to `HAL.md:709-755`. Not re-verified line by line here (the shader audit's ground). |
| D28: `renderFrame(device:)`, `testReplay(device:)`, `drawOnce` exported | **Done** (`flutter3d_testing/api`: `drawOnce`, `renderFrame({… BackendOpener? device})`, `testReplay(… BackendOpener? device …)`). |
| D28: conformance on one `decline()` | **Done**: no silent `return` on a missing feature is left in `src/` (rg for `features.has(...)) return`), and `runDeviceConformance` skips a decline (`flutter3d_conformance.dart:258-283`). |
| D28: `examples/flutter3d_backend_null` passes conformance and reaches no `src/` | **Done, run**: `dart test` in the example gives 14 passed and 12 skipped, every skip with a sentence. The rule `an outside example reaches only the published API` exists (`tool/structure/rules.dart:53`). |
| D28: `flutter3d create plugin --kind backend` from the example | **Done, run**: `plugin_template_test.dart -N backend` gives 5 of 5, including "is the null backend example, file for file". |
| D28: the `implements`→`extends` detector | **Fixed** (`tool/structure/detectors.dart:1115-1126`, with a self-test for `extends` at `:2596`). |
| D28: guide and SKILL rewritten | **Done**: `site/content/core/backends.md` and the SKILL no longer show `supportsX` or `present`. HAL.md is a complete reference, with a compiling skeleton (`HAL.md:1062-1356`). |
| "Every backend owes a `DeviceLoss` at least for its own dispose" (`graphics_device.dart:1004-1012`, `HAL.md:189-191`) | **Not kept by the reference example or the sidecar.** `NullDevice.dispose` only sets a flag (`examples/flutter3d_backend_null/lib/src/null_device.dart:435`). `flutter3d_wgpu` has no `lost` (`wgpu_device.dart:737`). No conformance check asks. See S7. |

## 5. Gaps by severity

### BLOCKER

**B1. Universal assumptions that cannot be gated later.**
`setPrimitiveType` documents that "there is no capability to ask first" for
strips and points (`command_encoder.dart:133-148`). The CPU refuses them from
the draw with an untyped `UnsupportedError` (`flutter3d_cpu/lib/src/cpu_encoder.dart:936-937`).
Primitive restart is specified nowhere: WebGL2 and WebGPU always restart on a
strip, the CPU has no strips, and Impeller follows the driver. 32-bit indices
(`IndexType.int32`, `formats.dart:994-996`) are assumed everywhere, while
Impeller's GLES path has a capability for them.

Once 1.0 ships, a `DeviceFeature` for any of these gates a call that 1.0
backends already accept. `checkCapabilitiesAreHonest` then demands that a
backend not listing it refuse by name, so a 1.0 backend fails a 1.1 suite. The
only other route is a permanent special case in the honesty check.

**Fix now, cheaply:**
- Add stable features `primitive-strips` and `point-primitives`, listed by
  webgl, webgpu and impeller and not by cpu.
- Make the CPU refuse with `UnsupportedCapabilityException`.
- Pin the restart rule in `setPrimitiveType`'s doc: "an all-ones index in a
  strip restarts it, on every backend that lists `primitive-strips`". Add it
  to the existing primitive check.
- Either declare 32-bit indices universal in the doc, or add an `index-uint32`
  feature now.

### SHOULD

**S2. No room for device-creation options.**
`BackendOpener = Future<GraphicsDevice> Function({required int width, required int height})`
(`device_registry.dart:42-43`; `ComputeOpener` at `:34`). There is nowhere to
request features or limits (WebGPU's model), a power preference, an adapter,
validation or a debug layer, a canvas, or a colour space. WebGPU asks the
adapter for everything it knows (`HAL.md:893`). A parameter added later breaks
every backend's `open`.

**Fix:** before the freeze, make it `Function(DeviceRequest request)`, where
`DeviceRequest` is a final class with `width`, `height` and defaulted fields
(`requiredFeatures`, `requiredLimits`, `powerPreference`, `debug`). The
alternative is to accept a parallel `addBackendWith` in 1.x.

**S3. No channel for asynchronous errors.**
WebGPU collects validation and allocation errors and throws them at the next
`beginFrame` (`webgpu_device.dart:1741-1764`, `webgpu_error_ledger.dart:12-20`).
The HAL's `beginFrame` (`graphics_device.dart:400-408`) promises no throw, and
the other backends do not throw there. The behaviour is a contract term that
one backend introduced on its own.

**Fix:** either state in `beginFrame`'s doc that it may throw a
`DeviceResourceException` or `ShaderCompileException` for the previous frame's
refusals, or add `Stream<DeviceError> get errors` with an empty default and
move WebGPU onto it. The choice must be made before the freeze, because
changing what `beginFrame` may throw later is a change of meaning.

**S4. The clear value is a mutable float32 vector.**
`ColorTarget.clearValue` is a `vm.Vector4?` (`render_pass_descriptor.dart:302-305`;
the API snapshot has it at `:147` and `:2036`, the second on the trace
target). It is the only `vector_math` type in the contract, so a `vector_math`
major forces a HAL major. It is mutable inside an `@immutable` descriptor. It
is float32, so an integer target (`r32UInt` ids) clears exactly only up to
2^24. `setBlendColor` already takes `LinearColor`.

**Fix:** replace it with an immutable `ClearColor` holding doubles, or with
`LinearColor` plus a separate integer clear, before the freeze. Otherwise
deprecate it in 1.x and carry it to 2.0.

**S5. `blendConstant` is too coarse.**
One feature covers four factors (`capabilities.dart:115-120`), two of which
(`blendAlpha`, `oneMinusBlendAlpha`, `formats.dart:644-646`) WebGPU cannot
form. WebGPU therefore loses the blend constant entirely
(`webgpu_encoder.dart:1325-1336`).

**Fix now:** narrow `blendConstant` to the two colour factors and add
`blend-constant-alpha` for GL's pair. Done after 1.0, `BlendState.checkFeatures`
has to accept "either feature", which HAL.md freezes as "the order of the
existing questions and the feature each names" (`HAL.md:448-450`).

**S6. Conformance holds behaviour for few of the 1.0 features.**
The honesty probes for `depthBias`, `depthBiasClamp`, `colorWriteMask`,
`depthClamp`, `minMaxBlend`, `dualSourceBlending`, `samplerCompare`,
`samplerLodClamp`, `samplerBorderColor`, `multiDraw`, `nonIndexedDraw`,
`baseVertexBaseInstance`, the indirect draws, `renderBundles`, the three query
types, `bufferCopy`/`bufferTextureCopy` and `mappedBuffers` only make the call
(`flutter3d_conformance/lib/src/capability_checks.dart:511-790`, for example
`:597-620`). None compares pixels or bytes, and `flutter3d_conformance_render`
does not either. With three or four backends each implementing these, a wrong
bias sign, a write mask applied to the wrong attachment, or query results in
another unit go unseen.

**Fix:** one pixel or byte check per feature, declining without it.
Priorities: depth bias, colour write mask, sampler compare, indirect draw
counts, buffer copies and occlusion results.

**S7. The lifetime and loss promises are unchecked, and the reference example
breaks one.** No shared check covers sRGB encode on render and decode on
sample, `lost` emitting `DeviceLossReason.destroyed` on `dispose`, a double
`dispose` asserting, or `debugCheckLive` naming a use after dispose (rg in
`flutter3d_conformance/lib/src` finds none of these). `NullDevice.dispose`
(`null_device.dart:435`) and the wgpu sidecar (`wgpu_device.dart:737`) report
no loss, though the HAL says an outside backend "owes the same"
(`graphics_device.dart:1010-1012`). The template copies the example, so every
new backend starts in breach.

**Fix:** add the loss to the example and to wgpu, and add an sRGB check, a
loss-on-dispose check and a debug-mode double-dispose check.

**S8. "A member with a body breaks none" is not quite true.**
`tool/structure/api.dart:1317-1319`, `README.md:85-97` and `HAL.md:79-86` make
the claim. A minor that adds `PassEncoder.setViewportRange` breaks any outside
backend that already declares a public member of that name with another
signature. A same-name member with a compatible signature silently overrides
the new default, which may be worse.

**Fix:** a sentence in HAL.md's stability section and in the template:
backend-specific members are private, or carry the backend's prefix
(`vkSomething`). Optionally, have the snapshot tool list the names a minor
introduces on extended types.

**S9. Versioning is stated two ways.**
`tasks/1.0-stability.md:40-44` (decision 2) says `flutter3d_hardware` "ships
under a number of its own, which rarely breaks". `HAL.md:74-77` says it is
versioned with the engine's major.minor. The in-repo backends pin
`'>=1.0.0-rc.1 <1.1.0'` (`flutter3d_impeller/pubspec.yaml:41`, and the same in
webgl, webgpu, cpu and wgpu), while HAL.md says "every backend depends on it
through a caret range" and the template writes `^1.0.0-rc.1`
(`plugin_template.dart:1006`). Under lock-step, an engine major for unrelated
reasons forces every outside backend to republish.

**Fix:** pick one. An independent HAL line is better for outside backends.
Then make the in-repo constraints match what the docs tell others to write,
and add the rule for new `DeviceLimits` defaults (§3, last row) to HAL.md.

**S10. The HAL.md growth table and some docs claim more than holds.**
- The growth table (`HAL.md:995-1018`) says "Needs a shape change: none" in
  every row. It should name B1, S2, S4 and S5.
- `BufferUsage.uniform` is documented as needing `buffers`
  (`HAL.md:347`), but no HAL call consumes it. Say that it is reserved for a
  buffer-bound uniform block, or drop it before the freeze.
- Stale docs: `TextureDimension.d1` says it is "gated by `textureWrites` alone
  … with no feature of its own" (`resources.dart:36-39`), but `texture1D`
  exists (`capabilities.dart:596-602`) and `checkFeatures` asks for it
  (`resources.dart:224`). `command_encoder.dart:13-18` and `:390-391` still
  say non-indexed draws are absent, though `drawNonIndexed` exists at `:602`.
  `:25` says "three backends".
- `overwriteTexture` refuses formats with `UnsupportedError`
  (`graphics_device.dart:329`), a type the refusal table does not list
  (`HAL.md:822-831`).

**S11. The build half of D26 is not wired.** See §4. An outside backend's
material section reaches a project only by hand until rc.2. It is not a
contract shape, but it is the second thing a fifth-backend author hits after
conformance.

### LATER (additive in 1.x)

- **L1.** Texture views: mip and layer ranges, dimension, sRGB
  reinterpretation and swizzle, through a view-creating member (§3).
- **L2.** Viewport depth range and a float viewport. flutter_gpu already has
  the first (§3).
- **L3.** Buffer-bound uniform blocks with dynamic offsets. flutter_gpu,
  Impeller and WebGPU all have them (§3).
- **L4.** Readback by mip, layer, face or depth aspect; an `aspect` on
  `TextureCopyLocation`; a `copySource` flag in `TextureFormatSupport`.
- **L5.** Device-side mip generation, a scaled blit and a texture clear on
  `TransferEncoder`.
- **L6.** Platform textures (`ui.Image`, Flutter `Texture`, video, camera)
  through a backend mixin. `Texture.fromImage` would remove the widget
  surface's CPU round trip on Impeller (`widget_texture.dart:24-25, 87-89`).
- **L7.** More formats (BC4, BC6H, EAC, ASTC sizes, norm16, snorm8),
  half-precision and normalised vertex formats, and compressed 3D.
- **L8.** `PassState` lacks every 1.0 setter: colour write mask, depth bias,
  depth clamp and alpha to coverage (`pass_state.dart:77-106`). HAL.md offers
  it as the PSO accumulator for a Vulkan-shaped backend (`HAL.md:486-488`).
  Add the fields with defaults.
- **L9.** Pipeline cache and state hints on `PipelineDescriptor`. WebGPU's
  async path guesses states today.
- **L10.** A memory budget query, a non-fatal error stream (after S3), and a
  sample mask.
- **L11.** Provoking vertex for `flat` varyings. The engine's shaders use
  none, but a plugin material can, and GL and WebGPU differ. Pin it in the
  doc or add a feature.
- **L12.** Finer features where support is partial: Impeller's level-0 texture
  copies are refused whole.
- **L13.** Implementation lag behind the APIs (Impeller copies, viewport depth
  and `fromImage`; the WebGL extensions listed in §3; WebGPU render-stage
  storage reflection).
- **L14.** A WebGL device draws into one canvas and cannot share resources
  with a second context. Two views therefore need two devices with no zero
  copy between them. Presenters and `SharedTexture` host copies cover this,
  slowly.

## 6. HAL design practice

| Practice | Here | Judgement |
|---|---|---|
| Handles vs objects | Handles are `final` with private constructors and an opaque `Object backend`, made through `backend.dart`'s `wrap*` with an owner. A sampler is a value with `releaseSampler`. `TextureHandle` has no `==` on purpose. | Good. The untyped `backend` field is justified (audit 11). |
| Where validation sits | Descriptor `checkFeatures` lives in the HAL, and every backend calls it on the way in. `indexWindow` and `readbackRegionOf` are shared. Limits go through `checkAttachmentLimit`. | Very good: the same words on every backend, and new fields are refused by old backends. |
| Typed refusals | `UnsupportedCapabilityException` from the foundation, `DeviceResourceException`, `PipelineRefusedException` reported rather than thrown, `ShaderBundleException.stale`. | Good, apart from the remaining `UnsupportedError` sites (B1, S10). |
| Capability negotiation | Reported after open: `features`, `limits`, per-format `textureFormatSupport`, and reserved features that cannot be reported. | Good for reporting. Requesting at open is missing (S2). |
| Open enums | Every growable set is an open class with `values`/`byName`, and the four closed enums are justified. | Good. |
| Versioning | Strict semver by snapshot, with a classifier that knows extended versus implemented types. | Good mechanics. The policy text is inconsistent (S9). |
| Pass state vs PSO | Raster state lives on the pass (Impeller-shaped), with `PassState` for PSO backends. | Deliberate and documented (`command_encoder.dart:52-60`). Costs CPU on WebGPU/Vulkan. Additive mitigations exist (L8, L9). |
| Binding model | By name per stage, with reflection in `StageBindings`. | Portable and simple. Bindless and dynamic offsets are additive (L3). |

## 7. What is good

- D25 landed in full, and a classifier enforces it rather than a sentence in a
  README.
- The descriptor-plus-`checkFeatures` pattern is what makes most of §3
  additive. A field added in 1.3 is refused by a backend compiled against 1.0,
  because the refusal lives in the package that grows.
- `createPipelineFrom(PipelineDescriptor)` exists precisely so that
  `createPipeline` never needs a parameter (`graphics_device.dart:811-837`).
- Reserved features keep the names of the next decade's capabilities without
  promising calls, and `DeviceFeatures` throws if one is reported.
- The per-backend reporting table in HAL.md matches the code where I checked,
  and Impeller's gaps are each a named refusal with a `TODO(impeller)` and the
  upstream ticket.
- The outside story works end to end: the null backend passes its tier, the
  template is held to it file for file, a backend registers itself and its
  compiler, and the testing package takes a device.
- Deferred destruction, frames in flight (`onFrameComplete`), "visible from
  the next pass" and readback ordering are written as contract terms, each
  with the check that holds it.

Nothing in the code was changed. I ran `dart test` in
`examples/flutter3d_backend_null` (all passed: 14 passed, 12 skipped with
reasons) and `dart test test/plugin_template_test.dart -N backend` in
`flutter3d_build` (5 of 5).
