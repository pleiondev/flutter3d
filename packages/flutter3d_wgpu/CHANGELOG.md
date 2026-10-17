## 1.0.0-rc.1+2

- **The sidecar decides its backend and says which.** It opened wgpu with
  every backend enabled, so a Windows machine computed on Direct3D 12 or
  on Vulkan depending on its drivers, and nothing recorded which. Now the
  platform's own backends are tried in order, each alone (Direct3D 12 then
  Vulkan on Windows, Metal on Apple platforms, Vulkan then OpenGL
  elsewhere), `WgpuSidecar.open` takes a `backend` and a `fallbackAdapter`
  (WARP on Direct3D 12, what CI computes on), and
  `WgpuSidecar.adapterInfo` (new) answers a `WgpuAdapterInfo` with the
  `WgpuBackend` it runs on. A backend asked for and missing is refused,
  never replaced. The C side is ABI 3 (`f3d_wgpu_open_on`,
  `f3d_wgpu_adapter_backend`, `f3d_wgpu_adapter_is_fallback`).
- **A readback that does not hold the caller.** `readBuffer` starts the
  copy, maps its staging buffer without waiting and polls the device on
  later turns of the event loop, where it waited on the queue in the
  calling turn: a frame's read now holds the UI isolate for its encoding,
  0.09 ms in place of 2.19 ms for 2 MiB on an M-series Mac, and lands in
  0.74 ms in place of 2.20 ms. `readBufferSync` still waits. The C side is
  ABI 2 (`f3d_wgpu_read_begin`, `f3d_wgpu_read_poll`).
- **Staging buffers and bind groups are kept.** A read copies through a
  staging buffer from a pool the device keeps, and a kernel keeps the last
  eight bind groups it made, keyed by resource ids that are never reused,
  and lets go of those of a buffer or texture released; each was made per
  read and per dispatch.
- **The encoder checks ranges and dispatches**, as every backend's does: a
  storage offset off the 256-byte alignment, which wgpu would have refused
  late, is a `RangeError` at the call.

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
