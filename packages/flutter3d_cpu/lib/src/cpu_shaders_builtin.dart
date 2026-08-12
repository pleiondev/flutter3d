/// The engine's shaders, written in Dart.
///
/// Every name the engine asks for is answered, and a handful are answered
/// properly. The rest throw when used rather than drawing something plausible:
/// a backend that quietly substitutes is the failure mode this whole project
/// keeps finding, and one that admits it cannot do a thing is worth more than
/// one that draws grey where the picture should be lit.
///
/// Implemented for real: the mesh vertex stage, Unlit, Lambert, the fullscreen
/// triangle and the composite. Between them they draw a lit scene and tone map
/// it, which is the `plain` parity fixture — the smallest thing that can be
/// compared against another backend and mean something.
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
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';

/// Where each attribute sits in the sixteen floats the engine lays out.
///
/// From `mesh.vert`'s `in` declarations, which are what define the layout —
/// repeated here rather than imported because this package does not depend on
/// the engine, and a backend that needed the engine to compile would not be a
/// backend. `VertexLayout.standard` is the Dart side of the same list.
const int _position = 0; // vec3
const int _normal = 3; // vec3
const int _texcoord = 6; // vec2
// tangent is at 8 (vec4) and nothing here reads it.
const int _colour = 12; // vec4

/// The varyings this backend's mesh stage carries.
///
/// `mesh.vert` also passes the tangent, which only the normal-mapped models
/// use and none of the ones written here do.
const int _vWorld = 0; // vec3
const int _vNormal = 3; // vec3
const int _vUv = 6; // vec2
const int _vColour = 8; // vec4
const int _meshVaryings = 12;

/// Lights per frame, from `kMaxLights` in `surface.glsl`.
const int _maxLights = 8;

/// sRGB to linear, per `color.glsl`.
double _toLinear(double c) =>
    c < 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

/// Linear to sRGB, the inverse.
double _toSrgb(double c) => c < 0.0031308
    ? c * 12.92
    : 1.055 * math.pow(math.max(c, 0.0), 1.0 / 2.4) - 0.055;

/// The mesh vertex stage — `mesh.vert`.
final class MeshVertexShader implements CpuVertexShader {
  const MeshVertexShader();

  @override
  int get varyingCount => _meshVaryings;

  @override
  Vector4 run(Float32List a, ShaderBindings bindings, Float32List out) {
    final mvp = bindings.mat4('FrameInfo', 'mvp');
    final model = bindings.mat4('FrameInfo', 'model');
    final normalMatrix = bindings.mat4('FrameInfo', 'normal_matrix');

    final local = Vector4(a[_position], a[_position + 1], a[_position + 2], 1.0);
    final world = model * local;
    out[_vWorld] = world.x;
    out[_vWorld + 1] = world.y;
    out[_vWorld + 2] = world.z;

    // `mat3(normal_matrix) * normal`: the upper-left three by three, so the
    // translation does not move a direction.
    final n = normalMatrix.getRotation() *
        Vector3(a[_normal], a[_normal + 1], a[_normal + 2]);
    out[_vNormal] = n.x;
    out[_vNormal + 1] = n.y;
    out[_vNormal + 2] = n.z;

    out[_vUv] = a[_texcoord];
    out[_vUv + 1] = a[_texcoord + 1];
    for (var i = 0; i < 4; i++) {
      out[_vColour + i] = a[_colour + i];
    }

    return mvp * local;
  }
}

/// What `ReadSurface` produces, for the models that need more than the albedo.
final class _Surface {
  _Surface(this.albedo, this.alpha, this.normal, this.world, this.ambient);
  final Vector3 albedo;
  final double alpha;
  final Vector3 normal;
  final Vector3 world;
  final double ambient;
}

/// `ReadSurface` from `surface.glsl`.
///
/// Alpha masking is not here: `material2.x` is negative for every material the
/// fixtures use, and a discard nothing exercises would be a guess.
_Surface _readSurface(Float32List v, ShaderBindings bindings) {
  final tint = bindings.vec4('FragInfo', 'base_color', Vector4(1, 1, 1, 1));
  final texture = bindings.textures['base_color_texture'];
  final texel =
      texture == null ? Vector4(1, 1, 1, 1) : texture.sample(v[_vUv], v[_vUv + 1]);

  // Texture and tint are sRGB; the vertex colour is authored linear, per glTF.
  final albedo = Vector3(
    _toLinear(texel.x) * _toLinear(tint.x) * v[_vColour],
    _toLinear(texel.y) * _toLinear(tint.y) * v[_vColour + 1],
    _toLinear(texel.z) * _toLinear(tint.z) * v[_vColour + 2],
  );
  final alpha = texel.w * tint.w * v[_vColour + 3];

  final normal = Vector3(v[_vNormal], v[_vNormal + 1], v[_vNormal + 2]);
  final length = normal.length;
  if (length > 1e-6) normal.scale(1.0 / length);

  final material = bindings.vec4('FragInfo', 'material', Vector4.zero());
  return _Surface(
    albedo,
    alpha,
    normal,
    Vector3(v[_vWorld], v[_vWorld + 1], v[_vWorld + 2]),
    material.z,
  );
}

/// `LightCount()`: the count lives in `frame_params.y`, not in a member of its
/// own. Reading a member that does not exist is silent, which is how the first
/// version of this file drew an unlit scene.
int _lightCount(ShaderBindings bindings) {
  final params = bindings.vec4('FragInfo', 'frame_params', Vector4.zero());
  return (params.y + 0.5).floor().clamp(0, _maxLights);
}

/// `PunctualAttenuation`: inverse square with glTF's range window.
double _attenuation(double distance, double range) {
  var attenuation = 1.0 / math.max(distance * distance, 1e-4);
  if (range > 0.0) {
    final ratio = distance / range;
    final window = (1.0 - ratio * ratio * ratio * ratio).clamp(0.0, 1.0);
    attenuation *= window * window;
  }
  return attenuation;
}

/// `SampleLight`, reduced to what a diffuse model uses.
///
/// Returns null for a light that contributes nothing, which is the `n_dot_l <=
/// 0` early-out in `AccumulateLights`.
({Vector3 radiance, double nDotL})? _sampleLight(
    ShaderBindings bindings, int index, _Surface s) {
  final position =
      bindings.vec4('FragInfo', 'light_position', Vector4.zero(), at: index);
  final colour =
      bindings.vec4('FragInfo', 'light_color', Vector4.zero(), at: index);
  final direction =
      bindings.vec4('FragInfo', 'light_direction', Vector4.zero(), at: index);

  final aim = Vector3(direction.x, direction.y, direction.z);
  final aimLength = aim.length;
  if (aimLength > 1e-6) aim.scale(1.0 / aimLength);

  Vector3 toLight;
  var attenuation = 1.0;
  if (position.w < 0.5) {
    // Directional: the direction to the light is the reverse of the one it
    // points.
    toLight = -aim;
  } else {
    toLight = Vector3(position.x, position.y, position.z) - s.world;
    final distance = toLight.length;
    if (distance < 1e-6) return null;
    toLight.scale(1.0 / distance);
    attenuation = _attenuation(distance, direction.w);
    // Spot cones are not here. Nothing this backend draws has one, and the
    // conformance suite does not ask; a cone written blind would be another
    // guess of the kind this file was rewritten to remove.
  }

  final nDotL = math.max(s.normal.dot(toLight), 0.0);
  if (nDotL <= 0.0) return null;
  return (
    radiance: Vector3(colour.x, colour.y, colour.z) * (colour.w * attenuation),
    nDotL: nDotL,
  );
}

/// `unlit.frag`: the albedo, written into the HDR target as light.
final class UnlitShader implements CpuFragmentShader {
  const UnlitShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings) {
    final s = _readSurface(v, bindings);
    return Vector4(s.albedo.x, s.albedo.y, s.albedo.z, s.alpha);
  }
}

/// `lambert.frag`: `AccumulateLights` with an albedo response, plus ambient.
///
/// No shadow term. `LightVisibility` in the real shader calls `ShadowFactor`,
/// and this backend has no shadow pass — so a scene with shadows on would be
/// lit through its occluders here. That is why the fixture this is checked
/// against is `plain`, and why the shadow entry points below refuse rather
/// than returning one.
final class LambertShader implements CpuFragmentShader {
  const LambertShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings) {
    final s = _readSurface(v, bindings);

    var total = Vector3.zero();
    final count = _lightCount(bindings);
    for (var i = 0; i < count; i++) {
      final light = _sampleLight(bindings, i, s);
      if (light == null) continue;
      // ShadeLight returns the albedo; the radiance and N.L are applied here,
      // as AccumulateLights does.
      total += Vector3(
        s.albedo.x * light.radiance.x,
        s.albedo.y * light.radiance.y,
        s.albedo.z * light.radiance.z,
      )..scale(light.nDotL);
    }

    // Occlusion is one and emissive zero: no ORM map, which is what
    // `lambert.frag` says in as many words.
    final lit = total + s.albedo * s.ambient;
    return Vector4(lit.x, lit.y, lit.z, s.alpha);
  }
}

/// `fullscreen.vert`.
///
/// The uv is an attribute, not something derived from the position. Deriving
/// it — which the first version did — puts the composite's sampling a flip
/// away from the engine's on any backend whose framebuffer disagrees, and
/// there is no way to see that in a fixture whose picture is roughly
/// symmetric.
final class FullscreenVertexShader implements CpuVertexShader {
  const FullscreenVertexShader();

  @override
  int get varyingCount => 2;

  @override
  Vector4 run(Float32List a, ShaderBindings bindings, Float32List out) {
    out[0] = a[2];
    out[1] = a[3];
    return Vector4(a[0], a[1], 0.0, 1.0);
  }
}

/// The Khronos PBR Neutral tone mapper, from `composite.frag`.
///
/// Transcribed rather than replaced with something simpler: this is the one
/// part of the chain that is pure arithmetic on a colour, so a Reinhard curve
/// here would make every cell of the comparison differ for a reason that has
/// nothing to do with the backend.
Vector3 _tonemapNeutral(Vector3 colour) {
  const startCompression = 0.8 - 0.04;
  const desaturation = 0.15;

  final minChannel = math.min(colour.x, math.min(colour.y, colour.z));
  final offset =
      minChannel < 0.08 ? minChannel - 6.25 * minChannel * minChannel : 0.04;
  final c = Vector3(colour.x - offset, colour.y - offset, colour.z - offset);

  final peak = math.max(c.x, math.max(c.y, c.z));
  if (peak < startCompression) return c;

  const d = 1.0 - startCompression;
  final newPeak = 1.0 - d * d / (peak + d - startCompression);
  c.scale(newPeak / peak);

  final desaturate = 1.0 - 1.0 / (desaturation * (peak - newPeak) + 1.0);
  return Vector3(
    c.x + (newPeak - c.x) * desaturate,
    c.y + (newPeak - c.y) * desaturate,
    c.z + (newPeak - c.z) * desaturate,
  );
}

/// `composite.frag`: add the bloom, expose, tone map, encode.
final class CompositeShader implements CpuFragmentShader {
  const CompositeShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings) {
    final scene = bindings.textures['scene_texture'];
    if (scene == null) return Vector4(0.0, 0.0, 0.0, 1.0);
    final params =
        bindings.vec4('CompositeInfo', 'params', Vector4(1.0, 0.0, 1.0, 0.0));

    final sampled = scene.sample(v[0], v[1]);
    var colour = Vector3(sampled.x, sampled.y, sampled.z);

    // Additive, and unconditional: the engine binds a black texture when bloom
    // is off rather than leaving the sampler unbound, so there is no branch to
    // make here either.
    final bloom = bindings.textures['bloom_texture'];
    if (bloom != null) {
      final b = bloom.sample(v[0], v[1]);
      colour += Vector3(b.x, b.y, b.z) * params.y;
    }

    colour.scale(math.max(params.x, 0.0));
    if (params.z > 0.5) colour = _tonemapNeutral(colour);

    return Vector4(
        _toSrgb(colour.x), _toSrgb(colour.y), _toSrgb(colour.z), sampled.w);
  }
}

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
  Vector4 run(Float32List a, ShaderBindings b, [Float32List? out]) =>
      throw UnsupportedError(
        '$name is not written in Dart. This backend answers to every name the '
        'engine asks for so that it can start, and refuses the ones it cannot '
        'draw rather than drawing something else.',
      );
}

/// Every stage, by the name the engine uses.
Map<String, CpuStage> builtinCpuShaders() {
  final stages = <String, CpuStage>{
    'MeshVertex': const CpuStage.vertex(MeshVertexShader()),
    'FullscreenVertex': const CpuStage.vertex(FullscreenVertexShader()),
    'Unlit': const CpuStage.fragment(UnlitShader()),
    'Lambert': const CpuStage.fragment(LambertShader()),
    'Composite': const CpuStage.fragment(CompositeShader()),
  };

  // The rest, present and refusing. Named individually rather than generated
  // from `kRequiredShaders`, so a shader added to the engine breaks this list
  // rather than silently acquiring a stub — `test/shader_names_test.dart`
  // pins that in both directions.
  const vertexGaps = <String>[
    'MeshSkinnedVertex',
    'DebugLineVertex',
    'ParticleVertex',
    'ShadowTileResetVertex',
  ];
  const fragmentGaps = <String>[
    'BlinnPhong',
    'Pbr',
    'Toon',
    'Normals',
    'DebugLine',
    'Particle',
    'BloomThreshold',
    'BloomDownsample',
    'BloomUpsample',
    'Reflections',
    'MrtProbe',
    'ShadowDepth',
    'ShadowDistance',
    'ShadowTileReset',
  ];
  for (final name in vertexGaps) {
    stages[name] = CpuStage.vertex(_Unimplemented(name));
  }
  for (final name in fragmentGaps) {
    stages[name] = CpuStage.fragment(_Unimplemented(name));
  }
  return stages;
}
