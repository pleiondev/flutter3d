# Fluids on GPU compute, placed by the engine

How a fluid of the physics core runs on a GPU's compute: on the web on the
WebGPU device that draws the frame, natively on the wgpu sidecar beside an
Impeller device, and on the core itself where neither exists. Written for
the shallow water the river runs on, and the particle liquid the chemistry
bench spills, which follows the same shape.

## Who decides where

The physics never does. A fluid describes its step once, as a
`ComputeWorkload` (`flutter3d_hardware`, `compute_workload.dart`):

- its kernels, in the kernel language (`flutter3d_shaders`) — one source,
  translated to WGSL for WebGPU and the sidecar, and to Dart for the CPU
  executor;
- its buffers, by the names its kernels bind them under;
- what one frame records with them (`record`), in terms of those names:
  writes, dispatches, reads back;
- whether it has an implementation of its own on the host (`hasHost`) —
  for the core's fluids, the C step they always had.

The engine places it. `RendererSteps.addWorkload` makes a `WorkloadStep`
(`flutter3d_core`, `compute_step.dart`), loads the kernels on each candidate
and asks `ComputeExecutors.placeWorkload`, which is the one place the rule
is written:

1. the drawing device's own compute (`ComputePlacement.device`): WebGPU;
2. the compute sidecar (`ComputePlacement.sidecar`): `flutter3d_wgpu` over
   wgpu-native, where the application registered it (`registerWgpuSidecar`);
3. the workload's own host implementation, when it has one;
4. the CPU executor (`ComputePlacement.cpu`), which interprets the kernels
   in Dart — only for a workload with nothing of its own on the host.

Host code comes before the CPU executor because it was written for the
CPU; the CPU executor runs kernels written for a GPU, one invocation at a
time. A demanded placement is met or refused, never moved, as for any
compute step. Impeller has no compute (`_noCompute`), so a native Impeller
application lands on the sidecar or the core.

The workload learns the outcome and nothing else: `placed(WorkloadBinding)`
says the placement, or `isOnHost`, and hands the drawing device's vertex
buffer for each buffer it declared `drawn`. `ShallowWaterWorkload` reacts by
telling the core whether it steps the columns (`setShallowExternal`); it
has no branch on a backend and no knowledge of which exist.
`flutter3d_effects/test/shallow_workload_test.dart` runs the same workload
object under four setups — a computing drawing device, a sidecar, only a
CPU executor, nothing — and reads where it ran back from what it was told.

**The core names no device.** It publishes its step's kernels
(`shallowWaterKernels`) and the calls that hand a water's columns over and
take them back; the workload that says the same in the engine's terms,
`ShallowWaterWorkload`, lives in `flutter3d_effects`, beside the view that
draws from its buffers. The simulation stack imports nothing that draws, so
a server replaying a run builds without the graphics layer.

## Where the buffers live

On the executor it was placed on, made by the engine
(`_WorkloadResources`): storage buffers, zeroed. A buffer declared `drawn`
is made with `BufferUsage.vertex` when the executor is the drawing device,
so the draw binds the very buffer the kernels wrote; from a sidecar or the
CPU executor the engine copies it to a vertex buffer on the drawing device
through the host after each frame (`SharedBuffer`'s host-copy path), and
the drawing trails the step by that copy. A buffer declared `readable` can
be read back (`WorkloadRecorder.readBack`), one read in flight at a time.

For the shallow water: `state` (depths, then x faces' velocities, then z
faces', the core's own layout), `cells` (ground, what bodies fill,
roughness, walls), the scratch the substep needs (`fa`, `fb`, `eddies`,
`share`, `flux`, `came`), `lip` (what went over a lip, four reals a face),
`changes`, and `params`. No kernel binds more than seven: WebGPU's default
is eight storage buffers a stage.

## What crosses, and when

The GPU owns the columns; the core keeps everything round them — the
bodies standing in the water, the springs and outlets, the spray off the
lips flying and landing, what the slope pushes the bodies with. Each frame:

1. the core's step (`step_round` in `f3d_shallow.c`) works on its mirror of
   the water and records what it did to it as changes
   (`external_begin`/`external_end` round the step, and round a pour);
2. the workload takes them (`f3d_shallow_take_external`), writes them and
   adds them on the GPU (`ShallowApply`), writes what bodies fill, and
   runs the step's substeps — as many as the core would cut the step into,
   counted from its mirror;
3. two reads come back on a later turn: the state, which the core mirrors
   (`f3d_shallow_put_state`), and the lips, which it throws as sheets
   (`f3d_shallow_throw_lips`) exactly as it throws its own.

So the core's view trails the GPU's by the read, a frame or two; and no
water is made or lost by the trailing, because everything crosses as a
change, and what the lips hold is cleared only after it was read. A pour,
a fill, a dig — anything set outright — sends the whole state again.

## Drawing without readback

The river's surface is built where the water is stepped: the view adds its
kernels to the same workload (`ShallowWaterWorkload.recordAfterStep`), and
one vertex a cell — height, normal, depth and edge, flow, froth — is
written into a buffer declared drawn, which the surface mesh draws from. On
the host the view builds the same vertices on the CPU as before, and that
path is unchanged.

The particle liquid draws its particles instanced from its position buffer
the same way.

## Determinism, and the tolerance

The CPU step is untouched: on the host, a water is the core's step bit for
bit (the host and no-compute cases of `shallow_workload_test.dart` compare
exactly), and the core's replay digests keep holding.

The GPU step is the same scheme pass for pass (`shallow_water_kernels.dart`
names each pass of `substep`), but not the same bits:

- a quotient, a square root and `pow` are a GPU's own to a few ulp, and the
  cube root is `pow(x, 1/3)` where the core has its own Newton iteration;
- a column's inflows and outflows are summed round it in face order rather
  than in the grid's;
- an open edge reads the face inside it as it stood before the slope;
- the wind is the one at the water's origin, even where a wind grid varies
  across it; the slope's push on the bodies is taken once a step from the
  mirror, where the core takes it each substep;
- what crosses an edge is not counted in the water's `lost`, and the
  water does not rest while stepped elsewhere;
- the core's view, and so what bodies feel and where spray lands, is a
  frame or two late.

Every f32 sum and product goes through the kernel language's
`f3d_exact`, so a GPU compiler fuses and reorders nothing the source did
not; what is left is the list above. The tolerance the conformance test
holds — the CPU executor's kernels against the core, over a second of a
falls off a sill with a stone dropped into the pool below — is two
centimetres in any column and one per cent of the water held; measured,
it is under a millimetre and a few parts in a hundred million.

The particle liquid's GPU passes (`csrc/gpu/f3d_gpu_fluid.c`) already
documented theirs: neighbours summed in the order a grid built with atomics
lists them, the CPU's to the GPU's rounding.

## Public surface

Additive only.

- `flutter3d_hardware` (1.0.0-rc.1+1): `ComputeWorkload`,
  `WorkloadBuffer`, `WorkloadRecorder`, `WorkloadBinding`,
  `ComputeExecutors.placeWorkload` and `ComputeExecutors.aheadOfHost`.
- `flutter3d_core`: `WorkloadStep`, `RendererSteps.addWorkload`,
  `FrameResourceIds.computedVertices`.
- `flutter3d_effects`: `ShallowWaterWorkload`.
- `flutter3d_physics_native` (not yet published; lands after its first
  publish as a +1): `shallowWaterKernels`, `nativeLipFloats`,
  `NativeShallowExternal`, the `NativeWorld` calls a workload makes
  (`setShallowExternal`, `drainShallowExternal`, `readShallowState`,
  `putShallowState`, `throwShallowLips`) and `NativeShallowLiquid.faces`,
  `stateLength` and `blockLength`; in C, `f3d_shallow_set_external`,
  `f3d_shallow_take_external`, `f3d_shallow_read_state`,
  `f3d_shallow_put_state` and `f3d_shallow_throw_lips` (ABI 42).
