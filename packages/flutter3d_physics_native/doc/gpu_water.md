# The physics core on GPU compute, placed by the hardware layer

How a system of the physics core runs on a GPU's compute: on the web on the
WebGPU device that draws the frame, natively on the wgpu sidecar beside an
Impeller device, and on the core itself where neither exists. Written for
the shallow water the river runs on; the visual systems — particles, debris,
cloth and the fluid tank — follow the same shape (*The visual systems*,
below). The particle liquid the chemistry bench spills does not yet: its
solver hands its state back synchronously every step.

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

**Nor does the game, nor the engine above the hardware layer.** Where a
workload may run is the hardware layer's alone (`FrameCompute`): the
device a renderer draws on, and the sidecar and CPU device of the
`DeviceRegistry` that opened it, which attaches its compute to every device
it opens. A game adds a water to its elements and nothing else; which
device is there, and whether a wgpu sidecar was registered beside it, is
the application's registry. A structure rule holds every `lib/` outside the
hardware layer and the backends to naming no placement.

`RendererSteps.addWorkload` makes a `WorkloadStep` (`flutter3d_core`,
`compute_step.dart`), which hands the kernels to `FrameCompute.placeHosted`;
that loads them on each candidate and asks `ComputeExecutors.placeWorkload`,
the one place the rule is written:

1. the drawing device's own compute: WebGPU;
2. the compute sidecar: `flutter3d_wgpu` over wgpu-native, where the
   application registered it (`registerWgpuSidecar`);
3. the workload's own host implementation, when it has one;
4. the CPU device, which interprets the kernels in Dart — only for a
   workload with nothing of its own on the host.

Host code comes before the CPU device because it was written for the CPU;
the CPU device runs kernels written for a GPU, one invocation at a time.
For the same reason a workload with host code is never put on a device that
does its work on the CPU (`GraphicsDevice.isSoftware`): the software
rasteriser drawing a test's frames, or a native fallback, leaves the water
on the core. Nothing asks for a placement. Impeller has no compute
(`_noCompute`), so a native Impeller application lands on the sidecar or
the core.

The workload learns the outcome and nothing else: `placed(WorkloadBinding)`
says whether its host code steps it (`isOnHost`), and hands the drawing
device's vertex buffer for each buffer it declared `drawn`. `ShallowWaterWorkload` reacts by
telling the core whether it steps the columns (`setShallowExternal`); it
has no branch on a backend and no knowledge of which exist.
`flutter3d_effects/test/shallow_workload_test.dart` runs the same workload
object under the setups a registry can make — a computing drawing device,
a sidecar (the CPU device standing in for a GPU, and the real wgpu one),
only a CPU device, nothing — and reads where it ran back through the
hardware layer's test seam, `computePlacementOf`.

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

## The visual systems

Particles, debris, cloth and the fluid tank are published as kernels
(`visual_kernels.dart`: `particleKernels`, `debrisKernels`, `clothKernels`,
`fluidKernels`) beside the CPU systems they mirror, and
`flutter3d_effects` hands each to a renderer as a workload
(`ParticleCloudWorkload`, `DebrisWorkload`, `ClothWorkload`,
`FluidWorkload`), which is itself the system: a `NativeParticleCloud`, a
`DebrisSystem`, a `ClothSystem` or a `FluidSystem`. Its host is the core's
own system for the same step, so where no GPU is it is the core, bit for
bit; on a GPU it records what it is told and the frame runs it, and a read
answers what was read back a frame or two before. Before it is placed it
keeps what it is told and plays it where it lands; taken out of the frame it
goes back to the core from what was read back last.

Each kernel is its C loop as one invocation an element. Debris and the
fluid find their neighbours through a grid of lists built with
`atomicExchange` — kernel language 2's atomic buffers — so a cell's
neighbours are summed in the order the invocations inserted them; the
cloth's colours come from the core already coloured (`ClothColoring`) and
are solved a dispatch each, in the core's order, with nothing summed in an
order a GPU picks. The tolerances
`flutter3d_effects/test/visual_workloads_test.dart` holds, on the software
device standing in for a GPU and on the wgpu sidecar, against the core:

- **particles:** two seconds of a spray bouncing on a floor in a wind, to
  a tenth of a millimetre in every float;
- **debris:** three balls of different sizes and masses stacked on a
  floor, every tenth step for two seconds, to a tenth of a millimetre;
  balls poured into a pen, to a tenth of a millimetre for five steps while
  they fall, then the same heap — its mean height within one per cent,
  none through the floor or a wall, none sunk a tenth into another;
- **cloth:** a pendulum, a damped spring in a wind, a rod sliding off a
  ball and points blown along a floor, every tenth step for two seconds,
  to half a millimetre; a sheet hung from two pins, to a tenth of a
  millimetre for half a second, then the same sheet — its stretch within
  half a per cent, its lowest point within a centimetre — with its pins
  carried where they are moved;
- **fluid:** a viscous pair passing, every tenth step for a second, to a
  hundredth of a millimetre; a dam slumping, to a tenth of a millimetre for
  five steps, and the density at rest within a thousandth.

## Public surface

- `flutter3d_hardware` (1.0.0-rc.1+1): `ComputeWorkload`,
  `WorkloadBuffer`, `WorkloadRecorder`, `WorkloadBinding`, `FrameCompute`,
  `ComputeSite`, `DeviceRegistry.adopt`, `ComputeExecutors.placeWorkload`,
  `workloadCandidates` and `aheadOfHost`, `GraphicsDevice.isSoftware`; a
  step's `demand` is gone.
- `flutter3d_core` (1.0.0-rc.1+1): `WorkloadStep`,
  `RendererSteps.addWorkload` and `workloadStep`,
  `FrameResourceIds.computedVertices`; compute steps, hooks and fields are
  placed by the hardware layer and handed no executors.
- `flutter3d_cpu` (1.0.0-rc.1+1): `CpuDevice.isSoftware` and
  `standInForGpu`.
- `flutter3d_webgpu` (1.0.0-rc.1+2): no API; a compute pass keeps its bind
  groups.
- `flutter3d_shaders` (1.0.0-rc.1+1): kernel language 2, its atomic
  buffers.
- `flutter3d_effects` (1.0.0-rc.1+1): `ShallowWaterWorkload`,
  `LiquidView.steppedOn`, `ParticleCloudWorkload`, `DebrisWorkload`,
  `ClothWorkload`, `FluidWorkload`.
- `flutter3d_physics_native` (1.0.0-rc.1, its first upload): the visual
  systems' kernels and buffer layouts, `ClothColoring`, with `NativeGpu`
  and its passes gone; `shallowWaterKernels`, `nativeLipFloats`, `NativeShallowExternal`, the
  `NativeWorld` calls a workload makes (`setShallowExternal`,
  `drainShallowExternal`, `readShallowState`, `putShallowState`,
  `throwShallowLips`) and `NativeShallowLiquid.faces`, `stateLength` and
  `blockLength`; in C, `f3d_shallow_set_external`,
  `f3d_shallow_take_external`, `f3d_shallow_read_state`,
  `f3d_shallow_put_state` and `f3d_shallow_throw_lips` (ABI 42).
