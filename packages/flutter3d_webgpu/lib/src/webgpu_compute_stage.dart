/// A compute stage as the generator writes it and the device reads it — `H6`.
///
/// Plain data and no interop, so the generator on the VM and the device in a
/// browser share one definition, as `webgpu_bundle_section.dart` does for the
/// render stages.
library;

import 'webgpu_bundle_section.dart' show WebGpuBlock;

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
  });

  final String wgsl;
  final List<WebGpuStorageBinding> storage;
  final List<WebGpuBlock> blocks;

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
