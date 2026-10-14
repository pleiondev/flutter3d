# Compute in the hardware layer (branch 1.0.0, 2026-10-14)

Agent notes. I read the code and did not change it. Every line reference is against `9f4312f64`.

## Verdict

The compute shape of `flutter3d_hardware` can ship as 1.0. I found **no blocker**. Each member of `ComputeEncoder` behind a feature now has a refusing default body (`compute.dart:180-211`). Placements, refusal reasons, binding kinds and query types are open classes. Pipeline inputs go through `ComputePipelineDescriptor` (`pipeline_descriptor.dart:80-112`). Binding is by name, so the HAL never commits to a bind group layout. Every gap against WebGPU compute can be filled additively: workgroup memory and barriers, uniforms in kernels, more storage-texture formats, multiple queues, a uniform binding fed from a GPU buffer.

What I would fix before tagging is behaviour, hygiene and documentation. These are the most serious:
- The CPU executor and the GPU executors order a workload's writes differently, which breaks the "same bytes" promise.
- The sidecar and CPU compute devices are opened lazily and never disposed.
- Kernels that fail on a GPU fall back to the CPU silently.
- Nothing validates against the portable limits: storage offset alignment, dispatch size, storage bindings per stage.
- Authors have no guide or example for writing a kernel. The material-compute path also bypasses the placement rule that the HAL says it alone owns.
- One semantic needs a decision now. HAL.md freezes the rule that nothing above the layer chooses a placement, and the workload rule always prefers a GPU over a simulation's own bit-exact host code. A deterministic game currently has no way to say "keep this on the host". The escape hatch should be worded as a requirement, not a placement, before 1.0 freezes the text.

## 1. The contract as it stands

| Area | What exists | Where |
|---|---|---|
| Pipelines | `createComputePipeline(ShaderHandle)`, `…Async`, `…From(ComputePipelineDescriptor)`, `…FromAsync`; `releaseComputePipeline` | `graphics_device.dart:543-545, 787-826`; `pipeline_descriptor.dart:80-112` |
| Shader modules | A compute stage is a `ShaderHandle` of `ShaderStageKind.compute` from a loaded bundle. Two sources: the engine's GLSL `.comp` stages, translated by glslang and naga into a generated WGSL table (`engine_compute_shaders.dart`, WebGPU only, with a hand-written Dart twin of `PrefixSum` on CPU); and kernel-language kernels in the bundle's `kernel` section, which each device translates as it loads them | `shader_bundle.dart:227-239, 573-586`; `flutter3d_webgpu/tool/generate_compute_shaders.dart`; `flutter3d_shaders/lib/src/compute_kernel.dart` |
| Binding model | By name: `bindStorageBuffer(stage, name, buffer, {offset, size})`, `bindTexture`, `bindStorageTexture(…, mipLevel, access)`, `bindUniformBlock` (float map), `bindUniformBytes` (std140 bytes). `bindPipeline` forgets every binding. A name the stage does not declare answers false. Groups and bindings are the backend's business (WebGPU builds one layout per group from reflection) | `compute.dart:141-226`; `webgpu_compute.dart:122-206` |
| Storage buffers | `createBuffer(BufferDescriptor)` with `BufferUsage` bits (`storage`, `indirect`, `vertex`, `index`, `uniform`, copy, `hostReadable`, `hostWritable`). `standardStorage` = storage, copySource and copyDestination. Read-only versus read-write is a property of the stage's declaration, not of the buffer | `resources.dart:326-436`; `graphics_device.dart:626-662` |
| Storage textures | `TextureUsage.storage`, `DeviceFeature.storageTextures` / `readWriteStorageTextures`, `StorageTextureAccess` (closed enum), per-format `TextureFormatSupport.storage` / `storageReadWrite` | `resources.dart:101-103, 787-800`; `capabilities.dart:262-275, 1069-1075` |
| Push constants | None. `bindUniformBytes` is the nearest equivalent | — |
| Dispatch | `dispatch(x, [y, z])`; `dispatchIndirect(StorageBuffer, {offset})` behind `indirectDispatch`; `dispatchIndirectArguments(x, y, z)` writes the 12 bytes | `compute.dart:199-223`; `resources.dart:911-913` |
| Workgroup size | Declared in the source (`workgroup x, y, z` in a kernel, `local_size_*` in GLSL). The parser caps it at 256×256×64 with 256 invocations, the WebGPU defaults. `DeviceLimits` exposes `maxComputeWorkgroupSize{X,Y,Z}`, `maxComputeInvocationsPerWorkgroup`, `maxComputeWorkgroupStorageSize` and `maxComputeWorkgroupsPerDimension`, which are zero on devices without compute | `kernel_parser.dart:470-473`; `capabilities.dart:879-1005` |
| Synchronisation | Implicit. Passes are ordered by submission (`transfer.dart:7`); every `ComputeEncoder.submit` and every render-pass submit is its own queue submission on WebGPU. Visibility between dispatches inside one pass is promised only by `WorkloadRecorder.dispatch` (`compute_workload.dart:139-141`), not by `ComputeEncoder` | — |
| Atomics, workgroup memory, subgroups, f16 | Kernel language 2 has `atomic` buffers (i32/u32, load, store, exchange, add). The kernel language has no workgroup memory and no barrier; only the engine's own GLSL stages use them. `DeviceFeature.subgroups` and `shaderF16` are listed on WebGPU when granted, and no author-facing language can use them. `shaderInt64` and `asyncCompute` are reserved | `compute_kernel.dart:46-58`; `webgpu_formats.dart:292-293`; `capabilities.dart:659-670` |
| Readback | `readBuffer(StorageBuffer) → Future<ByteData>` (whole buffer, `hostReadable`); `mapBuffer(…, MapMode, range)`; `readBufferSync` only through the `SynchronousBufferReadback` mixin in `testing.dart` | `graphics_device.dart:555-558, 697-714` |
| Compute output read by draws | `StorageBuffer.asVertices` / `asIndices` (the same memory, chosen by usage at creation); `PassEncoder.drawIndirect` / `multiDrawIndirect(StorageBuffer, countBuffer)`; `SharedBuffer` / `SharedTexture` across devices | `compute.dart:62-91`; `command_encoder.dart:489-591`; `sharing.dart:428-511` |
| Timing | `beginComputePass(timestampWrites:)` behind `timestampQuery`; pipeline-statistics queries (`computeShaderInvocations`) behind `pipelineStatisticsQuery`; `onGpuTimings` by label | `graphics_device.dart:547-553`; `compute.dart:202-211` |
| Placement | `ComputePlacement` {device, sidecar, cpu} in a frozen order; `FrameCompute.of(device)` with `place`, `placeHosted` and `placeStorage`; `ComputeSite`; `ComputePlacementException` plus `ComputeRefusalReason`; `DeviceRegistry.addComputeDevice` / `adopt` | `compute_placement.dart`; `device_registry.dart:203-252`; `HAL.md:613-657` |
| Engine-level | `ComputeStep` (a `RenderNode`), `ComputeContext`, `WorkloadStep`, and `ComputeWorkload` / `WorkloadRecorder` / `WorkloadBuffer` / `WorkloadBinding` | `flutter3d_core/…/compute_step.dart`; `compute_workload.dart` |
| Refusal | `UnsupportedCapabilityException(DeviceFeature.compute)` from the device defaults, which every backend without compute overrides with a reason; `ComputePlacementException` (a `CapabilityException`) for a step that has nowhere to run, reported as `PassSkip.unsupported` | `graphics_device.dart:543-558`; `compute_step.dart:1-13` |

## 2. Backend × compute feature

Key: **Y** = implemented. **R** = refused with a typed `UnsupportedCapabilityException`. **F** = binding answers false. **—** = not applicable. **!** = see the finding named in the cell.

| Feature | WebGPU | CPU (software) | wgpu sidecar | Impeller | WebGL2 |
|---|---|---|---|---|---|
| `compute` feature / pass / pipeline | Y | Y | Y | R (`gpu_device.dart:113-135`, flutter/flutter#188480) | R (`webgl_device.dart:69-93`) |
| Kernel-language kernels (`kernel` section) | Y (to WGSL) | Y (to Dart) | Y (to WGSL, through FFI) | R | R |
| Engine GLSL stages (`PrefixSum`, `SplatSort*`) | Y (all four) | `PrefixSum` only (hand-written Dart) | none (refuses non-kernel stages) | — | — |
| Storage buffer, read-only and read-write | Y | Y | Y | R | R (`buffers` only) |
| Range binding, offset alignment | Y, checked (`webgpu_compute.dart:345-352`) | Y, alignment **not** checked (S5) | Y, alignment **not** checked (S5) | — | — |
| Uniform block (float map) | Y, one new GPU buffer per bind (S6) | Y | **F** (kernels declare none) | — | — |
| `bindUniformBytes` | Y | R (`uniformBytesRefusal`) | R (default) | — | — |
| Sampled texture in compute | Y (`textureLoad`, or sampler-paired for GLSL stages) | Y | Y, rgba8 only | — | — |
| Storage texture, write-only | Y (reflected format) | Y (any format the codec stores) | Y, rgba8 only | — | — |
| Storage texture, read-write | Y when the adapter offers it | Y | **!** access not checked (S9) | — | — |
| `dispatchIndirect` | Y (checked) | Y | R (default) | — | — |
| Workgroup memory and barriers (author-facing) | GLSL engine stages only | in the hand-written Dart twin | no | — | — |
| Atomics (kernel 2) | Y | Y | Y | — | — |
| `subgroups`, `shaderF16` | listed when granted, no language to use them (L4) | no | no | — | — |
| `readBuffer` | Y, async (staging buffer made per read, S6) | Y | **synchronous** poll (S7) | Y (host copy, buffers only) | Y (fence + `getBufferSubData`, buffers only) |
| `mapBuffer` | Y | Y | no | — | — |
| Compute → vertex/index (`asVertices`/`asIndices`) | Y | Y | — (draws nothing; crosses through `SharedBuffer` by host copy) | — | — |
| Compute → `drawIndirect` | Y | Y | — | — | — |
| Compute timestamp writes | Y when granted | Y (CPU clock) | R | — | — |
| Pipeline statistics | R (not in WebGPU) | Y | R | — | — |
| Async pipeline creation | Y (`createComputePipelineAsync`) | default (synchronous) | default | — | — |
| Debug groups | Y | no-op | no-op | — | — |
| Async compute queue | reserved everywhere | | | | |
| Real device limits reported | Y (adapter) | defaults | **defaults, not queried** (S5) | zeros | zeros |
| Conformance compute run | `PrefixSum` plus the 4 kernels, in Chrome in CI | the same, on the VM | the 4 kernels plus sharing, skipped where wgpu-native will not start | declines | declines |

The placement policy (`compute_placement.dart:218-355`) is decided only from what the devices report and whether a kernel loads. It is deterministic for a given machine and registry. The order is drawing device, then sidecar, then CPU. For a workload with host code: GPUs, then that host code, then the CPU executor, and a software device is never used for work that has its own host code. A game cannot override it except by choosing which compute devices to register; that is deliberate and frozen in `HAL.md:656-657`.

How closely placements agree:
- The four conformance kernels must match **bit for bit** on CPU, WebGPU and the sidecar (`kernel_checks.dart:1-16`). This holds because every f32 operation is wrapped in an `f3d_exact` bitcast barrier and the RGBA8 store is rounded half to even in the kernel itself (`kernel_wgsl.dart:24-30, 84`; commit `65179578d`).
- Simulations are held only **within a tolerance**: water to 2 cm, particles and debris to 0.1 mm (`flutter3d_physics_native/doc/gpu_water.md:122-180`).
- The workload tests run on a CPU device posing as a GPU (`CpuDevice(standInForGpu: true)`) and on the real sidecar when it starts. No test runs a `WorkloadStep` on real WebGPU in a browser (S10).

## 3. Findings

### BLOCKER

None. All of section 4 is additive.

### SHOULD

**S1. Writes and dispatches reach the CPU executor in a different order than the GPUs.**
- *Where.* The `WorkloadRecorder` contract: "Every write lands before the frame's first dispatch … the CPU executor keeps the same order" (`compute_workload.dart:123-127`).
- *What happens.* `_Recorder.write` calls `device.writeBuffer` immediately (`compute_step.dart:536-541`). On WebGPU that is a `queue.writeBuffer` ahead of the pass submitted at the end, so every write in the frame precedes every dispatch. On the CPU, `writeBuffer` copies at once (`cpu_device.dart:1190-1214`) and `CpuComputeEncoder.dispatch` runs before it returns (`cpu_compute_encoder.dart:128-151`), so a write recorded after a dispatch lands after it.
- *A live case.* `LiquidSurfaceWorkload.recordAfterStep` writes `view` and `air` after the water step's dispatches (`liquid_view.dart:1232-1250`). It is harmless today only because the step kernels do not read those two buffers.
- *Fix.* Queue the writes in `_Recorder` and flush them before the first dispatch (or reject a write after a dispatch in debug builds). If an in-pass write is wanted later, add `WorkloadRecorder.writeBetween` with a default body. Add a conformance check that writes after a dispatch and compares placements.

**S2. Compute devices opened for a frame are never disposed.**
- *Where.* `FrameCompute._of` is a static `Expando` (`compute_placement.dart:428-434`). It opens the sidecar and CPU executors through `DeviceRegistry.computeExecutors` (`device_registry.dart:228-252`), and nothing disposes them when the drawing device is disposed.
- *Impact.* Each drawing device opened through the registry gets its own wgpu-native device (a native adapter, queue and buffers), and that device lives until process exit.
- *Also.* `WorkloadStep._libraries` and `_pipelines` are static `Expando`s (`compute_step.dart:276-282`) whose pipelines are never released.
- *Fix.* Have `FrameCompute` dispose the executors it opened from the drawing device's `dispose` path (a `GraphicsDevice` dispose hook, or the registry's `Registration`). Key the pipeline cache by site and release it in `WorkloadStep.release`.

**S3. A fall back to the CPU is silent.**
- *Where.* `FrameCompute.place` / `placeHosted` (`compute_placement.dart:471-478, 502-509`).
- *What happens.* When a kernel fails on WebGPU (bad WGSL, too many bindings, a limit) and then loads on the CPU executor, the caught error is kept only for the case where nothing takes the work. The frame then runs a GPU-intended kernel in Dart, one invocation at a time, and nothing says so.
- *Fix.* Report every executor passed over: add `PlacedWork.passedOver` (the class says it "can say more in a minor") and send it through the registry's `onFallback` or onto the frame report.

**S4. Material compute and splat sort bypass the placement rule.**
- *Material compute.* `MaterialComputeKernel.load` refuses on any device without compute and tells the author to bake on the CPU (`material_kernel.dart:123-133`). Since rc.1+1 an Impeller frame with a sidecar could run it on the GPU. The material-language reference repeats the refusal (`site/content/reference/material-language.md:209, 242`).
- *Splat sort.* `SplatGpuSort.availableOn` checks only the drawing device (`splat_sort_gpu.dart:78-79`). Its header still names `supportsCompute`, which is gone (`:18-22`).
- *Why it matters.* `HAL.md:613-625` says placement is decided in the HAL "and nowhere else".
- *Fix.* Route material compute through a `ComputeStep` / `FrameCompute.place`, with the bake as the host fallback. Either state that splat sort is on-frame-device only by design or route it as well. Correct both texts.

**S5. Portable limits are not enforced.**
- *Storage offset alignment.* The CPU (`storageRangeOf`) and the sidecar (`wgpu_device.dart:868-892`) accept offsets that are not a multiple of `minStorageBufferOffsetAlignment`. WebGPU rejects them, and no conformance check covers it.
- *Dispatch size.* No encoder checks `maxComputeWorkgroupsPerDimension`. A WebGPU dispatch past it becomes a validation error drained later, while the CPU simply runs it.
- *Storage buffers per stage.* The kernel parser does not cap storage buffers per stage at the portable 8. The largest kernels today are at 7 (`ShallowTransport`, `DebrisSolve`, `SurfaceVertices`). A ninth would load on the CPU, fail on WebGPU or the sidecar, and fall to the CPU silently (S3).
- *Workgroup size.* The parser's 256-invocation cap (`kernel_parser.dart:470`) is above the 128 that Vulkan and GLES 3.1 guarantee, which matters once Impeller has compute.
- *Sidecar limits.* The sidecar reports `DeviceLimits()` defaults rather than the adapter's (`wgpu_device.dart:147-154`).
- *Fix.* Check alignment and dispatch counts in all three encoders. Refuse more than `maxStorageBuffersPerShaderStage` at load, so placement passes over the device for a reason. Query the sidecar's limits through a new C call. Add the checks to `capability_checks`.

**S6. Allocations every frame in WebGPU compute.**
- *Uniforms.* Every `bindUniformBlock` / `bindUniformBytes` creates a GPU buffer and destroys it on submit (`webgpu_compute.dart:500-523`). The render encoder was moved to a scratch ring in 2A (D13), and the compute encoder was missed. Splat sort binds `SortInfo` per dispatch.
- *Readback.* Every `readBuffer` of a non-`MAP_READ` buffer creates a staging buffer (`webgpu_compute.dart:740-750`). Water reads its full state back every frame (`shallow_water_workload.dart:179`).
- *Fix.* Use the uniform scratch ring in `WebGpuComputeEncoder`, and pool staging buffers by size.

**S7. Synchronous readback on the sidecar path every frame.**
- *What happens.* `WgpuComputeDevice.readBuffer` blocks on `wgpuDevicePoll(wait)` (`wgpu_device.dart:11-14, 527-528`; `f3d_wgpu.c:287-296`). `_WorkloadResources.afterFrame` calls it every frame for each drawn buffer copied to the drawing device (`compute_step.dart:497-506`), so a sidecar-placed workload stalls the UI isolate on the GPU each frame.
- *Also.* Each submit waits on an error scope (`f3d_wgpu.c:220-231, 575-592`), and each dispatch creates a bind group with no cache (`f3d_wgpu.c:562`).
- *Fix.* An asynchronous map (a poll without wait from a timer, completing a future), plus a bind group cache keyed as WebGPU's is (`webgpu_compute.dart:46-66`). Until then, document it as the sidecar's cost in `HAL.md`.

**S8. No guide and no example for writing a kernel.**
- *What exists.* The kernel language is documented only in dartdoc (`compute_kernel.dart:1-58`). There is no site reference page, and neither the sample plugin (`flutter3d_plugin_runtime/example`) nor `examples/outside_plugin` has a `ComputeStep` or a `ComputeWorkload`. `API.md:766, 804` lists `addComputeStep`, and `FakeBackend` refuses compute (`testing_fake_backend.dart:110-151`), so a plugin author has no test device except `flutter3d_cpu`.
- *Compared with custom materials.* Writing a kernel is about as easy as writing a material: one source, no backend code, typed refusal, and the CPU twin comes free. Discovering how to do it is much harder.
- *Fix.* A `site/content/reference/kernel-language.md` (grammar, bindings, limits, what is bit-exact and what is not: `sin`, `cos`, `pow`, `sqrt` and division are not; see S11), a `ComputeStep` in the sample plugin run by conformance, and a "test your kernel on `cpuComputeDevice()`" paragraph.

**S9. Sidecar validation is loose and one refusal is untyped.**
- *Storage textures.* `bindStorageTexture` ignores `access` and `mipLevel` (`wgpu_device.dart:910-925`) although the device does not list `readWriteStorageTextures`. The contract says a backend without the feature throws.
- *Buffer usage.* `createBuffer` accepts any usage, including `indirect` and `vertex`, which it cannot honour, without `BufferUsage`'s feature check (`wgpu_device.dart:440-462`).
- *Untyped refusal.* `_drawsNothing` throws a plain `UnsupportedError` (`wgpu_device.dart:187-191`), not `UnsupportedCapabilityException`.
- *Fix.* Call the shared checks the other backends use (`checkBufferUsage`, the access check). For drawing, throw a typed refusal: `refuse(DeviceFeature.…)`, or `DeviceResourceException` naming the call.

**S10. Tests and checks have gaps.**
- *Coverage.*
  - The WebGPU workload path, which is the one most games will hit, has no test of `WorkloadStep` in a browser. Only `PrefixSum` and the four kernels run there.
  - `dispatchIndirect` is checked only for refusal and one dispatch (`capability_checks.dart:549-590`).
  - No conformance check covers atomics (kernel 2), compute writing an index or indirect buffer that a draw then consumes, or compute timestamps.
- *Reachability.* `kernelChecks` is not reachable for a device without the engine's GLSL stages except through `computeChecks`.
- *Test knob.* `standInForGpu` is a test knob on the public `CpuDevice` constructor and on `cpuComputeDevice` (`cpu_device.dart:52-62, 78`; `cpu_backend_registration.dart:63`), so it freezes into the 1.0 API.
- *Fix.* Add a browser `WorkloadStep` test, an atomics kernel check and a compute-to-draw check. Move the knob into `testing.dart` (for example `cpuComputeDeviceStandingInForGpu()`), or mark it `@visibleForTesting`.

**S11. Determinism needs a policy before the HAL text freezes.**
- *Where.* `placeWorkload` always prefers a GPU to a workload's host code (`compute_placement.dart:301-335`). For water, the GPU result is mirrored back into the physics world (`putShallowState`, `shallow_water_workload.dart:179, 205-211`), and bodies feel the GPU water. A game that needs cross-machine bit-exact replay or rollback cannot ask to keep the step on its bit-exact host code. `HAL.md:656-657` freezes "that nothing above this layer chooses among them".
- *Kernel language.* It exposes `sin`, `cos`, `pow`, `sqrt` and `/`, which are a GPU's own to a few ulp, while the module docs say "the same bytes on each" (`compute_kernel.dart:21-25`).
- *Fix.*
  - Reword the frozen sentence to allow a *requirement*: for example `ComputeWorkload.requiresExactHost`, or a `ComputeRequirement` open class with a default body, which the HAL's rule honours. This is a requirement, not a placement, so the rule stays the HAL's.
  - State in the kernel docs which operations are exact.
  - A follow-up for the authors of the water and visual workloads: decide whether a physics-affecting workload should default to the host.

**S12. Workload texture bindings fail in a different way on each backend.**
- *What happens.* `_Recorder.dispatch` binds only `buffer` bindings (`compute_step.dart:552-556`). A workload kernel that declares a `texture` or `image` is dispatched with that binding missing: WebGPU produces a bind-group validation error later, while the CPU and the sidecar throw a `StateError`.
- *Fix.* Refuse such kernels in `WorkloadStep` when they are parsed, with a message, until `WorkloadBuffer` gains a texture form (additive).

**S13. Stale words in compute docs.**
- `compute.dart:4-12` says "0.8.0 carries the whole shape" and names only WebGPU and the software rasteriser, not the sidecar.
- `webgpu_compute.dart:5-9` and `webgpu_compute_stage.dart:76-87` say no stage declares textures, but kernel stages do (`loadedTextures`, `storageTextures`).
- `splat_sort_gpu.dart:18-22` says `supportsCompute`.
- `ComputeEncoder` does not state what visibility it guarantees between dispatches. `WorkloadRecorder` does (`compute_workload.dart:139-141`). Write the rule once in `compute.dart`: storage writes of one dispatch are visible to the next in the same pass, and passes are ordered by submission. A Vulkan or Metal backend from outside needs it.

### LATER (additive in 1.x)

**L1. Kernel language 3: workgroup memory, `workgroupBarrier`, `storageBarrier`, uniform blocks.** All of these sit behind `kernel <N>`, which is versioned and refuses a newer source (`kernel_version.dart`). `KernelBindingKind` is an open class (`compute_kernel.dart:117-146`). The engine's own GLSL stages could then move to the kernel language, which retires `engine_compute_shaders.dart` and the hand-written Dart `PrefixSumShader`, and gives splat sort a CPU and sidecar path.

**L2. More storage-texture formats in kernels.** `KernelBinding.textureFormat` is a getter that returns rgba8 (`compute_kernel.dart:186`). A per-binding format (`image r32f`) is additive, and so is the sidecar's C kinds table.

**L3. `KernelBinding.atomic`.** The public binding drops the parser's `atomic` flag (`kernel_ast.dart:100-130` against `compute_kernel.dart:160-200`). Adding it is additive.

**L4. f16 and subgroups in the kernel language.** The features are already named. They need a language version and a refusal at load where the feature is missing.

**L5. A uniform binding fed from a GPU buffer** (`bindUniformBuffer(stage, name, StorageBuffer)`) with a refusing default, so compute can feed a draw's uniforms without a host round trip. `BufferUsage.uniform` exists already.

**L6. Async compute.** `DeviceFeature.asyncCompute` is reserved. A placement value goes on `ComputePlacement`, which is open, and an optional named `ComputeExecutors(asyncQueue:)`. Ordering would use `GpuFence` from `sharing.dart`.

**L7. Impeller compute when flutter_gpu has it.** Flutter 3.47.0's `flutter_gpu` (`bin/cache/pkg/flutter_gpu/lib/src/*.dart`) has no compute pipeline, compute pass or storage binding. Impeller's own `ComputePass` exists for Metal and Vulkan, not for GLES, so Android GLES devices will keep refusing and fall to the sidecar or CPU, which the placement already handles. The HAL shape follows the upstream proposal (#188474), so this becomes a mapping: `createComputePipeline(ShaderHandle)`, a pass per command buffer, binding by name through reflection.

**L8. Specialisation constants and a workgroup size chosen at pipeline creation**, as fields on `ComputePipelineDescriptor`, which the descriptor already reserves room for (`pipeline_descriptor.dart:83-86`).

**L9. Zero-copy sidecar to drawing device.** `SharedBuffer` / `SharedTexture` copy through host memory today (`wgpu_device.dart:424`; the sidecar does not report `sharedTextures`). The native-handle import planned in 2K is additive through the features.

## 4. Additive later or a break now

| Capability | Additive later? | Why / what the current shape assumes |
|---|---|---|
| Indirect dispatch | already in | `dispatchIndirect` has a refusing default; the sidecar refuses with a type |
| Storage textures (more formats, read-write, 3D) | yes | `bindStorageTexture` takes access and mip level; format comes from `TextureFormatSupport` and reflection. Only the kernel language pins rgba8 (L2) |
| Atomics (32-bit) | already in (kernel 2) | 64-bit: `shaderInt64` is reserved |
| Workgroup memory and barriers | yes | a kernel-language version (L1); the HAL is untouched |
| Several bind groups | yes | binding by name; WebGPU already builds N groups from reflection. Kernel bindings say "group zero" (`compute_kernel.dart:157-158`), which is a kernel-language detail, not HAL |
| Compute → vertex, index or indirect buffer | already in | `asVertices`, `asIndices`, `drawIndirect(StorageBuffer)`, chosen by usage at `createBuffer` |
| Compute → uniform buffer | yes | a new member with a default (L5) |
| Asynchronous readback | already in | `readBuffer` / `mapBuffer` are futures. Only the sidecar's implementation blocks (S7) |
| Partial readback | already in | `mapBuffer(offset, size)` |
| Timestamps on compute | already in | `beginComputePass(timestampWrites:)` |
| Async compute queue | yes | open `ComputePlacement`, and an optional constructor parameter on `ComputeExecutors` (L6) |
| Push constants | yes | a `bindUniformBytes`-like member with a default, or a descriptor field |
| Subgroups, f16 | yes | the features are named; a language version is needed (L4) |
| Pipeline overrides and constants | yes | `ComputePipelineDescriptor` fields (L8) |
| Writes between dispatches in a workload | yes | a new `WorkloadRecorder` member with a body. The fix for S1 makes the current promise true |
| Determinism requirement on a workload | **only if the frozen sentence is reworded before 1.0** | `HAL.md:656-657` freezes "nothing above this layer chooses". A requirement that is not a placement fits if the text says so now (S11) |
| Placements reported to the frame | yes | `PlacedWork` is a class "so it can say more in a minor" (S3) |
| Disposal of compute executors | yes, internal | no public shape changes (S2) |

## 5. What is good

- **Default bodies everywhere they matter.** The earlier finding (audit 11: abstract members of `ComputeEncoder` that sit behind features) is fixed: `bindStorageTexture`, `bindUniformBytes`, `dispatchIndirect`, the statistics queries and the debug groups all have bodies (`compute.dart:180-243`). The device's compute members refuse by default (`graphics_device.dart:543-558`).
- **Open sets.** `ComputePlacement`, `ComputeRefusalReason` and `KernelBindingKind` each have `values` and `byName` and a `_ =>` arm in every switch (`compute_placement.dart:239-245, 198-207`).
- **Typed refusal end to end.** A device without compute throws `UnsupportedCapabilityException` with the reason written out (`gpu_device.dart:116-123`, `webgl_device.dart:73-81`). A step with nowhere to run becomes `ComputePlacementException`, with every executor tried listed, and the frame reports the pass as unsupported instead of throwing (`compute_step.dart:1-13, 144-160`).
- **One source, translated per placement, held bit-exact.** The `f3d_exact` barrier and the investigation behind the Dawn fix (`65179578d`) are careful work, and the conformance kernels cover the fused-multiply-add case explicitly (`kernel_checks.dart:11-16`).
- **The placement rule lives in one place.** That place is the HAL, with a test seam (`computePlacementOf`) that does not let code choose.
- **WebGPU encoder details.** Bind groups cached by storage range (`webgpu_compute.dart:46-66`), checked ranges and indirect arguments, and asynchronous pipeline compilation that turns a browser refusal into a rejected future (`webgpu_device.dart:365-385`).
- **Compute output drawn without a host round trip** on the drawing device: `asVertices` and `asIndices`, plus splat sort writing the draw's index buffer directly (`splat_sort_gpu.dart:11-16`).
