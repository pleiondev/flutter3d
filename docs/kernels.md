# Writing a compute kernel

A kernel is a small program that runs once per invocation over a grid, reads
and writes storage buffers and images, and is written once in the **kernel
language**. You hand it to the engine as source; the hardware layer decides
where it runs (the drawing device's compute, the wgpu sidecar beside it, or the
CPU with the kernel translated to Dart) and translates it there. You never
write WGSL or Dart for it, and you never say which device it runs on.

This page is the guide. The reference for each word is the dartdoc of
`ComputeKernel` in `package:flutter3d_shaders/kernel.dart`.

## A first kernel

```text
kernel 1
compute Scale {
  workgroup 64;
  buffer values: f32[] read_write;
  buffer factor: f32[] read;
  kernel {
    let i = id.x;
    if i >= len(values) { return; }
    values[i] = values[i] * factor[0];
  }
}
```

- `kernel 1` is the language version. Leave it out and the source is read as
  the current version; a source newer than the build reading it is refused
  with both numbers.
- `workgroup x, y, z;` is how many invocations a workgroup runs. A dispatch of
  `n` workgroups along x runs `64 × n` invocations here, so every kernel
  checks its index against the data (`if i >= len(values) { return; }`).
- Bindings come next, in order: `buffer name: f32[] | i32[] | u32[]` (`read`
  by default, or `read_write`), `texture name: rgba8` (read with
  `load(t, x, y)`), `image name: rgba8` (written with `store(i, x, y, v)`).
  Kernel language 2 adds `atomic` buffers of `i32` or `u32`.
- The body has `let`, `var`, assignment and `+=` and its kin, `if`/`else`,
  `for i in a .. b`, `break`, `continue` and `return`; the types `f32`, `i32`,
  `u32`, `bool` and `vec2` to `vec4`; WGSL's operators; and `len`, `width`,
  `height`, the conversions, `min`, `max`, `clamp`, `abs`, `floor`, `ceil`,
  `round`, `trunc`, `select`, `sqrt`, `sin`, `cos`, `pow`.

There is no workgroup memory and no barrier yet: invocations are independent,
and each element of a plain buffer is written by one invocation.

## The portable profile

With nothing declared, a kernel must fit what every device that computes
offers, which is below WebGPU's defaults:

| Limit | Portable value |
|---|---|
| Invocations in one workgroup (`x × y × z`) | 128 |
| Storage buffers one kernel binds | 8 |

A kernel past the profile is refused on every device, with the reason, because
it would run on some machines and not on others. If you need more, declare
`ComputeRequirement.beyondPortableProfile` on the step or the workload; the
kernel is then held to each device's own `DeviceLimits`, and a device whose
limits fall short is passed over by name.

Every encoder also checks two things at the call, the same on every backend: a
storage binding starts at a multiple of `minStorageBufferOffsetAlignment`, and
a dispatch asks for at most `maxComputeWorkgroupsPerDimension` workgroups
along each axis. Both are a `RangeError` on the CPU exactly where WebGPU would
refuse them later in the browser.

## What is exact, and what is within a tolerance

Every placement computes these to the same bits: the integers, the f32 `+`,
`-` and `*`, the comparisons, `min`, `max`, `clamp`, `abs`, `floor`, `ceil`,
`round`, `trunc`, `select` and the conversions. The WGSL translation rounds
each f32 operation where it stands, so no compiler fuses a multiply-add or
reorders a sum, and the Dart translation rounds to f32 after each one.

Five operations are a GPU's own to within a tolerance. Each tolerance is
declared in `kernelTolerances` (`package:flutter3d_hardware`), WGSL's own
accuracy rounded up, and the conformance suite holds every device to it
against the Dart translation of the same kernel:

| Operation | Tolerance | Over |
|---|---|---|
| `/` | 3 ulp | a divisor of magnitude 2^-126 to 2^126 |
| `sqrt` | 5 ulp | every non-negative input |
| `sin` | 1/2048 absolute | inputs from -π to π |
| `cos` | 1/2048 absolute | inputs from -π to π |
| `pow` | 16 ulp | a positive base, with \|exponent × log2(base)\| at most 6 |

A kernel that keeps to the exact operations gives the same bytes on the
device, the sidecar and the CPU. One that divides or calls `sqrt`, `sin`,
`cos` or `pow` gives results within these tolerances of each other.

## Requirements, not placements

Where a kernel runs is the hardware layer's to say. What a step or a workload
may say is what it **requires**, as `ComputeRequirement`s:

- `ComputeRequirement.bitExact`: the same bytes on every machine, for a game
  that replays a match, rolls a frame back or compares one peer's world with
  another's. Work that keeps to the exact operations runs anywhere. Work that
  uses one of the five above is placed only where they are computed the one
  way every machine computes them: the work's own host code, or a device that
  runs the kernels translated to Dart. A GPU is passed over, with that reason.
- `ComputeRequirement.beyondPortableProfile`: see the profile above.

```dart
final class Rollback extends ComputeWorkload {
  @override
  Set<ComputeRequirement> get requirements =>
      const <ComputeRequirement>{ComputeRequirement.bitExact};
  // ...
}
```

## When a kernel fails on a device

A kernel that fails to load on a GPU (bad WGSL from a translator, a limit the
adapter did not report) is passed over, and the work runs on the next device
the rule offers. That fallback is never silent: it is a `ComputeFallback` on
`FrameCompute.fallbacks`, an instant event on the timeline (`compute
fallback`) and a log line (`flutter3d.compute`), each with the reason; the
`PlacedWork` a placement answers lists every device passed over.

In a test, a debug build and a conformance run, the fallback throws a
`ComputeFallbackError` instead, so the bug is seen where it happens.
`FrameCompute.of(device).strict = false` turns that off for a test that means
to fall back. A refusal the machine decides (`CapabilityException`) falls back
quietly either way.

## Running a kernel: a step or a workload

A **`ComputeStep`** is a pass of the frame graph that computes. It names its
kernels and records its work on the site the layer chose:

```dart
final class Glow extends ComputeStep {
  @override
  String get name => 'glow';

  @override
  List<ResourceId> get writes => const <ResourceId>[ResourceId('glow')];

  @override
  late final List<ComputeKernel> kernels = ComputeKernel.parseAll(source);

  @override
  void record(ComputeContext context) {
    final stage = context.stage('Glow');
    context.beginPass()
      ..bindPipeline(pipelineFor(context.device, stage))
      ..bindStorageBuffer(stage, 'glow', glowOn(context.device))
      ..dispatch(groups)
      ..submit();
  }
}
```

Add it with `RendererSteps.addComputeStep`. A step on a device beside the
frame's (`context.isOnFrameDevice` false) hands its results to the drawing
device through `SharedBuffer` or `SharedTexture`. `examples/outside_plugin`
has a complete one, `HeatGlow`.

A **`ComputeWorkload`** is a simulation's step handed over as kernels and
buffers. The engine allocates the buffers where the workload lands, records
its frame through a `WorkloadRecorder`, and copies what it draws across. A
workload with an implementation of its own on the host (`hasHost`) runs that
where no GPU takes it. The recorder has **queue semantics on every executor**:
the frame's writes land before its first dispatch, whatever order they were
recorded in, as on a GPU queue.

## Testing a kernel

- **The numbers**: run it on `cpuComputeDevice()` from `flutter3d_cpu`. It is
  the Dart translation every other placement is held to, and it runs on the
  VM with no GPU.
- **A workload placed as on a GPU**: `cpuComputeDeviceStandingInForGpu()` from
  `package:flutter3d_cpu/testing.dart` makes the CPU device answer
  `isSoftware` false, so a workload with host code of its own is placed on it
  as on a GPU, and you can check its kernels against its host code.
- **What a step encodes**: `FakeBackend(compute: true)` from
  `package:flutter3d_hardware/testing.dart` records every bind and dispatch in
  `computePasses`, after the same range and dispatch checks a real encoder
  makes.
- **The tolerances and the bytes**: the conformance suite's `computeChecks`
  run the four exact kernels and the five tolerance checks on any device you
  hand them.
