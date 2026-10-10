/// The sidecar in the browser: there is none, because WebGPU computes for
/// itself and `dart:ffi` is not there to reach wgpu-native.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

/// See `WgpuSidecar.open`: refused, saying why.
Future<GraphicsDevice> openSidecar() async =>
    throw const DeviceUnavailableException(
      'there is no wgpu sidecar in the browser: WebGPU computes on the '
      'device itself, and a frame without it places its compute on the CPU',
      backend: 'the wgpu sidecar',
    );

/// See `WgpuSidecar.metalTextureOf`.
NativeHandle? sidecarMetalTexture(
  GraphicsDevice device,
  TextureHandle texture,
) => null;

/// See `WgpuSidecar.adapterName`.
String? sidecarAdapterName(GraphicsDevice device) => null;
