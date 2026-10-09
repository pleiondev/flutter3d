/// The software backend's half of the material language — `gfx-84n`.
///
/// **Twenty lines, and here rather than in `flutter3d_cpu`.** That package has
/// `flutter3d_core` as a dev dependency with "nothing in `lib/` reaches it"
/// written beside it: a backend that imported the engine's formats library
/// would invert the direction an application assembles the two in. This
/// package already depends on both, which is what it is for. It lived in
/// `flutter3d_testing` until a game needed it — `P8`, a bundle built from a
/// `.f3dmat` drawn on the software backend — and a game cannot depend on a
/// package that carries `flutter_test`.
///
/// Everything that decides what a material *means* is in
/// `material_eval.dart`, beside the emitter that writes the GLSL — so what is
/// left here is filling in the surface a fragment is being shaded at, and
/// handing back what `WriteSurface(rgb, a)` takes.
///
///     final program = specializeMaterial(
///       parseMaterial(source),
///       const MaterialVariant('RimLight'),
///     );
///     final device = CpuDevice(
///       shaders: CpuShaderLibrary({
///         ...builtinCpuShaders(),
///         'RimLight': CpuStage.fragment(MaterialProgramStage(program)),
///       }),
///     );
///
/// **Version 2 of the language runs here whole**: the `vertex` block as
/// [MaterialVertexStage], the `ambient` and `composite` hooks and the two
/// switches through `composeMaterialLit`, the scene behind a translucent
/// surface, a full-screen stage as [MaterialFullscreenStage] and a compute
/// kernel as [materialComputeStage] — the one backend of the four that runs
/// a kernel written in the language.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_cpu/builtin.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:vector_math/vector_math.dart';

/// What `sceneDepth` reads where nothing was drawn behind: the sky, a
/// million metres off — `materialNothingBehind` in the emitted GLSL.
const double _nothingBehind = 1000000.0;

/// One compiled material, as a stage the software backend can be given.
///
/// The program must already be through `specializeMaterial`: a parameter has
/// no value until a variant gives it one, and a backend picking a default here
/// would be a backend disagreeing with the compiled shader.
final class MaterialProgramStage extends CpuFragmentShader {
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
    // `P8`: a lighting hook makes this a lit model — the maps applied, the
    // lights gathered through the block — as the emitted shader does.
    final light = program.light;
    if (light != null) applyCommonMaps(s, v, bindings, c);
    final inputs = <String, List<double>>{
      'albedo': <double>[s.albedo.x, s.albedo.y, s.albedo.z],
      'alpha': <double>[s.alpha],
      'normal': <double>[s.normal.x, s.normal.y, s.normal.z],
      'view': <double>[s.view.x, s.view.y, s.view.z],
      'nDotV': <double>[s.nDotV],
      'metallic': <double>[s.metallic],
      'roughness': <double>[s.roughness],
      'occlusion': <double>[s.occlusion],
      'emissive': <double>[s.emissive.r, s.emissive.g, s.emissive.b],
      'ambient': <double>[s.ambient.x, s.ambient.y, s.ambient.z],
      'uv': <double>[
        v[CpuMeshLayout.varyingUv],
        v[CpuMeshLayout.varyingUv + 1],
      ],
      'world': <double>[s.world.x, s.world.y, s.world.z],
      'instance': <double>[
        v[CpuMeshLayout.varyingInstance],
        v[CpuMeshLayout.varyingInstance + 1],
        v[CpuMeshLayout.varyingInstance + 2],
        v[CpuMeshLayout.varyingInstance + 3],
      ],
    };
    // `P8`: the draw's `MaterialParams`, which is `RenderMaterial.parameters`,
    // member by member as the GLSL reads its block.
    final uniforms = <String, List<double>>{
      for (final parameter in program.parameters)
        if (parameter.uniform)
          parameter.name: ?bindings.read('MaterialParams', parameter.name),
    };
    List<double> sample(MaterialTextureSlot slot, double u, double w) {
      final texture = bindings.textures[slot.bindingName];
      // White is what `surface.glsl` falls back to for an unbound base
      // colour, so a material sampling a slot this draw did not fill
      // looks the same on both sides.
      if (texture == null) return const <double>[1, 1, 1, 1];
      final texel = texture.sample(u, w, du: footprint.du, dv: footprint.dv);
      return <double>[texel.x, texel.y, texel.z, texel.w];
    }

    if (light != null) {
      // `lit` as the emitted `main` adds it up: the lights through the
      // block, by radiance, n·l and shadow, then ambient and lightmap under
      // the occlusion, then the emissive — `materialLitInput` — or as the
      // version 2 hooks and switches say, through `composeMaterialLit`.
      Vector3 shade(Surface s, LightSample light) {
        final half = (light.direction + s.view)..normalize();
        final answer = evaluateMaterialLight(
          program,
          MaterialSurfaceValues(
            inputs: <String, List<double>>{
              ...inputs,
              'lightDir': <double>[
                light.direction.x,
                light.direction.y,
                light.direction.z,
              ],
              'halfDir': <double>[half.x, half.y, half.z],
              'nDotL': <double>[light.nDotL],
              'nDotH': <double>[light.nDotH],
              'vDotH': <double>[light.vDotH],
            },
            uniforms: uniforms,
            sample: sample,
          ),
        );
        return Vector3(answer[0], answer[1], answer[2]);
      }

      final direct = program.state.directional
          ? accumulateLights(s, bindings, c, shade: shade, shadowed: true)
          : _withoutDirectional(s, bindings, c, shade);
      final lightmap = sampleLightmap(v, bindings, c);
      final lit = composeMaterialLit(
        program,
        MaterialSurfaceValues(
          inputs: inputs,
          uniforms: uniforms,
          sample: sample,
        ),
        direct: <double>[direct.x, direct.y, direct.z],
        lightmap: <double>[lightmap.x, lightmap.y, lightmap.z],
      );
      inputs['lit'] = lit;
    }

    // Version 2: this fragment's depth along the view axis, and the opaque
    // scene's behind it, as the emitted `main` reads them.
    if (program.inputsUsed.contains('viewDepth') || program.readsSceneDepth) {
      final depth = viewDepth(v, bindings);
      inputs['viewDepth'] = <double>[depth];
      if (program.readsSceneDepth) {
        final behind = _sceneDepthAt(bindings, c);
        final eye = bindings.vec4('FogInfo', 'eye', Vector4.zero());
        final forward = bindings.vec4('FogInfo', 'forward', Vector4.zero());
        final orthographic =
            bindings.vec4('FogInfo', 'projection', Vector4.zero()).x > 0.5;
        final at = orthographic
            ? s.world +
                  Vector3(forward.x, forward.y, forward.z) * (behind - depth)
            : Vector3(eye.x, eye.y, eye.z) +
                  (s.world - Vector3(eye.x, eye.y, eye.z)) *
                      (behind / (depth > 1e-6 ? depth : 1e-6));
        inputs['sceneDepth'] = <double>[behind];
        inputs['scenePosition'] = <double>[at.x, at.y, at.z];
      }
    }

    final result = evaluateMaterial(
      program,
      MaterialSurfaceValues(inputs: inputs, uniforms: uniforms, sample: sample),
    );

    // `blend premultiplied`: the colour is already times its alpha, and
    // `writeLit` weighs a blended surface's by it — so it is divided out
    // first, where there is an alpha to divide by. At nought the colour is
    // light added through a surface that covers nothing, which the blend
    // equation keeps and this one cannot; it is the emitted stage's case
    // alone, and a golden would show it.
    final premultiplied =
        program.state.blend == MaterialBlend.premultiplied &&
        premultiplies(bindings);
    final undo = premultiplied && result[3] > 0.0 ? 1.0 / result[3] : 1.0;

    // `WriteSurface(rgb, a)` in `color.glsl`, which is the one-argument form:
    // a surface that cannot say how polished it is is written fully rough, so
    // nothing reflects off it. The same call `unlit.frag` makes and the same
    // transcription `UnlitShader` makes of it.
    return writeLit(
      c,
      v,
      bindings,
      color: Vector3(result[0] * undo, result[1] * undo, result[2] * undo),
      alpha: result[3],
      normal: s.normal,
      roughness: 1,
    );
  }
}

/// `MaterialLights` in the emitted GLSL — `directional off`: every light the
/// draw has but the directional ones, which always sit in its eight slots.
Vector3 _withoutDirectional(
  Surface s,
  ShaderBindings b,
  FragmentContext c,
  Vector3 Function(Surface s, LightSample light) shade,
) {
  var total = Vector3.zero();
  final count = lightCount(b, s.world);
  for (var i = 0; i < count; i++) {
    if (i < CpuMeshLayout.maxLights &&
        b.vec4('FragInfo', 'light_position', Vector4.zero(), at: i).w < 0.5) {
      continue;
    }
    final light = sampleLight(b, i, s);
    if (light == null) continue;
    var visibility = 1.0;
    shadowTransmittance.setValues(1.0, 1.0, 1.0);
    if (i < CpuMeshLayout.maxLights) {
      visibility = shadowFactor(s, b, i, light.nDotL, c);
      visibility *= pointShadowFactor(b, s.world, s.normal, i, c);
    }
    if (visibility <= 0.0) continue;
    final response = shade(s, light);
    total += Vector3(
      response.x * light.radiance.x * shadowTransmittance.x,
      response.y * light.radiance.y * shadowTransmittance.y,
      response.z * light.radiance.z * shadowTransmittance.z,
    )..scale(light.nDotL * visibility);
  }
  return total;
}

/// The opaque scene's depth behind fragment [c], from `scene_depth_texture`
/// through `SceneDepthInfo` as the emitted stage reads it; the sky where
/// nothing was drawn, or where the draw was handed no buffer.
double _sceneDepthAt(ShaderBindings bindings, FragmentContext c) {
  final surface = bindings.textures['scene_depth_texture'];
  if (surface == null) return _nothingBehind;
  final target = bindings.vec4('SceneDepthInfo', 'target', Vector4.zero());
  // `FragCoordFromTop`.
  final row = target.z > 0.0 ? target.z - c.coord.y : c.coord.y;
  final stored = surface.sample(c.coord.x * target.x, row * target.y).w;
  return stored > 0.0 ? stored : _nothingBehind;
}

/// A material's `vertex` block as the software backend's vertex stage —
/// version 2: the engine's mesh stage, or its skinned one, and then the
/// block, as the emitted `<name>Vertex` and `<name>VertexSkinned` run it.
///
/// **What the block reads is taken back out of what the engine's stage
/// wrote**, rather than the engine's arithmetic written a second time: the
/// mesh-space position and normal are the world ones through the inverse
/// of the model transform, which is the skinned pose's for a skinned draw,
/// as the GLSL has it.
final class MaterialVertexStage extends CpuVertexShaderByIndex {
  const MaterialVertexStage(this.program, {this.skinned = false});

  final MaterialProgram program;

  /// Whether this is the skinned half.
  final bool skinned;

  static const MeshVertexShader _plain = MeshVertexShader();
  static const MeshSkinnedVertexShader _skinned = MeshSkinnedVertexShader();

  @override
  int get varyingCount => CpuMeshLayout.varyings;

  @override
  Vector4 run(Float32List a, ShaderBindings bindings, Float32List out) =>
      runAt(-1, 0, a, bindings, out);

  @override
  Vector4 runAt(
    int vertexIndex,
    int instanceIndex,
    Float32List a,
    ShaderBindings bindings,
    Float32List out,
  ) {
    final clip = (skinned ? _skinned : _plain).runAt(
      vertexIndex,
      instanceIndex,
      a,
      bindings,
      out,
    );
    final model = bindings.mat4('FrameInfo', 'model');
    final mvp = bindings.mat4('FrameInfo', 'mvp');
    final world = Vector3(
      out[CpuMeshLayout.varyingWorld],
      out[CpuMeshLayout.varyingWorld + 1],
      out[CpuMeshLayout.varyingWorld + 2],
    );
    final normal = Vector3(
      out[CpuMeshLayout.varyingNormal],
      out[CpuMeshLayout.varyingNormal + 1],
      out[CpuMeshLayout.varyingNormal + 2],
    );
    final toMesh = Matrix4.copy(model)..invert();
    final position = toMesh.transformed3(world.clone());
    final normalRotation = bindings
        .mat4('FrameInfo', 'normal_matrix')
        .getRotation();
    final objectNormal = (normalRotation..invert()).transformed(normal.clone());
    final origin = model.getTranslation();

    final uniforms = <String, List<double>>{
      for (final parameter in program.parameters)
        if (parameter.uniform)
          parameter.name: ?bindings.read('MaterialParams', parameter.name),
    };
    final written = evaluateMaterialVertex(
      program,
      MaterialSurfaceValues(
        inputs: <String, List<double>>{
          'position': <double>[position.x, position.y, position.z],
          'objectNormal': <double>[
            objectNormal.x,
            objectNormal.y,
            objectNormal.z,
          ],
          'world': <double>[world.x, world.y, world.z],
          'normal': <double>[normal.x, normal.y, normal.z],
          'uv': <double>[
            a[CpuMeshLayout.texcoord],
            a[CpuMeshLayout.texcoord + 1],
          ],
          'color': <double>[
            a[CpuMeshLayout.color],
            a[CpuMeshLayout.color + 1],
            a[CpuMeshLayout.color + 2],
            a[CpuMeshLayout.color + 3],
          ],
          'origin': <double>[origin.x, origin.y, origin.z],
        },
        uniforms: uniforms,
        sample: (_, _, _) =>
            throw StateError('a vertex block samples no texture'),
      ),
    );

    if (written['normal'] case final n?) {
      out
        ..[CpuMeshLayout.varyingNormal] = n[0]
        ..[CpuMeshLayout.varyingNormal + 1] = n[1]
        ..[CpuMeshLayout.varyingNormal + 2] = n[2];
    }
    if (written['position'] case final p?) {
      final local = Vector4(p[0], p[1], p[2], 1.0);
      final Vector4 moved = model * local;
      out
        ..[CpuMeshLayout.varyingWorld] = moved.x
        ..[CpuMeshLayout.varyingWorld + 1] = moved.y
        ..[CpuMeshLayout.varyingWorld + 2] = moved.z;
      return mvp * local;
    }
    if (written['world'] case final w?) {
      out
        ..[CpuMeshLayout.varyingWorld] = w[0]
        ..[CpuMeshLayout.varyingWorld + 1] = w[1]
        ..[CpuMeshLayout.varyingWorld + 2] = w[2];
      final viewProjection = bindings.mat4(
        'MaterialVertexInfo',
        'view_projection',
      );
      return viewProjection * Vector4(w[0], w[1], w[2], 1.0);
    }
    return clip;
  }
}

/// A full-screen stage written in the language — version 2 — as the
/// software backend's fragment stage, behind its `FullscreenVertex`.
final class MaterialFullscreenStage extends CpuFragmentShader {
  const MaterialFullscreenStage(this.program);

  final MaterialProgram program;

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) {
    final u = v[0];
    final w = v[1];
    final inputs = <String, List<double>>{
      'uv': <double>[u, w],
      if (program.inputsUsed.contains('sceneDepth'))
        'sceneDepth': <double>[
          switch (bindings.textures['surface_texture']) {
            null => _nothingBehind,
            final surface => switch (surface.sample(u, w).w) {
              final stored when stored > 0.0 => stored,
              _ => _nothingBehind,
            },
          },
        ],
    };
    final result = evaluateMaterial(
      program,
      MaterialSurfaceValues(
        inputs: inputs,
        uniforms: <String, List<double>>{
          for (final parameter in program.parameters)
            if (parameter.uniform)
              parameter.name: ?bindings.read('MaterialParams', parameter.name),
        },
        sample: (slot, u, w) {
          final texture = bindings.textures[slot.bindingName];
          if (texture == null) return const <double>[0, 0, 0, 0];
          final texel = texture.sample(u, w);
          return <double>[texel.x, texel.y, texel.z, texel.w];
        },
      ),
    );
    return Vector4(result[0], result[1], result[2], result[3]);
  }
}

/// A compute kernel written in the language — version 2 — as the software
/// backend's compute stage: one invocation per texel of the storage texture
/// bound as `target`, each writing what the kernel returns there.
///
/// **The one backend that runs a kernel written in the language.** Impeller
/// and WebGL2 have no compute pipelines, and WebGPU runs the engine's own
/// compute stages alone; `flutter3d_build` refuses a kernel under
/// `assets_src/` with that sentence. [program] must be specialised.
///
///     CpuDevice(
///       shaders: CpuShaderLibrary({
///         ...builtinCpuShaders(),
///         'Ripples': CpuStage.compute(materialComputeStage(program)),
///       }),
///     );
CpuComputeShader materialComputeStage(MaterialProgram program) {
  if (program.kind != MaterialStageKind.compute) {
    throw ArgumentError.value(
      program.name,
      'program',
      'is a ${program.kind} stage, not a compute kernel',
    );
  }
  return _MaterialKernel(program);
}

final class _MaterialKernel extends CpuComputeShader {
  _MaterialKernel(this.program);

  final MaterialProgram program;

  @override
  (int, int, int) get workgroupSize =>
      (program.workgroupSize.$1, program.workgroupSize.$2, 1);

  @override
  void runWorkgroup((int, int, int) group, CpuComputeBindings bindings) {
    final target =
        bindings.storageTextures['target'] ??
        (throw StateError(
          'kernel "${program.name}" writes the storage texture "target", '
          'and none was bound',
        ));
    final params = bindings.blocks['MaterialParams'];
    final uniforms = <String, List<double>>{
      for (final parameter in program.parameters)
        if (parameter.uniform) parameter.name: ?params?[parameter.name],
    };
    List<double> sample(MaterialTextureSlot slot, double u, double w) {
      final bound = bindings.textures[slot.bindingName];
      if (bound == null) return const <double>[0, 0, 0, 0];
      final texel = bound.sample(u, w);
      return <double>[texel.x, texel.y, texel.z, texel.w];
    }

    final (sizeX, sizeY) = program.workgroupSize;
    final width = target.width;
    final height = target.height;
    for (var y = 0; y < sizeY; y++) {
      for (var x = 0; x < sizeX; x++) {
        final cellX = group.$1 * sizeX + x;
        final cellY = group.$2 * sizeY + y;
        if (cellX >= width || cellY >= height) continue;
        final result = evaluateMaterial(
          program,
          MaterialSurfaceValues(
            inputs: <String, List<double>>{
              'cell': <double>[cellX.toDouble(), cellY.toDouble()],
              'size': <double>[width.toDouble(), height.toDouble()],
              'uv': <double>[(cellX + 0.5) / width, (cellY + 0.5) / height],
            },
            uniforms: uniforms,
            sample: sample,
          ),
        );
        target.store(
          cellX,
          cellY,
          Vector4(result[0], result[1], result[2], result[3]),
        );
      }
    }
  }
}

/// A `CpuMaterialCompiler` for the engine's material language — `P8`: the
/// source parsed and specialised at its declared defaults, as the build does
/// for the GPU sections beside it, and run by [MaterialProgramStage].
///
/// Handed to `CpuDevice(materialCompiler: ...)`, a bundle the build made from
/// a `.f3dmat` loads on the software backend with nothing registered by hand.
/// A source that does not parse is refused with its line and column.
///
/// **Every stage a source becomes — version 2.** A bundle carries the source
/// under each stage's name: the material's own, answered by
/// [MaterialProgramStage] or, for a full-screen stage,
/// [MaterialFullscreenStage]; and `<name>Vertex` and `<name>VertexSkinned`,
/// answered by [MaterialVertexStage], which the library hands out as a
/// vertex stage.
CpuStage materialLanguageCompiler(String stage, String source) {
  final program = parseMaterial(source);
  final specialised = specializeMaterial(
    program,
    MaterialVariant(program.name),
  );
  final vertex = program.vertexStageName;
  if (vertex != null && stage == vertex) {
    return CpuStage.vertex(MaterialVertexStage(specialised));
  }
  if (vertex != null && stage == '${vertex}Skinned') {
    return CpuStage.vertex(MaterialVertexStage(specialised, skinned: true));
  }
  if (program.name != stage) {
    throw MaterialBundleException(
      'the source is material "${program.name}" and the bundle calls it '
      '"$stage"',
    );
  }
  return switch (program.kind) {
    MaterialStageKind.fullscreen => CpuStage.fragment(
      MaterialFullscreenStage(specialised),
    ),
    MaterialStageKind.compute => throw MaterialBundleException(
      '"$stage" is a compute kernel, which a bundle does not carry: hand '
      'materialComputeStage(...) to CpuDevice.shaders instead',
    ),
    _ => CpuStage.fragment(MaterialProgramStage(specialised)),
  };
}
