/// Opening the sidecar natively.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'wgpu_adapter.dart';
import 'wgpu_device.dart';

/// See `WgpuSidecar.open`.
Future<GraphicsDevice> openSidecar({
  WgpuBackend? backend,
  bool fallbackAdapter = false,
}) async =>
    openWgpuComputeDevice(backend: backend, fallbackAdapter: fallbackAdapter);

/// See `WgpuSidecar.metalTextureOf`.
NativeHandle? sidecarMetalTexture(
  GraphicsDevice device,
  TextureHandle texture,
) => device is WgpuComputeDevice ? device.metalTextureOf(texture) : null;

/// See `WgpuSidecar.adapterName`.
String? sidecarAdapterName(GraphicsDevice device) =>
    device is WgpuComputeDevice ? device.adapterName : null;

/// See `WgpuSidecar.adapterInfo`.
WgpuAdapterInfo? sidecarAdapterInfo(GraphicsDevice device) =>
    device is WgpuComputeDevice ? device.adapterInfo : null;
