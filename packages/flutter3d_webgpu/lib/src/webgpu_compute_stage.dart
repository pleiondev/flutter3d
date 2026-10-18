/// A compute stage as the generator writes it and the device reads it — `H6`.
///
/// Plain data and no interop, so the generator on the VM and the device in a
/// browser share one definition, as `webgpu_bundle_section.dart` does for the
/// render stages.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart'
    show StorageTextureAccess, TextureFormat;
import 'package:flutter3d_shaders/kernel.dart'
    show ComputeKernel, KernelBindingKind;

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
  /// A storage texture [name] at `@group(group) @binding(binding)`, a 2D
  /// one unless [dimension] says otherwise.
  const WebGpuStorageTextureBinding({
    required this.name,
    required this.group,
    required this.binding,
    required this.access,
    required this.format,
    this.dimension = WebGpuTextureDimension.twoDimensional,
  });

  /// The name a caller binds the texture by.
  final String name;

  /// The WGSL `@group` the texture is declared in.
  final int group;

  /// The WGSL `@binding` within [group].
  final int binding;

  /// How the stage may touch the texture; a bind must match it.
  final StorageTextureAccess access;

  /// The texel format the layout names; a bound view must have it.
  final TextureFormat format;

  /// The view shape the layout declares, `2d` by default.
  final WebGpuTextureDimension dimension;
}

/// A storage buffer a compute stage declares.
final class WebGpuStorageBinding {
  /// A storage buffer [name] at `@group(group) @binding(binding)`.
  const WebGpuStorageBinding({
    required this.name,
    required this.group,
    required this.binding,
    required this.readOnly,
  });

  /// The GLSL block name, which is what a caller binds by.
  final String name;

  /// The WGSL `@group` the buffer is declared in.
  final int group;

  /// The WGSL `@binding` within [group].
  final int binding;

  /// Declared `readonly`, and so bound as `read-only-storage`.
  final bool readOnly;
}

/// One compute stage: its WGSL and what a pipeline layout needs to know.
final class WebGpuComputeStage {
  /// A stage of [wgsl] with its reflection; the texture lists default to
  /// empty, as on every generated stage.
  const WebGpuComputeStage({
    required this.wgsl,
    required this.storage,
    required this.blocks,
    required this.workgroupSize,
    this.textures = const <WebGpuSampler>[],
    this.storageTextures = const <WebGpuStorageTextureBinding>[],
    this.loadedTextures = const <WebGpuLoadedTexture>[],
  });

  /// The stage's WGSL source, as the translator wrote it.
  final String wgsl;

  /// Every storage buffer the stage declares, read or not.
  final List<WebGpuStorageBinding> storage;

  /// Every uniform block the stage declares, read or not.
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

  /// Textures read texel by texel with `textureLoad`, with no sampler beside
  /// them: what a kernel language `texture` binding is.
  /// `ComputeEncoder.bindTexture` binds one and ignores the sampler it is
  /// handed, which such a texture has no slot for.
  final List<WebGpuLoadedTexture> loadedTextures;

  /// `local_size_x`, `local_size_y`, `local_size_z`.
  final (int, int, int) workgroupSize;
}

/// A texture a compute stage reads with `textureLoad` alone — 1.0, a
/// kernel's `texture` binding.
final class WebGpuLoadedTexture {
  /// A texture [name] at `@group(group) @binding(binding)`.
  const WebGpuLoadedTexture({
    required this.name,
    required this.group,
    required this.binding,
  });

  /// The name the kernel declares the binding under, which a caller binds
  /// by.
  final String name;

  /// The WGSL `@group` the texture is declared in.
  final int group;

  /// The WGSL `@binding` within [group].
  final int binding;
}

/// [kernel] as this backend's compute stage — 1.0: its WGSL as
/// `flutter3d_shaders` translates it, and its bindings in group zero, by the
/// names the kernel declares them under.
WebGpuComputeStage webgpuKernelStage(ComputeKernel kernel) {
  final wgsl = kernel.toWgsl();
  return WebGpuComputeStage(
    wgsl: wgsl.code,
    storage: <WebGpuStorageBinding>[
      for (final b in wgsl.bindings)
        if (b.kind == KernelBindingKind.buffer)
          WebGpuStorageBinding(
            name: b.name,
            group: 0,
            binding: b.index,
            readOnly: !b.writable,
          ),
    ],
    blocks: const <WebGpuBlock>[],
    loadedTextures: <WebGpuLoadedTexture>[
      for (final b in wgsl.bindings)
        if (b.kind == KernelBindingKind.texture)
          WebGpuLoadedTexture(name: b.name, group: 0, binding: b.index),
    ],
    storageTextures: <WebGpuStorageTextureBinding>[
      for (final b in wgsl.bindings)
        if (b.kind == KernelBindingKind.image)
          WebGpuStorageTextureBinding(
            name: b.name,
            group: 0,
            binding: b.index,
            access: StorageTextureAccess.writeOnly,
            format: b.textureFormat,
          ),
    ],
    workgroupSize: (
      wgsl.workgroupSize.x,
      wgsl.workgroupSize.y,
      wgsl.workgroupSize.z,
    ),
  );
}

/// A compute stage's module, beside what its pipeline layout is built from.
final class WebGpuComputeShader {
  /// A shader [name] of [stage], compiled into [module].
  WebGpuComputeShader({
    required this.name,
    required this.stage,
    required this.module,
  });

  /// The kernel's name in its library, which refusals quote.
  final String name;

  /// What its pipeline layout is built from. Replaced, with [module], when a
  /// loaded library's reload brings a kernel's new source — 1.0 — so a
  /// handle already handed out runs it; a pipeline made before keeps what it
  /// was made from.
  WebGpuComputeStage stage;

  /// The `GPUShaderModule`, held as `Object` so this file stays free of
  /// interop and readable on the VM.
  Object module;
}
