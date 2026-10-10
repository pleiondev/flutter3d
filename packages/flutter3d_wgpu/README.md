# flutter3d_wgpu

The compute sidecar of flutter3d: a `GraphicsDevice` that computes and draws nothing, over [wgpu-native](https://github.com/gfx-rs/wgpu-native) through `dart:ffi`.

A frame's compute step runs where the frame can run it. The device that draws comes first, when it has compute (WebGPU does; Impeller will when flutter_gpu has compute pipelines). This package is second: a GPU beside the drawing device, on every native target. The CPU is last, through `flutter3d_cpu`. The order is `ComputeExecutors` in `flutter3d_hardware`, and a frame-graph `ComputeStep` in `flutter3d_core` is placed by it.

```dart
final registry = DeviceRegistry<Object>();
registerWgpuSidecar(registry); // ComputePlacement.sidecar
registerCpuBackend(registry); // ComputePlacement.cpu, and the fallback backend
final executors = await registry.computeExecutors(drawingDevice);
await myComputeStep.prepare(executors);
```

## The same kernels, the same bytes

A kernel is written once, in `.f3dmat compute`, and travels in a shader bundle's kernel section. The sidecar loads it as WebGPU does: translated to WGSL by `flutter3d_shaders`, then compiled by wgpu. The four kernels of the conformance suite (a prefix sum, a particle step, a skinning pass and a blur from a texture into a storage texture) give the bytes the CPU gives on it; `test/sidecar_test.dart` runs them against the device.

That holds because the WGSL rounds every f32 sum, difference and product where the source rounds it. Metal's compiler fuses a multiply into the add beside it and reorders sums, and before the rounding the particle step came out one ulp off in eight values of sixteen hundred.

## Getting what it computed to the screen

`SharedBuffer` and `SharedTexture` in `flutter3d_hardware` hand the sidecar's output to the drawing device. Today they copy through host memory: flutter_gpu cannot make a texture over a native handle, so Impeller refuses the import, and a demand for zero copy is a `SharingException` that says which half is missing. On Metal the sidecar can already give its half: `WgpuSidecar.metalTextureOf` returns the `MTLTexture` behind a texture it made.

## Building

The build hook fetches the pinned wgpu-native release for the target, checks its sha256, and links the static library into `f3d_wgpu`, the small C surface in `csrc/`. The fetch is `lib/wgpu_native_hook.dart`, which `flutter3d_physics_native` uses too, so both link the same release. Without a release for the target, or without a network, the hook says so and builds nothing; `WgpuSidecar.open` then refuses with the reason and the frame computes on the CPU. In the browser there is no sidecar: WebGPU computes for itself.
