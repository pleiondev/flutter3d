## 1.0.0-rc.1

- **`backendId` is `wgpu`.** It followed the display name, `the wgpu
  sidecar`; an id is fixed for good.
- **The compute sidecar.** `WgpuSidecar.open` makes a compute-only
  `GraphicsDevice` over wgpu-native through `dart:ffi`: storage buffers,
  RGBA8 textures and storage textures, a bundle's `.f3dmat compute` kernels
  loaded through `flutter3d_shaders`' WGSL, compute passes and readback.
  Everything that draws is refused by name. `registerWgpuSidecar` adds it to
  a `DeviceRegistry` as `ComputePlacement.sidecar`. The four conformance
  kernels give the CPU's bytes on it.
- **The pinned wgpu-native, in one place.** `wgpu_native_hook.dart` is the
  fetch both this package's build hook and `flutter3d_physics_native`'s
  use: the release, its checksums and the unpacking.
- **Zero copy's first half.** `WgpuSidecar.metalTextureOf` answers the
  `MTLTexture` behind a sidecar texture on Metal. The sidecar does not report
  `DeviceFeature.sharedTextures`, since it cannot import one back, so a
  `SharedTexture` between it and Impeller copies through host memory.
