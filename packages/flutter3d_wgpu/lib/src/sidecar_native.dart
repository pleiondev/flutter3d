/// Opening the sidecar natively.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'wgpu_device.dart';

/// See `WgpuSidecar.open`.
Future<GraphicsDevice> openSidecar() async => openWgpuComputeDevice();

/// See `WgpuSidecar.metalTextureOf`.
NativeHandle? sidecarMetalTexture(
  GraphicsDevice device,
  TextureHandle texture,
) => device is WgpuComputeDevice ? device.metalTextureOf(texture) : null;

/// See `WgpuSidecar.adapterName`.
String? sidecarAdapterName(GraphicsDevice device) =>
    device is WgpuComputeDevice ? device.adapterName : null;
