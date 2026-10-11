/// The engine's stages a WebGPU device opens over when it is handed none:
/// the `webgpu` section of the project's own bundle, which `flutter3d_build`'s
/// hook writes with the stages the project needs, and the table this package
/// was compiled with where there is no such section.
///
/// **No `package:web` here**, so the choice is tested on the VM: the device
/// reads the asset and hands the bytes over.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart'
    show ShaderBundle, ShaderBundleException;
import 'package:flutter3d_shaders/flutter3d_shaders.dart'
    show EngineBundleStamp;

import 'webgpu_bundle_section.dart';
import 'webgpu_loaded_shaders.dart';

/// The `webgpu` section of [bytes], the project's engine bundle as read from
/// [EngineBundleStamp.projectAsset]; null when there is no bundle, or when it
/// carries no section of this backend's (one written for a native target, or
/// on a machine without glslang and naga), and the device takes the table it
/// was compiled with.
///
/// **A bundle that is there and cannot be read is refused**, with a
/// [ShaderBundleException] naming the asset, rather than passed over for the
/// compiled table; one whose section is a newer document than this reader
/// knows is refused as stale, as a loaded bundle is.
WebGpuSectionStages? projectWebGpuStages(ByteData? bytes) {
  if (bytes == null) return null;
  const asset = EngineBundleStamp.projectAsset;
  try {
    final bundle = ShaderBundle.decode(bytes);
    if (bundle.section(ShaderBundle.webgpuSection) == null) return null;
    return WebGpuLoadedShaderLibrary.stagesOf(bundle);
  } on ShaderBundleException catch (error) {
    throw ShaderBundleException(
      name: error.name,
      reason: error.reason,
      stale: error.stale,
      asset: asset,
      advice: 'Build the project again so its hook writes the bundle anew',
    );
  }
}
