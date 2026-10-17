/// The compute sidecar: a compute-only `GraphicsDevice` over wgpu-native,
/// reached through `dart:ffi` — the [ComputePlacement.sidecar] a frame places
/// its compute steps on when the device that draws it has no compute
/// (Impeller until flutter_gpu has it, WebGL2).
///
/// **The same kernels, the same bytes.** The sidecar loads a bundle's kernel
/// section as WebGPU does, through `flutter3d_shaders`' WGSL, and the
/// conformance kernels give the CPU's bytes on it. What it computes reaches
/// the drawing device through `SharedBuffer` and `SharedTexture`: by a copy
/// through host memory today, since flutter_gpu cannot import a native
/// texture; [WgpuSidecar.metalTextureOf] is the sidecar's half of the copy
/// that will not be needed.
///
/// **Native only.** wgpu-native is linked in by this package's build hook,
/// the one pinned release in `tool/hook/wgpu_native.dart`. In the browser,
/// and in a build where wgpu-native could not be fetched,
/// [WgpuSidecar.open] refuses with the reason, and the frame places its
/// compute on the CPU.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Registration;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'src/sidecar_native.dart'
    if (dart.library.js_interop) 'src/sidecar_web.dart';
import 'src/wgpu_adapter.dart';

export 'src/wgpu_adapter.dart';

/// Opening the sidecar, and what only it can answer.
abstract final class WgpuSidecar {
  /// The sidecar on the best adapter of [backend]: a device with
  /// `DeviceFeature.compute` that draws nothing.
  ///
  /// **The backend is the sidecar's decision, never wgpu's guess.** Left
  /// null it is the platform's own, tried in order and each alone:
  /// Direct3D 12 then Vulkan on Windows, Metal on Apple platforms, Vulkan
  /// then OpenGL elsewhere; [adapterInfo] says which one answered.
  /// [fallbackAdapter] asks for the software adapter instead, WARP on
  /// Direct3D 12, which is how CI computes on a runner with no GPU.
  ///
  /// Throws [DeviceUnavailableException] saying why where there is none:
  /// the browser, a build without wgpu-native, no adapter on what was
  /// asked. Throws an [ArgumentError] for [WgpuBackend.other].
  static Future<GraphicsDevice> open({
    WgpuBackend? backend,
    bool fallbackAdapter = false,
  }) => openSidecar(backend: backend, fallbackAdapter: fallbackAdapter);

  /// The `MTLTexture` behind [texture], a texture the sidecar [device] made,
  /// as a [NativeHandle] another Metal device could import; null off Metal
  /// and for any other device.
  ///
  /// Not `GraphicsDevice.exportTexture`: the sidecar cannot import one back,
  /// so it does not report `DeviceFeature.sharedTextures`, and a
  /// `SharedTexture` between it and Impeller copies.
  static NativeHandle? metalTextureOf(
    GraphicsDevice device,
    TextureHandle texture,
  ) => sidecarMetalTexture(device, texture);

  /// The adapter wgpu-native chose for [device], or null for a device that
  /// is not the sidecar.
  static String? adapterName(GraphicsDevice device) =>
      sidecarAdapterName(device);

  /// The adapter the sidecar [device] opened, with the backend it runs on
  /// and whether it is a software one; null for a device that is not the
  /// sidecar.
  static WgpuAdapterInfo? adapterInfo(GraphicsDevice device) =>
      sidecarAdapterInfo(device);
}

/// Adds the sidecar to [registry] as [ComputePlacement.sidecar]: a frame
/// drawn on a device without compute places its compute steps there before
/// the CPU. The registration takes it out again.
Registration registerWgpuSidecar(DeviceRegistry registry) =>
    registry.addComputeDevice(
      ComputePlacement.sidecar,
      'the wgpu sidecar',
      (DeviceRequest _) => WgpuSidecar.open(),
    );
