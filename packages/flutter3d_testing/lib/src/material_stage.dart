/// The software backend's half of the material language — `gfx-84n`.
///
/// **Twenty lines, and here rather than in `flutter3d_cpu`.** That package has
/// `flutter3d_core` as a dev dependency with "nothing in `lib/` reaches it"
/// written beside it: a backend that imported the engine's formats library
/// would invert the direction an application assembles the two in. This
/// package already depends on both, which is what it is for.
///
/// Everything that decides what a material *means* is in
/// `material_eval.dart`, beside the emitter that writes the GLSL — so what is
/// left here is filling in the surface a fragment is being shaded at, and
/// handing back what `WriteSurface(rgb, a)` takes.
///
///     final program = specialiseMaterial(
///       parseMaterial(source),
///       const MaterialVariant('RimLight'),
///     );
///     final device = CpuDevice(
///       shaders: CpuShaderLibrary({
///         ...builtinCpuShaders(),
///         'RimLight': CpuStage.fragment(MaterialProgramStage(program)),
///       }),
///     );
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:vector_math/vector_math.dart';

/// One compiled material, as a stage the software backend can be given.
///
/// The program must already be through `specialiseMaterial`: a parameter has
/// no value until a variant gives it one, and a backend picking a default here
/// would be a backend disagreeing with the compiled shader.
final class MaterialProgramStage implements CpuFragmentShader {
  const MaterialProgramStage(this.program);

  final MaterialProgram program;

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) {
    final s = readSurface(v, bindings, c);
    // Null is the GLSL's `discard`, which `ReadSurface` performs for a masked
    // material under its cutoff — the emitted shader gets it from the same
    // header, so both sides drop the same fragments.
    if (s == null) return null;

    final footprint = uvFootprint(c);
    final result = evaluateMaterial(
      program,
      MaterialSurfaceValues(
        inputs: <String, List<double>>{
          'albedo': <double>[s.albedo.x, s.albedo.y, s.albedo.z],
          'alpha': <double>[s.alpha],
          'normal': <double>[s.normal.x, s.normal.y, s.normal.z],
          'view': <double>[s.view.x, s.view.y, s.view.z],
          'nDotV': <double>[s.nDotV],
          'metallic': <double>[s.metallic],
          'roughness': <double>[s.roughness],
          'occlusion': <double>[s.occlusion],
          'emissive': <double>[s.emissive.x, s.emissive.y, s.emissive.z],
          'ambient': <double>[s.ambient.x, s.ambient.y, s.ambient.z],
          'uv': <double>[v[kVUv], v[kVUv + 1]],
          'world': <double>[s.world.x, s.world.y, s.world.z],
        },
        sample: (slot, u, w) {
          final texture = bindings.textures[slot.bindingName];
          // White is what `surface.glsl` falls back to for an unbound base
          // colour, so a material sampling a slot this draw did not fill
          // looks the same on both sides.
          if (texture == null) return const <double>[1, 1, 1, 1];
          final texel = texture.sample(
            u,
            w,
            du: footprint.du,
            dv: footprint.dv,
          );
          return <double>[texel.x, texel.y, texel.z, texel.w];
        },
      ),
    );

    // `WriteSurface(rgb, a)` in `color.glsl`, which is the one-argument form:
    // a surface that cannot say how polished it is is written fully rough, so
    // nothing reflects off it. The same call `unlit.frag` makes and the same
    // transcription `UnlitShader` makes of it.
    return writeLit(
      c,
      v,
      bindings,
      colour: Vector3(result[0], result[1], result[2]),
      alpha: result[3],
      normal: s.normal,
      roughness: 1,
    );
  }
}
