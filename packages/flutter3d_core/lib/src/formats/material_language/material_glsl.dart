/// Turns a parsed material into the GLSL this engine's shader build already
/// compiles — `gfx-84n`.
///
/// **It emits into the existing convention rather than beside it.** The result
/// is a `.frag` shaped exactly like `unlit.frag`: it includes
/// `<lib/surface.glsl>`, satisfies the `ShadeLight` and `LightVisibility`
/// prototypes that header declares, reads the surface with `ReadSurface()` and
/// writes it with `WriteSurface()`. That is what "through the existing
/// generators" means in the row's acceptance — `impellerc` compiles it,
/// `glsl_translate.dart` turns it into GLSL ES 3.00 for WebGL2, and
/// `glsl_to_wgsl.dart` prepares it for glslang and naga, all without knowing a
/// material language exists.
///
/// **What it does not emit is as deliberate.** No uniform block of its own
/// but one: the engine's shared blocks are frozen by offset agreement across
/// four backends, and the one block a material may add — `MaterialParams`,
/// filled from `RenderMaterial.parameters` — is written for the program's
/// `uniform`s, and only when it has one (`P8`); a `param` is still a folded
/// constant. No sampler declaration, because `surface.glsl` already declares the ones the
/// engine binds and a second declaration is a duplicate symbol. No `#define`
/// the author chose, because a material that could switch headers on and off
/// could turn off the surface buffer and lie to every screen-space effect.
library;

import '../lighting_model.dart';
import 'material_ast.dart';

/// The `.frag` source for [program], which should already be specialised.
///
/// [describeMaterial] answers the other half — what the engine may bind to it.
///
/// A full-screen stage is a fragment stage too, of the shape every post
/// stage of the engine's has — see [_emitFullscreen]. A compute kernel has
/// no fragment, and is refused with an [ArgumentError].
String emitMaterialFragment(MaterialProgram program) {
  if (program.kind == MaterialStageKind.fullscreen) {
    return _emitFullscreen(program);
  }
  if (program.kind == MaterialStageKind.compute) {
    throw ArgumentError.value(
      program.name,
      'program',
      'a compute stage has no fragment stage to emit; the software backend '
          'runs its kernel, and no GPU backend compiles one yet',
    );
  }
  final light = program.light;
  final state = program.state;
  // Version 2's lit path: the hooks, the switches, or both. Without any of
  // them a lit material adds `lit` up exactly as version 1 did, so every
  // stage written before them compiles to the same text.
  final hooked =
      light != null &&
      (program.ambient != null ||
          program.composite != null ||
          !state.environment ||
          !state.directional);
  final readsScene = program.readsSceneDepth;
  final readsViewDepth = readsScene || program.inputsUsed.contains('viewDepth');
  final out = StringBuffer()
    ..writeln('#version 460 core')
    ..writeln()
    ..writeln('// Generated from a material written in the material language')
    ..writeln('// — gfx-84n. The source is the thing to edit; this file is')
    ..writeln('// what the shader build compiles and what the three GPU')
    ..writeln('// backends translate. The software backend evaluates the same')
    ..writeln('// tree instead of reading this.');
  if (light == null) {
    // It gathers no lights, so it keeps no light list — see
    // `LightingModel.usesLightList` — and no point-shadow block either, as
    // `unlit.frag` keeps none: a block declared and never bound is a
    // refused draw on WebGL2.
    out
      ..writeln('#define F3D_NO_POINT_SHADOW')
      ..writeln('#define F3D_NO_LIGHT_LIST')
      ..writeln('#include <lib/surface.glsl>')
      ..writeln();
  } else {
    // `P8`: a material with a lighting hook is a lit model, and includes
    // what `lambert.frag` does — the maps, the shadows, the light list.
    out
      ..writeln('#include <lib/material_maps.glsl>')
      ..writeln('#include <lib/shadow.glsl>')
      ..writeln();
  }

  // `P8`: an instance's own numbers, declared after every header's inputs so
  // it takes the location the engine's vertex stages give it, after
  // `v_lightmap_uv` — and only when read, since a varying no stage writes is
  // a link error on a stage that writes it not.
  if (program.inputsUsed.contains('instance')) {
    out
      ..writeln('in vec4 v_instance;')
      ..writeln();
  }

  // Version 2: the scene behind a translucent surface, which the engine
  // lends it after the opaque half — `lib/particle_soft.glsl`'s pair, under
  // names of the material's own.
  if (readsScene) {
    out
      ..writeln('// The opaque scene\'s surface buffer: in a, its depth along')
      ..writeln('// the view axis in metres, nought where nothing was drawn.')
      ..writeln('uniform sampler2D scene_depth_texture;')
      ..writeln()
      ..writeln('uniform SceneDepthInfo {')
      ..writeln('  // xy: one over the target\'s size. z: its rows when row')
      ..writeln('  // zero is the bottom, nought when it is the top.')
      ..writeln('  vec4 target;')
      ..writeln('}')
      ..writeln('scene_depth_info;')
      ..writeln();
  }

  _uniformBlock(out, program);

  if (light == null) {
    // Both prototypes have to be satisfied whether or not anything calls
    // them, which is what `unlit.frag` says about its own pair. A material
    // without a `light` block never accumulates lights — it returns the light
    // the surface emits — so these are the same honest stubs.
    out
      ..writeln('// Never called: this material returns the light its surface')
      ..writeln('// emits rather than gathering any. The prototypes in')
      ..writeln('// surface.glsl still have to be satisfied.')
      ..writeln('vec3 ShadeLight(Surface s, LightSample light) {')
      ..writeln('  return s.albedo;')
      ..writeln('}')
      ..writeln()
      ..writeln('float LightVisibility(Surface s, LightSample light, int i) {')
      ..writeln('  return 1.0;')
      ..writeln('}')
      ..writeln();
  } else {
    // The `light` block is `ShadeLight`, which `AccumulateLights` multiplies
    // by the light's radiance, n·l and visibility; the visibility is the
    // shadow, as every lit model of the engine's has it.
    out
      ..writeln('// The material\'s light block, run once per light.')
      ..writeln('vec3 ShadeLight(Surface s, LightSample light) {');
    _statements(out, light, (value) => '  return ${_glsl(value)};');
    out
      ..writeln('}')
      ..writeln()
      ..writeln('float LightVisibility(Surface s, LightSample light, int i) {')
      ..writeln('  return ShadowFactor(s, light, i);')
      ..writeln('}')
      ..writeln();
  }

  // Version 2's hooks, each a function of its own beside `ShadeLight`.
  if (program.ambient case final ambient?) {
    out
      ..writeln('// The material\'s ambient block: the light the surface takes')
      ..writeln('// from its surroundings, in place of the engine\'s own.')
      ..writeln('vec3 ShadeAmbient(Surface s, vec3 f3d_lightmap) {');
    _statements(out, ambient, (value) => '  return ${_glsl(value)};');
    out
      ..writeln('}')
      ..writeln();
  }
  if (program.composite case final composite?) {
    out
      ..writeln('// The material\'s composite block: how `lit` is added up.')
      ..writeln(
        'vec3 ShadeComposite(Surface s, vec3 f3d_direct, vec3 f3d_indirect) {',
      );
    _statements(out, composite, (value) => '  return ${_glsl(value)};');
    out
      ..writeln('}')
      ..writeln();
  }
  if (light != null && !state.directional) {
    // `directional off`: `AccumulateLights` with the sun left out. A
    // directional light always takes one of the draw's eight slots —
    // `LightBuffer` ranks only the lights with a position into the list —
    // so its type is read off the slot and nothing in the list is one.
    out
      ..writeln('// `directional off`: every light the draw has but the')
      ..writeln('// directional ones, which always sit in its eight slots.')
      ..writeln('vec3 MaterialLights(Surface s) {')
      ..writeln('  vec3 total = vec3(0.0);')
      ..writeln('  int count = LightCount();')
      ..writeln('  for (int i = 0; i < kTotalLights; i++) {')
      ..writeln('    if (i >= count) break;')
      ..writeln(
        '    if (i < kMaxLights && frag_info.light_position[i].w < 0.5) '
        'continue;',
      )
      ..writeln('    LightSample light = SampleLight(i, s);')
      ..writeln('    if (light.n_dot_l <= 0.0) continue;')
      ..writeln('    light_transmittance = vec3(1.0);')
      ..writeln('    float visibility = LightHasShadow(i)')
      ..writeln('        ? LightVisibility(s, light, i) *')
      ..writeln('              PointShadowFactor(v_world_position, s.n, i)')
      ..writeln('        : 1.0;')
      ..writeln('    if (visibility <= 0.0) continue;')
      ..writeln(
        '    total += ShadeLight(s, light) * light.radiance * light.n_dot_l * '
        'visibility * light_transmittance;',
      )
      ..writeln('  }')
      ..writeln('  return total;')
      ..writeln('}')
      ..writeln();
  }

  out
    ..writeln('void main() {')
    ..writeln('  Surface s = ReadSurface();');
  // `blend premultiplied`: the colour the body returns is already times its
  // alpha, so `WriteSurface` must not weigh it again — `ReadSurface` set
  // the flag for a blended surface, and it is put back here.
  if (state.blend == MaterialBlend.premultiplied) {
    out.writeln('  g_premultiply = false;');
  }
  if (light != null && !hooked) {
    // `lit` as `lambert.frag` adds it up — see `materialLitInput`.
    out
      ..writeln('  ApplyCommonMaps(s);')
      ..writeln(
        '  vec3 lit = AccumulateLights(s) * s.occlusion + '
        's.albedo * (s.ambient + SampleLightmap()) * s.occlusion + '
        's.emissive;',
      );
  } else if (light != null) {
    final direct = state.directional
        ? 'AccumulateLights(s)'
        : 'MaterialLights(s)';
    final indirect = !state.environment
        ? 'vec3(0.0)'
        : program.ambient != null
        ? 'ShadeAmbient(s, f3d_lightmap)'
        : 's.albedo * (s.ambient + f3d_lightmap)';
    final lit = program.composite != null
        ? 'ShadeComposite(s, f3d_direct, f3d_indirect)'
        : '(f3d_direct + f3d_indirect) * s.occlusion + s.emissive';
    out
      ..writeln('  ApplyCommonMaps(s);')
      ..writeln('  vec3 f3d_direct = $direct;')
      ..writeln('  vec3 f3d_lightmap = SampleLightmap();')
      ..writeln('  vec3 f3d_indirect = $indirect;')
      ..writeln('  vec3 lit = $lit;')
      // **Every lit stage keeps what the engine binds to one.** A hook or
      // a switch can leave the lightmap, the irradiance field, the maps or
      // the lights unread, and a compiler drops what nothing reads — which
      // makes the engine's bind of it a native crash on Metal. So they are
      // read here, behind a branch no frame takes: the environment's level
      // count is never below nought. A uniform the compiler cannot see
      // through, so it keeps them; a branch no fragment takes, so the
      // picture is the hooks' alone.
      ..writeln('  // Keeps what the engine binds to every lit stage; no frame')
      ..writeln('  // takes this branch.')
      ..writeln('  if (frag_info.frame_params.w < 0.0) {')
      ..writeln(
        '    lit += f3d_direct + f3d_lightmap + s.ambient + s.emissive + '
        'vec3(s.occlusion);',
      )
      ..writeln('  }');
  }
  if (readsViewDepth) {
    out.writeln('  float f3d_view_depth = ViewDepth();');
  }
  if (readsScene) {
    // `SoftParticleFade`'s read, and the opaque surface's position along
    // the same ray: from the eye through a perspective lens, along the view
    // axis through an orthographic one, where every ray is parallel.
    out
      ..writeln(
        '  vec2 f3d_scene_uv = FragCoordFromTop(scene_depth_info.target.z) * '
        'scene_depth_info.target.xy;',
      )
      ..writeln(
        '  float f3d_stored = textureLod(scene_depth_texture, f3d_scene_uv, '
        '0.0).a;',
      )
      ..writeln(
        '  float f3d_scene_depth = f3d_stored > 0.0 ? f3d_stored : '
        '$materialNothingBehind;',
      )
      ..writeln(
        '  vec3 f3d_scene_position = Orthographic()\n'
        '      ? v_world_position + fog_info.forward.xyz * '
        '(f3d_scene_depth - f3d_view_depth)\n'
        '      : fog_info.eye.xyz + (v_world_position - fog_info.eye.xyz) * '
        '(f3d_scene_depth / max(f3d_view_depth, 1e-6));',
      );
  }
  _statements(
    out,
    program.body,
    (value) =>
        '  vec4 result = ${_glsl(value)};\n'
        '  WriteSurface(result.rgb, result.a);',
  );
  out.writeln('}');
  return out.toString();
}

/// What `sceneDepth` reads where nothing was drawn behind — the sky — in
/// metres: far enough that every soft edge and every fog reads it as
/// nothing there, and well inside a half float.
const String materialNothingBehind = '1000000.0';

/// `P8`: the uniforms, as the block the engine binds `RenderMaterial.parameters`
/// to. Declaration order, as std140 lays it out and every backend's
/// reflection reports it. Nothing for a program without one.
void _uniformBlock(StringBuffer out, MaterialProgram program) {
  final uniforms = <MaterialParameter>[
    for (final parameter in program.parameters)
      if (parameter.uniform) parameter,
  ];
  if (uniforms.isEmpty) return;
  out.writeln('uniform MaterialParams {');
  for (final parameter in uniforms) {
    out.writeln('  ${parameter.type.name} ${parameter.name};');
  }
  out
    ..writeln('}')
    ..writeln('material_params;')
    ..writeln();
}

/// The vertex stage of [program]'s `vertex` block — version 2 — or, with
/// [skinned], its skinned half: `mesh.vert` and `mesh_skinned.vert` with
/// the block between the engine's answer and the varyings.
///
/// **The same varyings the engine's mesh stages write**, under the same
/// names, so every fragment stage the engine pairs with them reads it: the
/// material's own, the depth pre-draw's and the shadow passes'. That is what
/// lets the renderer draw a material's depth and its shadow through this
/// stage, and why geometry it moves casts the shadow it draws.
///
/// A block that writes `world` is projected through `MaterialVertexInfo`'s
/// `view_projection`: the engine's `FrameInfo` carries the model-view-
/// projection whole, and taking the model back out of it is an inverse
/// WGSL has not got. The renderer binds the block wherever it binds
/// `FrameInfo` to such a stage — scene, pre-draw, shadow — with the matrix
/// that pass draws through.
///
/// Throws an [ArgumentError] for a program without a `vertex` block.
String emitMaterialVertex(MaterialProgram program, {bool skinned = false}) {
  final vertex =
      program.vertex ??
      (throw ArgumentError.value(
        program.name,
        'program',
        'has no vertex block',
      ));
  final writes = <String>{
    for (final statement in vertex)
      if (statement is MaterialOutput) statement.output.name,
  };
  final projectsWorld = writes.contains('world');
  final out = StringBuffer()
    ..writeln('#version 460 core')
    ..writeln()
    ..writeln('// Generated from the vertex block of a material written in')
    ..writeln('// the material language, version 2. The source is the thing')
    ..writeln('// to edit. `mesh${skinned ? '_skinned' : ''}.vert` with the')
    ..writeln('// block between the engine\'s answer and the varyings.')
    ..writeln()
    ..writeln('in vec3 position;')
    ..writeln('in vec3 normal;')
    ..writeln('in vec2 texcoord;')
    ..writeln('in vec4 tangent;')
    ..writeln('in vec4 color;')
    ..writeln()
    ..writeln('#include <lib/morph.glsl>')
    ..writeln();
  if (skinned) {
    out
      ..writeln('in vec4 joints;')
      ..writeln('in vec4 weights;')
      ..writeln();
  }
  out
    ..writeln('uniform FrameInfo {')
    ..writeln('  mat4 mvp;')
    ..writeln('  mat4 model;')
    ..writeln('  mat4 normal_matrix;')
    ..writeln('}')
    ..writeln('frame_info;')
    ..writeln();
  if (skinned) {
    out
      ..writeln('#define kMaxJoints 64')
      ..writeln()
      ..writeln('uniform SkinInfo {')
      ..writeln('  mat4 joint_matrices[kMaxJoints];')
      ..writeln('}')
      ..writeln('skin_info;')
      ..writeln()
      ..writeln('int JointIndex(float joint) {')
      ..writeln('  return clamp(int(joint), 0, kMaxJoints - 1);')
      ..writeln('}')
      ..writeln()
      ..writeln('mat4 SkinMatrix() {')
      ..writeln(
        '  float total = weights.x + weights.y + weights.z + weights.w;',
      )
      ..writeln(
        '  vec4 w = total > 1e-5 ? weights / total : vec4(1.0, 0.0, 0.0, 0.0);',
      )
      ..writeln(
        '  return w.x * skin_info.joint_matrices[JointIndex(joints.x)] +',
      )
      ..writeln(
        '         w.y * skin_info.joint_matrices[JointIndex(joints.y)] +',
      )
      ..writeln(
        '         w.z * skin_info.joint_matrices[JointIndex(joints.z)] +',
      )
      ..writeln(
        '         w.w * skin_info.joint_matrices[JointIndex(joints.w)];',
      )
      ..writeln('}')
      ..writeln();
  }
  if (projectsWorld) {
    out
      ..writeln('// The view-projection alone, for a block that says where in')
      ..writeln('// the world the vertex is rather than where in the mesh.')
      ..writeln('uniform MaterialVertexInfo {')
      ..writeln('  mat4 view_projection;')
      ..writeln('}')
      ..writeln('material_vertex_info;')
      ..writeln();
  }
  _uniformBlock(out, program);
  out
    ..writeln('out vec3 v_world_position;')
    ..writeln('out vec3 v_normal;')
    ..writeln('out vec2 v_texcoord;')
    ..writeln('out vec4 v_tangent;')
    ..writeln('out vec4 v_color;')
    ..writeln('out vec2 v_lightmap_uv;')
    ..writeln('out vec4 v_instance;')
    ..writeln()
    ..writeln('void main() {')
    ..writeln('  vec3 morphed_position = position;')
    ..writeln('  vec3 morphed_normal = normal;')
    ..writeln('  vec4 morphed_tangent = tangent;')
    ..writeln(
      '  ApplyMorph(morphed_position, morphed_normal, morphed_tangent);',
    );
  if (skinned) {
    out
      ..writeln('  mat4 skin = SkinMatrix();')
      ..writeln('  mat3 f3d_skin_rotation = mat3(skin);')
      ..writeln(
        '  vec3 f3d_position = (skin * vec4(morphed_position, 1.0)).xyz;',
      )
      ..writeln(
        '  vec3 f3d_object_normal = f3d_skin_rotation * morphed_normal;',
      )
      ..writeln('  vec3 f3d_tangent = f3d_skin_rotation * morphed_tangent.xyz;')
      ..writeln(
        '  bool f3d_mirrored = (determinant(mat3(frame_info.model)) < 0.0) !=',
      )
      ..writeln(
        '                      (determinant(f3d_skin_rotation) < 0.0);',
      );
  } else {
    out
      ..writeln('  vec3 f3d_position = morphed_position;')
      ..writeln('  vec3 f3d_object_normal = morphed_normal;')
      ..writeln('  vec3 f3d_tangent = morphed_tangent.xyz;')
      ..writeln(
        '  bool f3d_mirrored = determinant(mat3(frame_info.model)) < 0.0;',
      );
  }
  out
    ..writeln(
      '  vec3 f3d_world = (frame_info.model * vec4(f3d_position, 1.0)).xyz;',
    )
    ..writeln(
      '  vec3 f3d_normal = mat3(frame_info.normal_matrix) * f3d_object_normal;',
    )
    ..writeln('  vec3 f3d_out_position = f3d_position;')
    ..writeln('  vec3 f3d_out_world = f3d_world;')
    ..writeln('  vec3 f3d_out_normal = f3d_normal;')
    ..writeln()
    ..writeln('  // The material\'s vertex block.');
  _statements(out, vertex, (_) => throw StateError('a vertex block returns'));
  out.writeln();
  if (writes.contains('position')) {
    out.writeln(
      '  f3d_out_world = (frame_info.model * vec4(f3d_out_position, '
      '1.0)).xyz;',
    );
  }
  out
    ..writeln('  v_world_position = f3d_out_world;')
    ..writeln('  v_normal = f3d_out_normal;')
    ..writeln('  v_texcoord = texcoord;')
    ..writeln('  v_tangent = vec4(mat3(frame_info.model) * f3d_tangent,')
    ..writeln(
      '                   f3d_mirrored ? -morphed_tangent.w : '
      'morphed_tangent.w);',
    )
    ..writeln('  v_color = color;')
    ..writeln('  v_lightmap_uv = vec2(0.0);')
    ..writeln('  v_instance = vec4(0.0);')
    ..writeln(
      projectsWorld
          ? '  gl_Position = material_vertex_info.view_projection * '
                'vec4(f3d_out_world, 1.0);'
          : '  gl_Position = frame_info.mvp * vec4(f3d_out_position, 1.0);',
    )
    ..writeln('}');
  return out.toString();
}

/// A full-screen stage — version 2: the shape of every post stage of the
/// engine's, which `FullscreenEffect` and a plugin's render step draw over
/// the shared `FullscreenVertex`. The picture is `scene_texture`; the
/// scene's depth, when the body reads `sceneDepth`, the surface buffer as
/// `surface_texture`; every other slot under the name the source binds it.
String _emitFullscreen(MaterialProgram program) {
  final readsDepth = program.inputsUsed.contains('sceneDepth');
  final out = StringBuffer()
    ..writeln('#version 460 core')
    ..writeln()
    ..writeln('// Generated from a full-screen stage written in the material')
    ..writeln('// language, version 2. The source is the thing to edit.')
    ..writeln()
    ..writeln('in vec2 v_uv;')
    ..writeln()
    ..writeln('out vec4 frag_color;')
    ..writeln();
  for (final slot in program.textures) {
    out.writeln('uniform sampler2D ${slot.bindingName};');
  }
  if (readsDepth) {
    out
      ..writeln('// The surface buffer: in a, the depth along the view axis.')
      ..writeln('uniform sampler2D surface_texture;');
  }
  out.writeln();
  _uniformBlock(out, program);
  out.writeln('void main() {');
  if (readsDepth) {
    out
      ..writeln(
        '  float f3d_stored = textureLod(surface_texture, v_uv, 0.0).a;',
      )
      ..writeln(
        '  float f3d_scene_depth = f3d_stored > 0.0 ? f3d_stored : '
        '$materialNothingBehind;',
      );
  }
  _statements(out, program.body, (value) => '  frag_color = ${_glsl(value)};');
  out.writeln('}');
  return out.toString();
}

/// Writes [body]'s bindings, and its return as [returns] spells it. A
/// `vertex` block's outputs are assigned to the variables that stand for
/// them.
void _statements(
  StringBuffer out,
  List<MaterialStatement> body,
  String Function(MaterialExpression value) returns,
) {
  for (final statement in body) {
    switch (statement) {
      case MaterialLet(:final name, :final value):
        out.writeln('  ${value.type.name} $name = ${_glsl(value)};');
      case MaterialReturn(:final value):
        out.writeln(returns(value));
      case MaterialOutput(:final output, :final value):
        out.writeln('  ${output.glsl} = ${_glsl(value)};');
    }
  }
}

/// What the engine may bind to [program]'s compiled shader.
///
/// **The row asks the toolchain to generate the binding metadata, and this is
/// it.** `LightingModel`'s `uses…` flags are hand-declared today, under a
/// comment saying why reflection cannot answer the question: a compiled shader
/// keeps a uniform block only if something reads it, and binding one it
/// dropped segfaults inside Metal with no Dart stack trace. A material this
/// package parsed is a different case — what it reads is written down, so the
/// flags come from the tree rather than from somebody remembering.
///
/// **And for the vertex stage, since version 2.** A material with a `vertex`
/// block brings `<name>Vertex` and `<name>VertexSkinned`, which the depth
/// pre-draw and the shadow passes draw through as well — see
/// [MaterialBindings.vertexShaderName].
///
/// For a full-screen stage or a compute kernel the answer is the uniforms
/// alone: nothing about them is a lighting model.
MaterialBindings describeMaterial(MaterialProgram program) {
  final samples = <String>{
    for (final slot in program.textures) slot.bindingName,
  };
  final reads = program.inputsUsed;
  // `P8`: a lighting hook makes it a lit model, which applies the normal,
  // occlusion and emissive maps and reads the shadows and the light list —
  // all of it live, because the parser holds the fragment body to reading
  // `lit`, which adds every one of them up.
  final lit = program.light != null;

  // A material that reads nothing off the lit surface still goes through
  // `ReadSurface`, which is what applies the base colour tint and the mask
  // cutoff — so `FragInfo` is always read and always bound, the way it is for
  // every model except `Normals`.
  return MaterialBindings(
    name: program.name,
    // Always: `ReadSurface` samples the base colour map for the albedo every
    // material reads, whether or not the source names the slot. Asked of the
    // source alone, a material that never wrote `texture` was drawn with the
    // map unbound — black on Impeller and a refused draw on WebGL2, found
    // the first time one was drawn on a GPU (`P8`, `material-language`).
    usesAlbedoTexture: true,
    usesMaterialMaps:
        lit ||
        samples.contains('normal_texture') ||
        samples.contains('occlusion_texture') ||
        samples.contains('emissive_texture') ||
        samples.contains('metallic_roughness_texture'),
    usesMetallicRoughnessMap: samples.contains('metallic_roughness_texture'),
    usesMetallic: reads.contains('metallic'),
    usesLightList: lit,
    uniforms: <String, List<double>>{
      for (final parameter in program.parameters)
        if (parameter.uniform) parameter.name: parameter.defaultValue,
    },
    kind: program.kind,
    state: program.state,
    usesSceneDepth:
        program.kind == MaterialStageKind.surface && program.readsSceneDepth,
    readsSurfaceBuffer:
        program.kind == MaterialStageKind.fullscreen &&
        program.inputsUsed.contains('sceneDepth'),
    vertexShaderName: program.vertexStageName,
  );
}

/// What [describeMaterial] found, in the shape `LightingModel` takes.
///
/// A record of the answer rather than a `LightingModel` itself, because
/// building one needs a label and a vertex stage name that are the
/// application's to choose — and because this package would otherwise decide
/// how a material is shown in a picker.
final class MaterialBindings {
  const MaterialBindings({
    required this.name,
    required this.usesAlbedoTexture,
    required this.usesMaterialMaps,
    required this.usesMetallicRoughnessMap,
    required this.usesMetallic,
    this.usesLightList = false,
    this.uniforms = const <String, List<double>>{},
    this.kind = MaterialStageKind.surface,
    this.state = MaterialFileState.none,
    this.usesSceneDepth = false,
    this.readsSurfaceBuffer = false,
    this.vertexShaderName,
  });

  final String name;

  /// What the source was — version 2. Only a surface is a lighting model.
  final MaterialStageKind kind;

  /// The source's `state` block — version 2: what
  /// `BundledMaterials.material` sets on the `RenderMaterial` it makes.
  final MaterialFileState state;

  /// Whether the fragment stage reads the scene behind it — version 2. See
  /// `LightingModel.usesSceneDepth`.
  final bool usesSceneDepth;

  /// Whether a full-screen stage reads the surface buffer, as
  /// `surface_texture` — version 2's `sceneDepth` in one. What
  /// `FullscreenEffect.readsSurface` is set from.
  final bool readsSurfaceBuffer;

  /// The vertex stage the source's `vertex` block becomes, `<name>Vertex`,
  /// or null for a material that keeps the engine's — version 2.
  final String? vertexShaderName;
  final bool usesAlbedoTexture;
  final bool usesMaterialMaps;
  final bool usesMetallicRoughnessMap;
  final bool usesMetallic;

  /// Each `uniform` the program declares, with its default, in declaration
  /// order — `P8`: the members of the `MaterialParams` block, and what
  /// `RenderMaterial.parameters` has to hold for the renderer to bind it.
  final Map<String, List<double>> uniforms;

  /// Whether the stage declares `MaterialParams`, which is whether the
  /// program has a uniform.
  bool get usesMaterialParameters => uniforms.isNotEmpty;

  /// Whether the stage gathers lights: true for a material with a `light`
  /// block — `P8` — and false for one that returns the light its surface
  /// emits, whose stage declares no light list.
  final bool usesLightList;

  /// The [LightingModel] these bindings describe, with the label and entry
  /// point the application chose.
  ///
  /// **Build the model here, not by hand.** Every flag comes off the program,
  /// [usesLightList] included, which a hand-built model gets wrong the moment
  /// the material samples a map: `LightingModel` defaults the list to its maps,
  /// the emitted stage never declares it, and the bind is a thrown "Failed to
  /// bind texture" on Impeller and a dropped draw on WebGL.
  ///
  /// [vertexShaderName] defaults to the source's own vertex stage, and a
  /// stage the language made is drawn in the depth and shadow passes too —
  /// `LightingModel.vertexStageInDepthPasses`. Naming another stage keeps
  /// those passes on the engine's, as a stage written by hand always was.
  LightingModel lightingModel({
    required String label,
    required String shaderName,
    String? vertexShaderName,
    bool vertexStageMorphs = true,
  }) {
    if (kind != MaterialStageKind.surface) {
      throw StateError(
        '"$name" is a $kind stage, and only a material is a lighting model',
      );
    }
    final vertex = vertexShaderName ?? this.vertexShaderName;
    return LightingModel(
      label,
      shaderName,
      vertexShaderName: vertex,
      usesAlbedoTexture: usesAlbedoTexture,
      usesMaterialMaps: usesMaterialMaps,
      usesMetallicRoughnessMap: usesMetallicRoughnessMap,
      usesMetallic: usesMetallic,
      usesLightList: usesLightList,
      usesMaterialParameters: usesMaterialParameters,
      vertexStageMorphs: vertexStageMorphs,
      usesSceneDepth: usesSceneDepth,
      vertexStageInDepthPasses:
          vertex != null && vertex == this.vertexShaderName,
    );
  }
}

String _glsl(MaterialExpression expression) {
  switch (expression) {
    case MaterialConstant(:final value, :final type):
      if (type == MaterialType.float) return _number(value.single);
      return '${type.name}(${value.map(_number).join(', ')})';
    case MaterialInputRef(:final input):
      return input.glsl;
    case MaterialLocalRef(:final name):
      return name;
    case MaterialParamRef(:final parameter) when parameter.uniform:
      return 'material_params.${parameter.name}';
    case MaterialParamRef(:final parameter):
      // Reachable only for a program nothing specialised, which is a caller
      // skipping a step rather than a shape this emitter supports: a
      // parameter has no GLSL, because it is not a uniform.
      throw StateError(
        'The parameter "${parameter.name}" has no value. Call '
        'specialiseMaterial before emitting.',
      );
    case MaterialConstruct(:final arguments, :final type):
      return '${type.name}(${arguments.map(_glsl).join(', ')})';
    case MaterialSwizzle(:final target, :final components):
      const letters = 'xyzw';
      final field = components.map((i) => letters[i]).join();
      return '${_glsl(target)}.$field';
    case MaterialNegate(:final operand):
      return '-(${_glsl(operand)})';
    case MaterialBinary(:final op, :final left, :final right):
      // Fully parenthesised rather than tracking precedence a second time:
      // the parser already decided the shape, and an emitter that re-derived
      // it could put the brackets somewhere the tree does not mean.
      return '(${_glsl(left)} $op ${_glsl(right)})';
    case MaterialCall(:final builtin, :final arguments):
      // The language spreads a float beside a vector for every component-wise
      // builtin, and `broadcastArguments` evaluates it that way; GLSL does only
      // for some positions of some of them — `pow(vec3, float)`,
      // `mix(float, vec3, float)` and `min(float, vec3)` do not compile. So the
      // spread is written out, which every overload accepts and which says
      // what the software backend computes.
      var width = 1;
      for (final argument in arguments) {
        if (argument.type.components > width) width = argument.type.components;
      }
      String spread(MaterialExpression argument) {
        final text = _glsl(argument);
        return builtin.componentWise &&
                width > 1 &&
                argument.type.components == 1
            ? '${MaterialType.numeric[width]!.name}($text)'
            : text;
      }

      return '${builtin.glsl}(${arguments.map(spread).join(', ')})';
    case MaterialSample(:final slot, :final uv):
      return 'texture(${slot.bindingName}, ${_glsl(uv)})';
  }
}

/// A GLSL float literal, which always has a decimal point.
///
/// `2` is an `int` in GLSL, and `pow(x, 2)` fails to compile against a
/// `pow(float, float)` overload — a whole number reaching the shader without
/// its point is the classic way a generated shader stops building.
String _number(double value) {
  if (!value.isFinite) {
    throw ArgumentError('$value cannot be written as a GLSL literal.');
  }
  final text = value.toString();
  return text.contains('.') || text.contains('e') ? text : '$text.0';
}
