/// A compute stage as the generator writes it and the device reads it — `H6`.
///
/// Plain data and no interop, so the generator on the VM and the device in a
/// browser share one definition, as `webgpu_bundle_section.dart` does for the
/// render stages.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart'
    show StorageTextureAccess, TextureFormat;

import 'webgpu_bundle_section.dart'
    show WebGpuBlock, WebGpuSampler, WebGpuTextureDimension;

/// A storage texture a compute stage declares: where it is bound, how the
/// stage may touch it, and the one format the layout names.
///
/// WebGPU states a storage texture's format and access in the bind group
/// layout, so a bind of a texture in another format, or with another access,
/// is a group the browser refuses; `WebGpuComputeEncoder.bindStorageTexture`
/// refuses it first, by name.
final class WebGpuStorageTextureBinding {
  const WebGpuStorageTextureBinding({
    required this.name,
    required this.group,
    required this.binding,
    required this.access,
    required this.format,
    this.dimension = WebGpuTextureDimension.twoDimensional,
  });

  final String name;
  final int group;
  final int binding;
  final StorageTextureAccess access;
  final TextureFormat format;
  final WebGpuTextureDimension dimension;
}

/// A storage buffer a compute stage declares.
final class WebGpuStorageBinding {
  const WebGpuStorageBinding({
    required this.name,
    required this.group,
    required this.binding,
    required this.readOnly,
  });

  /// The GLSL block name, which is what a caller binds by.
  final String name;
  final int group;
  final int binding;

  /// Declared `readonly`, and so bound as `read-only-storage`.
  final bool readOnly;
}

/// One compute stage: its WGSL and what a pipeline layout needs to know.
final class WebGpuComputeStage {
  const WebGpuComputeStage({
    required this.wgsl,
    required this.storage,
    required this.blocks,
    required this.workgroupSize,
    this.textures = const <WebGpuSampler>[],
    this.storageTextures = const <WebGpuStorageTextureBinding>[],
  });

  final String wgsl;
  final List<WebGpuStorageBinding> storage;
  final List<WebGpuBlock> blocks;

  /// Sampled textures, each a texture-and-sampler pair as a render stage's
  /// are. **Empty for every stage the generator writes today**:
  /// `tool/generate_compute_shaders.dart` reflects storage buffers and
  /// uniform blocks only, so `ComputeEncoder.bindTexture` answers false for
  /// every name on the engine's own stages — the contract's answer for a
  /// binding the stage does not declare. A stage built with these filled in
  /// binds them; the generator learning to write them is the missing half.
  final List<WebGpuSampler> textures;

  /// Storage textures, empty on every generated stage for the reason
  /// [textures] gives.
  final List<WebGpuStorageTextureBinding> storageTextures;

  /// `local_size_x`, `local_size_y`, `local_size_z`.
  final (int, int, int) workgroupSize;
}

/// A compute stage's module, beside what its pipeline layout is built from.
final class WebGpuComputeShader {
  WebGpuComputeShader({
    required this.name,
    required this.stage,
    required this.module,
  });

  final String name;
  final WebGpuComputeStage stage;

  /// The `GPUShaderModule`, held as `Object` so this file stays free of
  /// interop and readable on the VM.
  final Object module;
}
