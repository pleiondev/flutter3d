import 'package:flutter3d_shaders/translate.dart'
    show
        PackedStage,
        PreparedAttribute,
        PreparedBlock,
        PreparedMember,
        PreparedSampler,
        PreparedStage;

import '../engine_shaders.dart';
import 'webgpu_bundle_section.dart';

/// The stage a material loaded while the game runs is spliced into on this
/// backend: the engine's compiled `Unlit` fragment stage, with its WGSL and
/// its reflection, in the shape `flutter3d_plugin_runtime`'s `RuntimeShaders`
/// takes as `webGpuHost`.
///
/// ```dart
/// final shaders = RuntimeShaders(
///   backend: RuntimeBackends.webgpu,
///   loadShaders: device.loadShaders,
///   addMaterials: renderer.renderSteps.addMaterials,
///   webGpuHost: webGpuMaterialHost(),
/// );
/// ```
///
/// **Why a host, and not a compiler.** The engine's WGSL is made in the build,
/// by glslang and naga, and neither ships with a game. A material without a
/// `light` block is `unlit.frag` with a different `main` — the same header
/// with the same two switches — so the stage the build already compiled is
/// the material's stage once its `main` is rewritten from the material's
/// tree, and everything else in it stays what naga made. `RuntimeShaders`
/// does the rewriting and says what it cannot rewrite.
///
/// [stages] is the table the device was opened over, [webGpuEngineShaders] when
/// nothing else was.
PackedStage webGpuMaterialHost({WebGpuSectionStages? stages}) {
  final unlit = (stages ?? webGpuEngineShaders).fragment['Unlit'];
  if (unlit == null) {
    throw StateError(
      'the WebGPU stages have no Unlit fragment stage to host a material',
    );
  }
  for (final sampler in unlit.samplers) {
    if (sampler.comparison) {
      throw StateError(
        'the Unlit stage samples "${sampler.name}" by comparison, which a '
        'material\'s reflection cannot carry',
      );
    }
  }
  return (
    wgsl: unlit.wgsl,
    prepared: PreparedStage(
      // Nothing reads it: the WGSL is already compiled.
      glsl: '',
      attributes: <PreparedAttribute>[
        for (final attribute in unlit.attributes)
          (
            name: attribute.name,
            location: attribute.location,
            format: attribute.format.name,
          ),
      ],
      blocks: <PreparedBlock>[
        for (final block in unlit.blocks)
          (
            name: block.name,
            group: block.group,
            binding: block.binding,
            sizeInBytes: block.sizeInBytes,
            members: <PreparedMember>[
              for (final member in block.members)
                (
                  name: member.name,
                  offsetInBytes: member.offsetInBytes,
                  sizeInBytes: member.sizeInBytes,
                ),
            ],
          ),
      ],
      samplers: <PreparedSampler>[
        for (final sampler in unlit.samplers)
          (
            name: sampler.name,
            group: sampler.group,
            textureBinding: sampler.textureBinding,
            samplerBinding: sampler.samplerBinding,
            dimension: sampler.dimension.name,
          ),
      ],
    ),
  );
}

/// Where the engine's full-screen stages read `v_uv` on this backend — what
/// `flutter3d_plugin_runtime`'s `RuntimeShaders` takes as
/// `webGpuFullscreenUvLocation`, so a full-screen stage written in the
/// material language while the game runs (version 2) meets the shared
/// `FullscreenVertex` at the location the engine's own post stages do.
///
/// Read off the engine's compiled `SceneColourCopy` stage in [stages],
/// [webGpuEngineShaders] when nothing else was given.
int webGpuFullscreenUvLocation({WebGpuSectionStages? stages}) {
  final copy = (stages ?? webGpuEngineShaders).fragment['SceneColourCopy'];
  final location = copy == null
      ? null
      : RegExp(r'@location\((\d+)\) v_uv\b').firstMatch(copy.wgsl)?.group(1);
  if (location == null) {
    throw StateError(
      'the WebGPU stages have no full-screen stage reading v_uv to take its '
      'location from',
    );
  }
  return int.parse(location);
}
