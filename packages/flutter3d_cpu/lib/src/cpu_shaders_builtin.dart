/// The engine's shaders, written in Dart.
///
/// All twenty-four of them: both mesh stages, six lighting models, the two
/// shadow passes and the atlas tile reset, three bloom stages, the composite,
/// reflections, debug lines, particles and the MRT probe. The demo application
/// runs end to end on this backend, and eleven of its twelve golden scenes
/// land between 0.15% and 0.46% of the pictures Impeller recorded — most of
/// which is the multisampling this backend says it has none of.
///
/// `kUnimplementedCpuVertexShaders` and its fragment twin are empty and stay
/// in place: they are what a stage is added to when the engine grows one, and
/// a test fails until it is either written or listed.
///
/// **Transcribed from the GLSL, not invented.** The first version of this file
/// was written from memory of what a renderer's uniforms are usually called,
/// and it drew two black spheres on a light background: `light_count` does not
/// exist (the count is `frame_params.y`), and `material` is metallic and
/// roughness rather than the colour. Both names were plausible and neither was
/// real, and nothing anywhere reported a missing member — a Dart shader reads
/// zeros for what it asks for wrongly, exactly as a compiled one does. The
/// sources under `packages/flutter3d_shaders/shaders` are the contract; where
/// this file departs from them it says so.
///
/// **Split by pass rather than kept as one file.** Every class below used to
/// live here; they now live in `cpu_shaders_*.dart` beside this one, grouped
/// the way the GLSL sources they transcribe are grouped — `surface.glsl`,
/// `shadow.glsl`, `color.glsl`, and one file per pass or family of passes. This
/// file is what is left once the shaders move out: the registry that answers a
/// name with a stage, and the two lists of names nothing here implements yet.
/// All of it is re-exported from here, so nothing outside this directory has
/// to learn the new file names.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_bloom.dart';
import 'cpu_shaders_debug.dart';
import 'cpu_shaders_lit.dart';
import 'cpu_shaders_mesh_vertex.dart';
import 'cpu_shaders_particles.dart';
import 'cpu_shaders_post.dart';
import 'cpu_shaders_reflections.dart';
import 'cpu_shaders_shadow_passes.dart';
import 'cpu_shaders_sky.dart';
import 'cpu_shaders_ssao.dart';

export 'cpu_shaders_bloom.dart';
export 'cpu_shaders_color.dart';
export 'cpu_shaders_debug.dart';
export 'cpu_shaders_layout.dart';
export 'cpu_shaders_lighting.dart';
export 'cpu_shaders_lit.dart';
export 'cpu_shaders_mesh_vertex.dart';
export 'cpu_shaders_particles.dart';
export 'cpu_shaders_post.dart';
export 'cpu_shaders_reflections.dart';
export 'cpu_shaders_shadow_directional.dart';
export 'cpu_shaders_shadow_passes.dart';
export 'cpu_shaders_shadow_point.dart';
export 'cpu_shaders_sky.dart';
export 'cpu_shaders_ssao.dart';
export 'cpu_shaders_surface.dart';

/// A stage that exists so the name resolves and fails if anybody draws with it.
///
/// The conformance suite asks that every entry point the engine names is
/// answered, and answering is genuinely required — the engine resolves all of
/// them at `Renderer.create` and throws on the first missing one, so a backend
/// with gaps cannot start at all. Answering with something that draws would be
/// worse than answering with something that says no.
final class _Unimplemented implements CpuVertexShader, CpuFragmentShader {
  const _Unimplemented(this.name);
  final String name;

  @override
  int get varyingCount => 0;

  @override
  Vector4 run(
    Float32List a,
    ShaderBindings b, [
    Object? out,
    Object? context,
  ]) => throw UnsupportedError(
    '$name is not written in Dart. This backend answers to every name the '
    'engine asks for so that it can start, and refuses the ones it cannot '
    'draw rather than drawing something else.',
  );
}

/// The stages that are not written in Dart, by name.
///
/// Public, and the single source of the fact. `builtinCpuShaders` builds the
/// refusing stubs from it and `test/shader_names_test.dart` checks that every
/// name on it really does refuse — so implementing one means deleting it here,
/// and the test fails until that is done. A stub that quietly stopped being a
/// stub is exactly the drift this list exists to prevent.
const List<String> kUnimplementedCpuVertexShaders = <String>[];

/// The fragment half of [kUnimplementedCpuVertexShaders].
const List<String> kUnimplementedCpuFragmentShaders = <String>[];

/// Every stage, by the name the engine uses.
Map<String, CpuStage> builtinCpuShaders() {
  final stages = <String, CpuStage>{
    'MeshVertex': const CpuStage.vertex(MeshVertexShader()),
    'FullscreenVertex': const CpuStage.vertex(FullscreenVertexShader()),
    'Unlit': const CpuStage.fragment(UnlitShader()),
    'Lambert': const CpuStage.fragment(LambertShader()),
    'BlinnPhong': const CpuStage.fragment(BlinnPhongShader()),
    'Pbr': const CpuStage.fragment(PbrShader()),
    'Toon': const CpuStage.fragment(ToonShader()),
    'Normals': const CpuStage.fragment(NormalsShader()),
    'BloomThreshold': const CpuStage.fragment(BloomThresholdShader()),
    'BloomDownsample': const CpuStage.fragment(BloomDownsampleShader()),
    'BloomUpsample': const CpuStage.fragment(BloomUpsampleShader()),
    'MeshSkinnedVertex': const CpuStage.vertex(MeshSkinnedVertexShader()),
    'DebugLineVertex': const CpuStage.vertex(DebugLineVertexShader()),
    'DebugLine': const CpuStage.fragment(DebugLineShader()),
    'ParticleVertex': const CpuStage.vertex(ParticleVertexShader()),
    'ParticleMeshVertex': const CpuStage.vertex(ParticleMeshVertexShader()),
    'ParticleMesh': const CpuStage.fragment(ParticleMeshShader()),
    'ParticleTextured': const CpuStage.fragment(ParticleTexturedShader()),
    'Particle': const CpuStage.fragment(ParticleShader()),
    'Reflections': const CpuStage.fragment(ReflectionsShader()),
    'Ssao': const CpuStage.fragment(SsaoShader()),
    'MrtProbe': const CpuStage.fragment(MrtProbeShader()),
    'Composite': const CpuStage.fragment(CompositeShader()),
    'ShadowDepth': const CpuStage.fragment(ShadowDepthShader()),
    'ShadowDistance': const CpuStage.fragment(ShadowDistanceShader()),
    'ShadowTileReset': const CpuStage.fragment(ShadowTileResetShader()),
    'ShadowTileResetVertex': const CpuStage.vertex(
      ShadowTileResetVertexShader(),
    ),
    'SkyVertex': const CpuStage.vertex(SkyVertexShader()),
    'SkyCubeVertex': const CpuStage.vertex(SkyCubeVertexShader()),
    'Sky': const CpuStage.fragment(SkyShader()),
    'SkyCube': const CpuStage.fragment(SkyCubeShader()),
  };

  for (final name in kUnimplementedCpuVertexShaders) {
    stages[name] = CpuStage.vertex(_Unimplemented(name));
  }
  for (final name in kUnimplementedCpuFragmentShaders) {
    stages[name] = CpuStage.fragment(_Unimplemented(name));
  }
  return stages;
}
