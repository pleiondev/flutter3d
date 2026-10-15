## 1.0.0-rc.1+1

- **Its own dispose is a loss.** The sidecar reported no loss at all; its
  `dispose` reports `DeviceLossReason.destroyed` on `lost` (new) and
  `isLost` follows.
- **What it cannot draw is refused in the HAL's words**: a render pass,
  pipeline or geometry is a `DeviceResourceException`, where it was an
  `UnsupportedError`. Its registration takes the HAL's `DeviceRequest`.

## 1.0.0-rc.1

- **Breaking: `wgpu_native_hook.dart` is no library of this package.** The
  fetch of the pinned wgpu-native is the build hook's own file,
  `hook/wgpu_native.dart`; nothing an application imports changes.
- **The limits say the sidecar draws nothing**: no colour attachment, one
  sample, no vertex buffer, attribute or inter-stage variable, where it
  answered WebGPU's defaults for all of them. A sampler handed to
  `bindTexture` is checked by its features.
- **`backendId` is `wgpu`.** It followed the display name, `the wgpu
  sidecar`; an id is fixed for good.
- **The compute sidecar.** `WgpuSidecar.open` makes a compute-only
  `GraphicsDevice` over wgpu-native through `dart:ffi`: storage buffers,
  RGBA8 textures and storage textures, a bundle's `.f3dmat compute` kernels
  loaded through `flutter3d_shaders`' WGSL, compute passes and readback.
  Everything that draws is refused by name. `registerWgpuSidecar` adds it to
  a `DeviceRegistry` as `ComputePlacement.sidecar`. The four conformance
  kernels give the CPU's bytes on it.
- **The pinned wgpu-native, in one file.** `hook/wgpu_native.dart` is the
  fetch this package's build hook uses: the release, its checksums and the
  unpacking. `flutter3d_physics_native` keeps a copy under its own `hook/`,
  held to the same bytes, and does not depend on this package.
- **Zero copy's first half.** `WgpuSidecar.metalTextureOf` answers the
  `MTLTexture` behind a sidecar texture on Metal. The sidecar does not report
  `DeviceFeature.sharedTextures`, since it cannot import one back, so a
  `SharedTexture` between it and Impeller copies through host memory.
