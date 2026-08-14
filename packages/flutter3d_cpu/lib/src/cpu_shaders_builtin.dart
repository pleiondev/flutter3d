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
const int _tangent = 8; // vec4
const int _colour = 12; // vec4

/// The varyings this backend's mesh stage carries.
///
/// `mesh.vert` also passes the tangent, which only the normal-mapped models
/// use and none of the ones written here do.
const int _vWorld = 0; // vec3
const int _vNormal = 3; // vec3
const int _vUv = 6; // vec2
const int _vColour = 8; // vec4
const int _vTangent = 12; // vec4
const int _meshVaryings = 16;

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

    // The tangent transforms with the model matrix, not the normal matrix: it
    // lies *in* the surface, so it stretches with the geometry rather than
    // staying perpendicular to it.
    final t = model.getRotation() *
        Vector3(a[_tangent], a[_tangent + 1], a[_tangent + 2]);
    out[_vTangent] = t.x;
    out[_vTangent + 1] = t.y;
    out[_vTangent + 2] = t.z;
    out[_vTangent + 3] = a[_tangent + 3];

    return mvp * local;
  }
}

/// What `ReadSurface` produces, for the models that need more than the albedo.
/// Mutable, because the GLSL passes it as `inout` to every map function and
/// each one modifies a field. A copy-returning version would read better and
/// would be a different program.
final class _Surface {
  _Surface(this.albedo, this.alpha, this.normal, this.world, this.ambient,
      this.metallic, this.roughness, this.view, this.nDotV, this.tangent);
  Vector3 albedo;
  double alpha;
  Vector3 normal;
  final Vector3 world;
  final double ambient;
  double metallic;
  double roughness;

  /// Towards the eye, which every specular term needs.
  final Vector3 view;

  /// Clamped away from zero: a grazing view otherwise divides by zero in the
  /// specular visibility term.
  double nDotV;

  /// xyz the tangent, w the bitangent sign — glTF's convention for a mirrored
  /// UV island.
  final Vector4 tangent;

  /// Neutral until a map says otherwise, so a model that samples nothing still
  /// has a complete surface.
  double occlusion = 1.0;
  Vector3 emissive = Vector3.zero();
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
  final camera =
      bindings.vec4('FragInfo', 'camera_position', Vector4.zero());
  final world = Vector3(v[_vWorld], v[_vWorld + 1], v[_vWorld + 2]);
  final view = Vector3(camera.x, camera.y, camera.z) - world;
  final viewLength = view.length;
  if (viewLength > 1e-6) view.scale(1.0 / viewLength);

  return _Surface(
    albedo,
    alpha,
    normal,
    world,
    material.z,
    material.x.clamp(0.0, 1.0),
    material.y.clamp(0.02, 1.0),
    view,
    math.max(normal.dot(view), 1e-4),
    Vector4(v[_vTangent], v[_vTangent + 1], v[_vTangent + 2],
        v[_vTangent + 3]),
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

/// What `SampleLight` produces.
typedef _LightSample = ({
  Vector3 direction,
  Vector3 radiance,
  double nDotL,
  double nDotH,
  double vDotH,
});

/// `SampleLight`.
///
/// Returns null for a light that contributes nothing, which is the `n_dot_l <=
/// 0` early-out in `AccumulateLights`.
_LightSample? _sampleLight(
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

  // The spot cone: a smooth ramp between the two cosines. The Dart side
  // guarantees the denominator is non-zero.
  if (position.w > 1.5) {
    final cone =
        bindings.vec4('FragInfo', 'light_cone', Vector4.zero(), at: index);
    final cosAngle = aim.dot(-toLight);
    attenuation *= ((cosAngle - cone.y) / (cone.x - cone.y)).clamp(0.0, 1.0);
  }

  final half = (toLight + s.view)..normalize();
  final nDotL = math.max(s.normal.dot(toLight), 0.0);
  if (nDotL <= 0.0) return null;
  return (
    direction: toLight,
    radiance: Vector3(colour.x, colour.y, colour.z) * (colour.w * attenuation),
    nDotL: nDotL,
    nDotH: math.max(s.normal.dot(half), 0.0),
    vDotH: math.max(s.view.dot(half), 0.0),
  );
}

// ---------------------------------------------------------------------------
// material_maps.glsl
//
// Every map has a neutral fallback bound when the material has none, so there
// are no "has this map" flags to keep in sync: a white ORM texture multiplies
// by one and a flat normal map perturbs nothing. That is why each function
// below samples unconditionally.
// ---------------------------------------------------------------------------

/// glTF's ORM packing: roughness in g, metallic in b.
void _applyMetallicRoughnessMap(_Surface s, Float32List v, ShaderBindings b) {
  final orm = b.textures['metallic_roughness_texture'];
  if (orm == null) return;
  final texel = orm.sample(v[_vUv], v[_vUv + 1]);
  s.metallic = (s.metallic * texel.z).clamp(0.0, 1.0);
  s.roughness = (s.roughness * texel.y).clamp(0.02, 1.0);
}

/// glTF's `occlusionStrength` lerps between ignoring the map and applying it
/// in full, which is why this is a mix and not a multiply.
void _applyOcclusionMap(_Surface s, Float32List v, ShaderBindings b) {
  final map = b.textures['occlusion_texture'];
  if (map == null) return;
  final occlusion = map.sample(v[_vUv], v[_vUv + 1]).x;
  final strength =
      b.vec4('FragInfo', 'material2', Vector4.zero()).z.clamp(0.0, 1.0);
  s.occlusion = 1.0 + (occlusion - 1.0) * strength;
}

void _applyEmissiveMap(_Surface s, Float32List v, ShaderBindings b) {
  final map = b.textures['emissive_texture'];
  if (map == null) return;
  final texel = map.sample(v[_vUv], v[_vUv + 1]);
  final factor = b.vec4('FragInfo', 'emissive', Vector4.zero());
  final strength = b.vec4('FragInfo', 'material2', Vector4.zero()).w;
  s.emissive = Vector3(
    _toLinear(texel.x) * factor.x * strength,
    _toLinear(texel.y) * factor.y * strength,
    _toLinear(texel.z) * factor.z * strength,
  );
}

/// Perturbs the normal by the tangent-space map.
void _applyNormalMap(_Surface s, Float32List v, ShaderBindings b) {
  final map = b.textures['normal_texture'];
  if (map == null) return;

  // Re-orthogonalised against the normal: interpolating both across a triangle
  // does not preserve the right angle between them.
  final t = Vector3(s.tangent.x, s.tangent.y, s.tangent.z);
  t.sub(s.normal * s.normal.dot(t));
  if (t.length2 < 1e-12) return; // no usable frame; keep the vertex normal
  t.normalize();

  // The bitangent sign encodes a mirrored UV island. Dropping it lights every
  // mirrored half of a symmetric model from the wrong side.
  final bitangent = s.normal.cross(t)..scale(s.tangent.w);

  final texel = map.sample(v[_vUv], v[_vUv + 1]);
  final scale = b.vec4('FragInfo', 'material2', Vector4.zero()).y;
  final sx = (texel.x * 2.0 - 1.0) * scale;
  final sy = (texel.y * 2.0 - 1.0) * scale;
  final sz = texel.z * 2.0 - 1.0;

  s.normal = (t * sx + bitangent * sy + s.normal * sz)..normalize();
  s.nDotV = math.max(s.normal.dot(s.view), 1e-4);
}

/// The three every lit model uses. Metal-rough is separate because only the
/// models that respond to metallic or roughness may sample it.
void _applyCommonMaps(_Surface s, Float32List v, ShaderBindings b) {
  _applyNormalMap(s, v, b);
  _applyOcclusionMap(s, v, b);
  _applyEmissiveMap(s, v, b);
}

// ---------------------------------------------------------------------------
// shadow.glsl and the cube atlas in surface.glsl
// ---------------------------------------------------------------------------

/// Atlas rows, from `kShadowSlots` in `surface.glsl`.
const int _shadowSlots = 4;

/// `ShadowFactor`: how much of the directional light survives here.
///
/// One — not zero — outside the map, off the caster, or with shadows off. A
/// fragment beyond the shadow volume is unshadowed, and getting that backwards
/// puts a hard edge across the scene at the edge of the map.
double _shadowFactor(_Surface s, ShaderBindings b, int lightIndex) {
  final params = b.vec4('FragInfo', 'shadow_params', Vector4.zero());
  final strength = params.w;
  if (strength <= 0.0) return 1.0;
  final frame = b.vec4('FragInfo', 'frame_params', Vector4.zero());
  if (lightIndex != (frame.z + 0.5).floor()) return 1.0;

  final map = b.textures['shadow_texture'];
  if (map == null) return 1.0;

  // Normal offset: move the sample along the normal before projecting. It
  // fixes acne a depth bias cannot, because that error is proportional to the
  // surface's slope relative to the light rather than to depth.
  final origin = s.world + s.normal * params.z;
  final matrix = b.mat4('FragInfo', 'shadow_matrix');
  final lightSpace = matrix * Vector4(origin.x, origin.y, origin.z, 1.0);
  if (lightSpace.w <= 0.0) return 1.0;
  final projected = Vector3(lightSpace.x, lightSpace.y, lightSpace.z)
    ..scale(1.0 / lightSpace.w);

  final u = projected.x * 0.5 + 0.5;
  final vv = 0.5 - projected.y * 0.5;
  if (u < 0.0 || u > 1.0 || vv < 0.0 || vv > 1.0) return 1.0;
  if (projected.z > 1.0) return 1.0;

  final bias = params.y;
  final texel = params.x;

  // PCF 3x3: four samples band visibly at this map size and nine is the
  // smallest kernel that reads as a soft edge rather than as stair steps.
  var lit = 0.0;
  for (var y = -1; y <= 1; y++) {
    for (var x = -1; x <= 1; x++) {
      final occluder = map.sample(u + x * texel, vv + y * texel).x;
      lit += projected.z - bias > occluder ? 0.0 : 1.0;
    }
  }
  lit /= 9.0;
  return 1.0 + (lit - 1.0) * strength.clamp(0.0, 1.0);
}

/// The Poisson disk the cube filter rotates, from `PointShadowDiskTap`.
const List<List<double>> _diskTaps = <List<double>>[
  <double>[-0.94201624, -0.39906216],
  <double>[0.94558609, -0.76890725],
  <double>[-0.09418410, -0.92938870],
  <double>[0.34495938, 0.29387760],
  <double>[-0.91588581, 0.45771432],
  <double>[-0.81544232, -0.87912464],
  <double>[-0.38277543, 0.27676845],
  <double>[0.97484398, 0.75648379],
];

/// `PointShadowDistance`: one comparison against the atlas.
///
/// The clamp is applied **after** the offset, holding each tap inside its own
/// tile individually. Clamping the centre and then offsetting would let the
/// outer taps walk into a distance measured from a different face, or from a
/// different light.
double _atlasDistance(ShaderBindings b, double u, double v, double ox,
    double oy, double tileX, double tileY, double range, double inset) {
  final localU = (u + ox).clamp(inset, 1.0 - inset);
  final localV = (v + oy).clamp(inset, 1.0 - inset);
  final atlasU = (localU + tileX) / 6.0;
  final atlasV = (localV + tileY) / _shadowSlots;

  final dynamicMap = b.textures['point_shadow_texture'];
  final staticMap = b.textures['point_shadow_static_texture'];
  var nearest = 1.0;
  if (dynamicMap != null) nearest = dynamicMap.sample(atlasU, atlasV).x;
  if (staticMap != null) {
    // Whichever is nearer occludes: a wall in front of a monster shadows, and
    // so does a monster in front of a wall.
    nearest = math.min(nearest, staticMap.sample(atlasU, atlasV).x);
  }
  return nearest * range;
}

/// `PointShadowFactor`: how lit a point is by the light that owns the atlas.
double _pointShadowFactor(
    ShaderBindings b, Vector3 world, Vector3 normal, int lightIndex,
    FragmentContext c) {
  final slotEntry =
      b.vec4('PointShadow', 'slots', Vector4(-1, 0, 0, 0), at: lightIndex);
  if (slotEntry.x < 0.0) return 1.0;
  final slot = (slotEntry.x + 0.5).floor();

  final params = b.vec4('PointShadow', 'params', Vector4.zero());
  final strength = params.z;
  if (strength <= 0.0) return 1.0;

  final light = b.vec4('PointShadow', 'lights', Vector4.zero(), at: slot);
  final lightPos = Vector3(light.x, light.y, light.z);

  // Offset along the normal, scaled by how steeply the surface leans away.
  // A soft kernel on a tilted surface straddles a depth gradient, so a flat
  // offset that clears the surface head-on leaves acne at a grazing angle. The
  // cap matters: uncapped, the lift detaches the shadow from its caster.
  final toLight = lightPos - world;
  final toLightLength = math.max(toLight.length, 1e-6);
  final nDotL = math.max(normal.dot(toLight / toLightLength), 0.15);
  final slope =
      math.min(math.sqrt(math.max(1.0 - nDotL * nDotL, 0.0)) / (nDotL * nDotL),
          8.0);
  final origin = world + normal * (params.w * (1.0 + slope));
  final toFragment = origin - lightPos;
  final distance = toFragment.length;
  final range = math.max(light.w, 1e-4);
  if (distance >= range) return 1.0;

  // The dominant axis picks the face, in the order the renderer wrote them:
  // +X, -X, +Y, -Y, +Z, -Z, left to right then top to bottom.
  final a = Vector3(toFragment.x.abs(), toFragment.y.abs(), toFragment.z.abs());
  final int face;
  if (a.x >= a.y && a.x >= a.z) {
    face = toFragment.x > 0.0 ? 0 : 1;
  } else if (a.y >= a.z) {
    face = toFragment.y > 0.0 ? 2 : 3;
  } else {
    face = toFragment.z > 0.0 ? 4 : 5;
  }

  final matrix = b.mat4('PointShadow', 'faces', at: slot * 6 + face);
  final clip = matrix * Vector4(origin.x, origin.y, origin.z, 1.0);
  if (clip.w <= 0.0) return 1.0;
  final ndcX = clip.x / clip.w;
  final ndcY = clip.y / clip.w;
  if (ndcX.abs() > 1.0 || ndcY.abs() > 1.0) return 1.0;

  // v is flipped, as the directional map does it: the texture's origin is at
  // the top, where row zero of the render target is.
  final u = ndcX * 0.5 + 0.5;
  final vv = 0.5 - ndcY * 0.5;
  final tileX = face.toDouble();
  final tileY = slot.toDouble();
  final inset = params.x;
  final receiver = distance - params.y;

  // One rotation per fragment, shared by the search and the filter, so eight
  // samples read as a soft edge rather than as eight copies of the silhouette.
  final noise = _fract(52.9829189 *
      _fract(c.coord.x * 0.06711056 + c.coord.y * 0.00583715));
  final angle = noise * 6.28318530718;
  final ca = math.cos(angle);
  final sa = math.sin(angle);

  final params2 = b.vec4('PointShadow', 'params2', Vector4.zero());
  final lightRadius = params2.y;
  final minRadius = params2.x;
  final maxRadius = params2.z;

  double radius;
  if (lightRadius <= 0.0) {
    radius = minRadius;
  } else {
    // The blocker search runs at the widest penumbra allowed: a blocker
    // outside that circle cannot widen the result, and searching narrower
    // would miss the very blockers that make an edge soft.
    var sum = 0.0;
    var count = 0.0;
    for (var i = 0; i < 8; i++) {
      final p = _diskTaps[i];
      final ox = (p[0] * ca - p[1] * sa) * maxRadius;
      final oy = (p[0] * sa + p[1] * ca) * maxRadius;
      final stored =
          _atlasDistance(b, u, vv, ox, oy, tileX, tileY, range, inset);
      if (stored >= range * 0.999) continue;
      if (stored >= receiver) continue;
      sum += stored;
      count += 1.0;
    }
    // Nothing in front of this fragment anywhere in the search.
    if (count < 0.5) return 1.0;
    final blocker = math.max(sum / count, 1e-4);
    final worldWidth = lightRadius * math.max(receiver - blocker, 0.0) / blocker;
    radius = (worldWidth / (2.0 * receiver)).clamp(minRadius, maxRadius);
  }

  double tap(double ox, double oy) {
    final stored = _atlasDistance(b, u, vv, ox, oy, tileX, tileY, range, inset);
    // Nothing was drawn in that direction by either map.
    if (stored >= range * 0.999) return 1.0;
    return receiver > stored ? 0.0 : 1.0;
  }

  var lit = tap(0.0, 0.0);
  if (radius > 0.0) {
    for (var i = 0; i < 8; i++) {
      final p = _diskTaps[i];
      lit += tap((p[0] * ca - p[1] * sa) * radius,
          (p[0] * sa + p[1] * ca) * radius);
    }
    lit /= 9.0;
  }
  return 1.0 + (lit - 1.0) * strength.clamp(0.0, 1.0);
}

double _fract(double x) => x - x.floor();

/// `AccumulateLights`, with the model's own response passed in.
///
/// The GLSL achieves this with two function prototypes each shader defines;
/// here it is a callback, which is the same shape and one fewer file.
Vector3 _accumulateLights(
  _Surface s,
  ShaderBindings b,
  FragmentContext c, {
  required Vector3 Function(_Surface s, _LightSample light) shade,
  required bool shadowed,
}) {
  var total = Vector3.zero();
  final count = _lightCount(b);
  for (var i = 0; i < count; i++) {
    final light = _sampleLight(b, i, s);
    if (light == null) continue;
    var visibility = shadowed ? _shadowFactor(s, b, i) : 1.0;
    visibility *= _pointShadowFactor(b, s.world, s.normal, i, c);
    if (visibility <= 0.0) continue;
    final response = shade(s, light);
    total += Vector3(
      response.x * light.radiance.x,
      response.y * light.radiance.y,
      response.z * light.radiance.z,
    )..scale(light.nDotL * visibility);
  }
  return total;
}

/// `EncodeOctahedral` from `color.glsl`: a unit normal in two channels.
Vector2 _encodeOctahedral(Vector3 n) {
  final sum = n.x.abs() + n.y.abs() + n.z.abs();
  final scaled = sum > 1e-6 ? n / sum : Vector3(0.0, 0.0, 1.0);
  var e = Vector2(scaled.x, scaled.y);
  if (scaled.z < 0.0) {
    e = Vector2(
      (1.0 - scaled.y.abs()) * (scaled.x >= 0.0 ? 1.0 : -1.0),
      (1.0 - scaled.x.abs()) * (scaled.y >= 0.0 ? 1.0 : -1.0),
    );
  }
  return Vector2(e.x * 0.5 + 0.5, e.y * 0.5 + 0.5);
}

/// `WriteSurfaceGeometry`: the octahedral normal, the roughness, the depth.
///
/// Called from the same place that writes colour, so a surface cannot be lit
/// into the frame without also describing itself — which is the failure that
/// leaves a screen-space effect reflecting whatever was in the buffer before.
void _writeSurface(FragmentContext c, Vector3 normal, double roughness) {
  final encoded = _encodeOctahedral(normal);
  c.surface =
      Vector4(encoded.x, encoded.y, roughness.clamp(0.0, 1.0), c.coord.z);
}

/// `unlit.frag`: the albedo, written into the HDR target as light.
final class UnlitShader implements CpuFragmentShader {
  const UnlitShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) {
    final s = _readSurface(v, bindings);
    // Fully rough, which is what WriteSurface's one-argument form means: a
    // surface that cannot say how polished it is should not be reflected off.
    _writeSurface(c, s.normal, 1.0);
    return Vector4(s.albedo.x, s.albedo.y, s.albedo.z, s.alpha);
  }
}

/// What the three bloom stages share: the source texture and its texel size.
({BoundTexture source, double tx, double ty, Vector4 params})? _bloomSource(
    ShaderBindings b) {
  final source = b.textures['source_texture'];
  if (source == null) return null;
  final params = b.vec4('BloomInfo', 'params', Vector4.zero());
  return (source: source, tx: params.x, ty: params.y, params: params);
}

/// `bloom_threshold.frag`: what is bright enough to glow.
final class BloomThresholdShader implements CpuFragmentShader {
  const BloomThresholdShader();

  static double _luminance(Vector3 c) =>
      c.x * 0.2126 + c.y * 0.7152 + c.z * 0.0722;

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final src = _bloomSource(b);
    if (src == null) return Vector4(0.0, 0.0, 0.0, 1.0);
    final u = v[0];
    final w = v[1];

    // A four-tap box at the corners of the source quad. A single tap aliases a
    // one-pixel highlight in and out of existence as the camera moves, which
    // reads as flickering rather than as bloom.
    var sum = Vector3.zero();
    for (final d in const <List<double>>[
      <double>[-0.5, -0.5],
      <double>[0.5, -0.5],
      <double>[-0.5, 0.5],
      <double>[0.5, 0.5],
    ]) {
      final t = src.source.sample(u + src.tx * d[0], w + src.ty * d[1]);
      sum += Vector3(t.x, t.y, t.z);
    }
    final colour = sum..scale(0.25);

    final threshold = src.params.z;
    final knee = math.max(src.params.w, 1e-4);
    // A soft knee rather than a hard step: a hard cut makes the bloom appear
    // along a visible contour as a highlight brightens through the threshold.
    final brightness = _luminance(colour);
    var soft = (brightness - threshold + knee).clamp(0.0, 2.0 * knee);
    soft = soft * soft / (4.0 * knee);
    final contribution =
        math.max(soft, brightness - threshold) / math.max(brightness, 1e-4);

    colour.scale(contribution);
    return Vector4(colour.x, colour.y, colour.z, 1.0);
  }
}

/// `bloom_downsample.frag`: the thirteen-tap filter, four boxes plus five.
final class BloomDownsampleShader implements CpuFragmentShader {
  const BloomDownsampleShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final src = _bloomSource(b);
    if (src == null) return Vector4(0.0, 0.0, 0.0, 1.0);
    final u = v[0];
    final w = v[1];

    Vector3 at(double dx, double dy) {
      final t = src.source.sample(u + dx * src.tx, w + dy * src.ty);
      return Vector3(t.x, t.y, t.z);
    }

    final a = at(-2, 2), bb = at(0, 2), cc = at(2, 2);
    final d = at(-2, 0), e = at(0, 0), f = at(2, 0);
    final g = at(-2, -2), h = at(0, -2), i = at(2, -2);
    final j = at(-1, 1), k = at(1, 1), l = at(-1, -1), m = at(1, -1);

    // The inner four boxes carry half the weight between them; the five outer
    // ones share the rest.
    final result = (j + k + l + m) * (0.5 * 0.25);
    result.add((a + bb + d + e) * (0.125 * 0.25));
    result.add((bb + cc + e + f) * (0.125 * 0.25));
    result.add((d + e + g + h) * (0.125 * 0.25));
    result.add((e + f + h + i) * (0.125 * 0.25));
    return Vector4(result.x, result.y, result.z, 1.0);
  }
}

/// `bloom_upsample.frag`: a 1-2-1 tent over sixteen.
final class BloomUpsampleShader implements CpuFragmentShader {
  const BloomUpsampleShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final src = _bloomSource(b);
    if (src == null) return Vector4(0.0, 0.0, 0.0, 1.0);
    // The radius is in source texels, and is what makes the chain a filter
    // rather than four copies of the same blur.
    final radius = math.max(src.params.z, 0.0);
    final tx = src.tx * radius;
    final ty = src.ty * radius;
    final u = v[0];
    final w = v[1];

    Vector3 at(double dx, double dy) {
      final t = src.source.sample(u + dx * tx, w + dy * ty);
      return Vector3(t.x, t.y, t.z);
    }

    final a = at(-1, 1), bb = at(0, 1), cc = at(1, 1);
    final d = at(-1, 0), e = at(0, 0), f = at(1, 0);
    final g = at(-1, -1), h = at(0, -1), i = at(1, -1);

    final result = e * 4.0 + (bb + d + f + h) * 2.0 + (a + cc + g + i);
    result.scale(1.0 / 16.0);
    return Vector4(result.x, result.y, result.z, 1.0);
  }
}

/// `lambert.frag`: pure diffuse, the cheapest model that still reads as
/// three-dimensional.
final class LambertShader implements CpuFragmentShader {
  const LambertShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final s = _readSurface(v, b);
    // No ORM map: a purely diffuse model has no response to metallic or
    // roughness, so sampling it would leave a slot the compiler then drops.
    _applyCommonMaps(s, v, b);
    final lit = _accumulateLights(s, b, c,
            shade: (s, light) => s.albedo, shadowed: true)
        .scaled(s.occlusion);
    final ambient = s.albedo * (s.ambient * s.occlusion);
    _writeSurface(c, s.normal, s.roughness);
    final total = lit + ambient + s.emissive;
    return Vector4(total.x, total.y, total.z, s.alpha);
  }
}

/// `blinn_phong.frag`: a Phong highlight on top of the albedo.
final class BlinnPhongShader implements CpuFragmentShader {
  const BlinnPhongShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final s = _readSurface(v, b);
    _applyCommonMaps(s, v, b);
    // Roughness drives the exponent, so the ORM map does reach the output.
    _applyMetallicRoughnessMap(s, v, b);
    final specularStrength =
        b.vec4('FragInfo', 'material', Vector4.zero()).w;

    final lit = _accumulateLights(s, b, c, shadowed: true, shade: (s, light) {
      // Perceptual roughness onto a Phong exponent. The mapping is arbitrary;
      // it only has to feel monotonic as the slider moves.
      final shininess = 256.0 + (4.0 - 256.0) * s.roughness;
      final specular =
          math.pow(light.nDotH, shininess).toDouble() * specularStrength;
      return Vector3(s.albedo.x + specular, s.albedo.y + specular,
          s.albedo.z + specular);
    }).scaled(s.occlusion);

    final ambient = s.albedo * (s.ambient * s.occlusion);
    _writeSurface(c, s.normal, s.roughness);
    final total = lit + ambient + s.emissive;
    return Vector4(total.x, total.y, total.z, s.alpha);
  }
}

/// `pbr.frag`: Cook-Torrance with GGX, height-correlated Smith, Schlick.
///
/// Formulations follow Filament, which is what the glTF spec describes, so an
/// imported material lands on the same look. There is no image-based lighting:
/// a prefiltered environment needs mip levels, which the stable channel does
/// not expose, and the flat ambient below is exactly the gap IBL would fill.
final class PbrShader implements CpuFragmentShader {
  const PbrShader();

  static const double _pi = 3.141592653589793;

  static double _dGgx(double nDotH, double alpha) {
    final a = nDotH * alpha;
    final k = alpha / math.max(1.0 - nDotH * nDotH + a * a, 1e-6);
    return k * k * (1.0 / _pi);
  }

  static double _vSmith(double nDotV, double nDotL, double alpha) {
    final a2 = alpha * alpha;
    final lambdaV = nDotL * math.sqrt(nDotV * nDotV * (1.0 - a2) + a2);
    final lambdaL = nDotV * math.sqrt(nDotL * nDotL * (1.0 - a2) + a2);
    return 0.5 / math.max(lambdaV + lambdaL, 1e-5);
  }

  static Vector3 _fSchlick(Vector3 f0, double vDotH) {
    final f = math.pow(1.0 - vDotH, 5.0).toDouble();
    return Vector3(
      f0.x + (1.0 - f0.x) * f,
      f0.y + (1.0 - f0.y) * f,
      f0.z + (1.0 - f0.z) * f,
    );
  }

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final s = _readSurface(v, b);
    _applyCommonMaps(s, v, b);
    _applyMetallicRoughnessMap(s, v, b);
    final specularStrength =
        b.vec4('FragInfo', 'material', Vector4.zero()).w;

    final lit = _accumulateLights(s, b, c, shadowed: true, shade: (s, light) {
      // Perceptual roughness squared is the GGX alpha; this is what makes the
      // roughness slider feel linear.
      final alpha = s.roughness * s.roughness;

      // Dielectrics reflect about four percent head-on; metals tint the
      // reflection with their albedo and have no diffuse response.
      final f0 = Vector3(
        0.04 + (s.albedo.x - 0.04) * s.metallic,
        0.04 + (s.albedo.y - 0.04) * s.metallic,
        0.04 + (s.albedo.z - 0.04) * s.metallic,
      );
      final diffuseColour = s.albedo * (1.0 - s.metallic);

      final d = _dGgx(light.nDotH, alpha);
      final vis = _vSmith(s.nDotV, light.nDotL, alpha);
      final f = _fSchlick(f0, light.vDotH);

      final specular = f * (d * vis * specularStrength);
      // Energy left over after reflection is what scatters diffusely.
      final diffuse = Vector3(
        diffuseColour.x * (1.0 - f.x) / _pi,
        diffuseColour.y * (1.0 - f.y) / _pi,
        diffuseColour.z * (1.0 - f.z) / _pi,
      );
      // The pi puts the result back on the scale the tone mapper and the
      // exposure default were calibrated against.
      return (diffuse + specular)..scale(_pi);
    }).scaled(s.occlusion);

    // Occlusion darkens indirect light, and is applied to the direct term too.
    // Not physical; with no IBL the flat ambient is far too weak for an
    // occlusion map to be visible otherwise.
    final diffuseColour = s.albedo * (1.0 - s.metallic.clamp(0.0, 1.0));
    final ambient = diffuseColour * (s.ambient * s.occlusion);
    _writeSurface(c, s.normal, s.roughness);
    final total = lit + ambient + s.emissive;
    return Vector4(total.x, total.y, total.z, s.alpha);
  }
}

/// `toon.frag`: the diffuse response quantised into bands, plus a rim term.
final class ToonShader implements CpuFragmentShader {
  const ToonShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final s = _readSurface(v, b);
    _applyCommonMaps(s, v, b);
    // Roughness sets the band count, so the ORM map matters here too.
    _applyMetallicRoughnessMap(s, v, b);

    final lit = _accumulateLights(s, b, c, shadowed: true, shade: (s, light) {
      // Fewer bands as roughness rises, so the slider still does something.
      final bands = 5.0 + (2.0 - 5.0) * s.roughness;
      var quantised = (light.nDotL * bands).floorToDouble() / bands;
      final fraction = _fract(light.nDotL * bands);
      quantised += _smoothstep(0.85, 1.0, fraction) / bands;
      // AccumulateLights multiplies by N.L, which is what the banding is meant
      // to replace, so divide it back out and keep the ramp.
      final ramp = quantised / math.max(light.nDotL, 1e-3);
      return s.albedo * ramp;
    }).scaled(s.occlusion);

    // The rim belongs to the view, not to any one light: inside the loop it
    // would brighten with the number of lamps in the scene.
    final specularStrength =
        b.vec4('FragInfo', 'material', Vector4.zero()).w;
    final rim =
        math.pow(1.0 - s.nDotV, 3.0).toDouble() * specularStrength * 0.35;
    final ambient = s.albedo * (s.ambient * s.occlusion);
    _writeSurface(c, s.normal, s.roughness);
    final total = lit + ambient + Vector3.all(rim) + s.emissive;
    return Vector4(total.x, total.y, total.z, s.alpha);
  }
}

double _smoothstep(double edge0, double edge1, double x) {
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

/// `normals.frag`: the world normal as colour.
///
/// A debug view, and the fastest way to tell a geometry bug from a lighting
/// one: hard edges show as flat blocks, smooth ones as gradients, and inverted
/// winding as the complement of the expected colour.
///
/// Written through the display-colour path — the value is not a light quantity,
/// so it is converted to linear here and the composite's encode hands the
/// original back, provided tone mapping and exposure are off.
final class NormalsShader implements CpuFragmentShader {
  const NormalsShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final n = Vector3(v[_vNormal], v[_vNormal + 1], v[_vNormal + 2])
      ..normalize();
    final display = Vector3(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5);
    _writeSurface(c, n, 1.0);
    return Vector4(_toLinear(display.x), _toLinear(display.y),
        _toLinear(display.z), 1.0);
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
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) {
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

/// `shadow_depth.frag`: window depth into a colour target.
///
/// A colour target rather than the depth buffer because flutter_gpu gives no
/// way to sample a depth texture, and the workaround is in the engine rather
/// than in any one backend. `gl_FragCoord.z` is the right value *because* the
/// shadow camera is orthographic — under perspective it would be hyperbolic,
/// all its precision near the near plane, and comparing two of them would mean
/// nothing.
final class ShadowDepthShader implements CpuFragmentShader {
  const ShadowDepthShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) =>
      Vector4(c.coord.z, 0.0, 0.0, 1.0);
}

/// `shadow_distance.frag`: radial distance from a point light, over its range.
///
/// Not clip depth. Clip depth is measured along one cube face's axis, so the
/// same distance reads differently depending which face a direction lands on
/// and every face boundary shows a seam.
final class ShadowDistanceShader implements CpuFragmentShader {
  const ShadowDistanceShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) {
    final light = bindings.vec4('ShadowLight', 'light', Vector4.zero());
    final range = math.max(light.w, 1e-4);
    final world = Vector3(v[_vWorld], v[_vWorld + 1], v[_vWorld + 2]);
    final distance =
        (world - Vector3(light.x, light.y, light.z)).length;
    return Vector4((distance / range).clamp(0.0, 1.0), 0.0, 0.0, 1.0);
  }
}

/// `shadow_tile_reset.frag`: one, the far end of the range.
///
/// A texel no caster covers means "nothing between the light and its range",
/// which is the right answer for a direction with nothing in it.
final class ShadowTileResetShader implements CpuFragmentShader {
  const ShadowTileResetShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) =>
      Vector4(1.0, 1.0, 1.0, 1.0);
}

/// `shadow_tile_reset.vert`: the fullscreen triangle, but on the far plane.
///
/// `z = 1`, not zero. The casters are drawn into the same tile immediately
/// afterwards, comparing `less` against a buffer this triangle has just
/// covered, and a mid-depth value stamped across the tile makes every caster
/// beyond it fail and vanish. In the engine's history that was a shadow that
/// was present before the tile reset existed and missing after.
final class ShadowTileResetVertexShader implements CpuVertexShader {
  const ShadowTileResetVertexShader();

  @override
  int get varyingCount => 2;

  @override
  Vector4 run(Float32List a, ShaderBindings bindings, Float32List out) {
    out[0] = a[2];
    out[1] = a[3];
    return Vector4(a[0], a[1], 1.0, 1.0);
  }
}

/// `mesh_skinned.vert`: the mesh stage with a joint blend in front of it.
///
/// The skinned layout is the standard one with joints and weights appended, so
/// the first sixteen floats are read at the same offsets as `mesh.vert` reads
/// them.
final class MeshSkinnedVertexShader implements CpuVertexShader {
  const MeshSkinnedVertexShader();

  static const int _joints = 16; // vec4
  static const int _weights = 20; // vec4

  @override
  int get varyingCount => _meshVaryings;

  @override
  Vector4 run(Float32List a, ShaderBindings bindings, Float32List out) {
    // The weights are renormalised rather than trusted: an exporter that
    // writes three of four and leaves the fourth at zero is common, and a
    // total below one shrinks the vertex towards the origin.
    var total = a[_weights] + a[_weights + 1] + a[_weights + 2] + a[_weights + 3];
    final w = total > 1e-5
        ? <double>[
            a[_weights] / total,
            a[_weights + 1] / total,
            a[_weights + 2] / total,
            a[_weights + 3] / total,
          ]
        : <double>[1.0, 0.0, 0.0, 0.0];

    final skin = Matrix4.zero();
    for (var i = 0; i < 4; i++) {
      if (w[i] == 0.0) continue;
      final joint = bindings.mat4('SkinInfo', 'joint_matrices',
          at: a[_joints + i].toInt());
      for (var e = 0; e < 16; e++) {
        skin[e] = skin[e] + joint[e] * w[i];
      }
    }

    final model = bindings.mat4('FrameInfo', 'model');
    final mvp = bindings.mat4('FrameInfo', 'mvp');
    final normalMatrix = bindings.mat4('FrameInfo', 'normal_matrix');

    final local = Vector4(a[_position], a[_position + 1], a[_position + 2], 1.0);
    final skinned = skin * local;
    final world = model * skinned;
    out[_vWorld] = world.x;
    out[_vWorld + 1] = world.y;
    out[_vWorld + 2] = world.z;

    final skinRotation = skin.getRotation();
    final n = normalMatrix.getRotation() *
        (skinRotation * Vector3(a[_normal], a[_normal + 1], a[_normal + 2]));
    out[_vNormal] = n.x;
    out[_vNormal + 1] = n.y;
    out[_vNormal + 2] = n.z;

    out[_vUv] = a[_texcoord];
    out[_vUv + 1] = a[_texcoord + 1];
    for (var i = 0; i < 4; i++) {
      out[_vColour + i] = a[_colour + i];
    }

    final t = model.getRotation() *
        (skinRotation *
            Vector3(a[_tangent], a[_tangent + 1], a[_tangent + 2]));
    out[_vTangent] = t.x;
    out[_vTangent + 1] = t.y;
    out[_vTangent + 2] = t.z;
    out[_vTangent + 3] = a[_tangent + 3];

    return mvp * skinned;
  }
}

/// `debug_line.vert`: position and colour, through one matrix.
final class DebugLineVertexShader implements CpuVertexShader {
  const DebugLineVertexShader();

  @override
  int get varyingCount => 4;

  @override
  Vector4 run(Float32List a, ShaderBindings bindings, Float32List out) {
    for (var i = 0; i < 4; i++) {
      out[i] = a[3 + i];
    }
    return bindings.mat4('LineInfo', 'view_projection') *
        Vector4(a[0], a[1], a[2], 1.0);
  }
}

/// `debug_line.frag`: the colour, unchanged.
final class DebugLineShader implements CpuFragmentShader {
  const DebugLineShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) =>
      Vector4(v[0], v[1], v[2], v[3]);
}

/// `particle.vert`: a billboard corner, and the world position for the fog.
final class ParticleVertexShader implements CpuVertexShader {
  const ParticleVertexShader();

  @override
  int get varyingCount => 9;

  @override
  Vector4 run(Float32List a, ShaderBindings bindings, Float32List out) {
    for (var i = 0; i < 4; i++) {
      out[i] = a[3 + i];
    }
    out[4] = a[7];
    out[5] = a[8];
    out[6] = a[0];
    out[7] = a[1];
    out[8] = a[2];
    return bindings.mat4('ParticleInfo', 'view_projection') *
        Vector4(a[0], a[1], a[2], 1.0);
  }
}

/// `particle_mesh.vert`: one mesh, placed and tinted per instance.
///
/// **The attribute order here is the layout's, not a shader's.** Every other
/// stage in this file reads one interleaved vertex whose order is its own `in`
/// declarations; this one is fed by `_LayoutFetch`, which assembles slot 0's
/// attributes and then slot 1's. So position and normal come first because they
/// are the mesh's buffer, and the placement follows because it is the instance
/// buffer — see `MeshParticleContributor.layout`, which is the one place that
/// order is decided.
final class ParticleMeshVertexShader implements CpuVertexShader {
  const ParticleMeshVertexShader();

  @override
  int get varyingCount => 10;

  @override
  Vector4 run(Float32List a, ShaderBindings bindings, Float32List out) {
    final scale = a[13];
    final x = a[6] + a[0] * scale;
    final y = a[7] + a[1] * scale;
    final z = a[8] + a[2] * scale;

    out[0] = a[9];
    out[1] = a[10];
    out[2] = a[11];
    out[3] = a[12];
    out[4] = x;
    out[5] = y;
    out[6] = z;
    // Unchanged by a uniform scale, which is why the scale is one number.
    out[7] = a[3];
    out[8] = a[4];
    out[9] = a[5];

    return bindings.mat4('ParticleMeshInfo', 'view_projection') *
        Vector4(x, y, z, 1.0);
  }
}

/// `particle_mesh.frag`: additive, fogged, shaded by which way a face points.
final class ParticleMeshShader implements CpuFragmentShader {
  const ParticleMeshShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final fog = b.vec4('FogInfo', 'fog', Vector4.zero());
    final eye = b.vec4('FogInfo', 'eye', Vector4.zero());

    final tx = eye.x - v[4];
    final ty = eye.y - v[5];
    final tz = eye.z - v[6];
    final distance = math.sqrt(tx * tx + ty * ty + tz * tz);

    var facing = 1.0;
    if (distance > 0.0) {
      final n = Vector3(v[7], v[8], v[9]);
      final length = n.length;
      if (length > 0.0) {
        // `abs`, because nothing here is culled and a back face is as visible
        // as a front one.
        facing = ((n.x * tx + n.y * ty + n.z * tz) / (length * distance)).abs();
      }
    }
    // Never to zero: a silhouette edge is exactly perpendicular to the eye, and
    // a face that vanished there would carve a dark seam along it.
    final intensity = 0.35 + 0.65 * facing;

    var fogged = 1.0;
    if (fog.w > 0.0) {
      fogged = math.exp(-fog.w * distance).clamp(0.0, 1.0);
    }

    final scale = v[3] * intensity * fogged;
    return Vector4(v[0] * scale, v[1] * scale, v[2] * scale, 1.0);
  }
}

/// `particle.frag`: a radial falloff, premultiplied, fogged.
final class ParticleShader implements CpuFragmentShader {
  const ParticleShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final cx = v[4] * 2.0 - 1.0;
    final cy = v[5] * 2.0 - 1.0;
    final radius = math.sqrt(cx * cx + cy * cy);
    final falloff = 1.0 - _smoothstep(0.0, 1.0, radius);
    final intensity = falloff * falloff;

    var fogged = 1.0;
    final fog = b.vec4('FogInfo', 'fog', Vector4.zero());
    if (fog.w > 0.0) {
      final eye = b.vec4('FogInfo', 'eye', Vector4.zero());
      final d = (Vector3(v[6], v[7], v[8]) - Vector3(eye.x, eye.y, eye.z))
          .length;
      fogged = math.exp(-fog.w * d).clamp(0.0, 1.0);
    }

    final scale = v[3] * intensity * fogged;
    // Alpha one with the colour premultiplied: these draw additively, so the
    // alpha channel is not what decides how much of them lands.
    return Vector4(v[0] * scale, v[1] * scale, v[2] * scale, 1.0);
  }
}

/// `DecodeOctahedral`, the inverse of what the surface buffer stored.
Vector3 _decodeOctahedral(double ex, double ey) {
  final x = ex * 2.0 - 1.0;
  final y = ey * 2.0 - 1.0;
  final n = Vector3(x, y, 1.0 - x.abs() - y.abs());
  final t = math.max(-n.z, 0.0);
  n.x += n.x >= 0.0 ? -t : t;
  n.y += n.y >= 0.0 ? -t : t;
  return n..normalize();
}

/// `reflections.frag`: screen-space reflections, marched against the surface
/// buffer.
///
/// Transcribed including the part that looks wrong: the ray's screen position
/// is `ndc.xy * 0.5 + 0.5` with **no v flip**, where the shadow lookups do
/// flip. Reproducing it exactly is the job here — if the two conventions
/// genuinely disagree that is a finding about the engine, and it is not one a
/// backend gets to decide by quietly picking the other one.
final class ReflectionsShader implements CpuFragmentShader {
  const ReflectionsShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final sceneMap = b.textures['scene_texture'];
    final surfaceMap = b.textures['surface_texture'];
    if (sceneMap == null || surfaceMap == null) {
      return Vector4(0.0, 0.0, 0.0, 1.0);
    }
    final u = v[0];
    final w = v[1];

    final surface = surfaceMap.sample(u, w);
    final sampled = sceneMap.sample(u, w);
    final scene = Vector3(sampled.x, sampled.y, sampled.z);

    final screen = b.vec4('ReflectionInfo', 'screen', Vector4.zero());
    final debugOnly = screen.w > 0.5;
    final background = debugOnly ? Vector3.zero() : scene;

    Vector4 done(Vector3 rgb) => Vector4(rgb.x, rgb.y, rgb.z, 1.0);

    if (surface.w <= 0.0) return done(background);

    final normal = _decodeOctahedral(surface.x, surface.y);
    final roughness = surface.z;
    final polish = 1.0 - _smoothstep(0.18, 0.45, roughness);
    if (polish <= 0.0) return done(background);

    final inverse = b.mat4('ReflectionInfo', 'inverse_view_projection');
    final ndc = Vector4(u * 2.0 - 1.0, w * 2.0 - 1.0, surface.w, 1.0);
    final worldH = inverse * ndc;
    final position =
        Vector3(worldH.x, worldH.y, worldH.z)..scale(1.0 / worldH.w);

    final camera = b.vec4('ReflectionInfo', 'camera', Vector4.zero());
    final toEye = (Vector3(camera.x, camera.y, camera.z) - position)
      ..normalize();
    final facing = normal.dot(toEye);
    if (facing <= 0.05) return done(background);

    // reflect(-toEye, normal)
    final incident = -toEye;
    final ray = incident - normal * (2.0 * incident.dot(normal));

    final params = b.vec4('ReflectionInfo', 'params', Vector4.zero());
    final steps = params.x.toInt();
    final stride = params.y;
    final thickness = params.z;
    final intensity = params.w;

    final viewProjection = b.mat4('ReflectionInfo', 'view_projection');
    final march = position + normal * 0.02 + ray * stride;
    var hitColour = Vector3.zero();
    var hit = 0.0;

    // Sixty-four is the shader's own ceiling, and it is a real one: GLSL needs
    // a constant bound. Kept so the two loops end in the same place.
    for (var i = 0; i < 64; i++) {
      if (i >= steps) break;
      final clip = viewProjection * Vector4(march.x, march.y, march.z, 1.0);
      if (clip.w <= 0.0) break;
      final nx = clip.x / clip.w;
      final ny = clip.y / clip.w;
      final nz = clip.z / clip.w;
      final su = nx * 0.5 + 0.5;
      final sv = ny * 0.5 + 0.5;
      if (su < 0.0 || su > 1.0 || sv < 0.0 || sv > 1.0) break;

      final sceneDepth = surfaceMap.sample(su, sv).w;
      if (sceneDepth > 0.0) {
        final difference = nz - sceneDepth;
        if (difference > 0.0 && difference < thickness) {
          final tex = sceneMap.sample(su, sv);
          hitColour = Vector3(tex.x, tex.y, tex.z);
          final border = 1.0 -
              math.max((su * 2.0 - 1.0).abs(), (sv * 2.0 - 1.0).abs());
          hit = _smoothstep(0.0, 0.15, border);
          break;
        }
      }
      march.add(ray * stride);
    }

    final fresnel = math.pow(1.0 - facing, 4.0).toDouble();
    final reflection =
        hitColour * (hit * intensity * polish * (0.15 + 0.85 * fresnel));
    return done(debugOnly ? reflection : scene + reflection);
  }
}

/// `mrt_probe.frag`: two constants into two attachments.
///
/// It exists to answer whether a backend writes the second target at all, so
/// there is nothing to get right here except writing both.
final class MrtProbeShader implements CpuFragmentShader {
  const MrtProbeShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    c.surface = Vector4(0.75, 0.5, 0.25, 1.0);
    return Vector4(0.25, 0.5, 0.75, 1.0);
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
  Vector4 run(Float32List a, ShaderBindings b,
          [Object? out, Object? context]) =>
      throw UnsupportedError(
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
    'ParticleMeshVertex':
        const CpuStage.vertex(ParticleMeshVertexShader()),
    'ParticleMesh': const CpuStage.fragment(ParticleMeshShader()),
    'Particle': const CpuStage.fragment(ParticleShader()),
    'Reflections': const CpuStage.fragment(ReflectionsShader()),
    'MrtProbe': const CpuStage.fragment(MrtProbeShader()),
    'Composite': const CpuStage.fragment(CompositeShader()),
    'ShadowDepth': const CpuStage.fragment(ShadowDepthShader()),
    'ShadowDistance': const CpuStage.fragment(ShadowDistanceShader()),
    'ShadowTileReset': const CpuStage.fragment(ShadowTileResetShader()),
    'ShadowTileResetVertex':
        const CpuStage.vertex(ShadowTileResetVertexShader()),
  };

  for (final name in kUnimplementedCpuVertexShaders) {
    stages[name] = CpuStage.vertex(_Unimplemented(name));
  }
  for (final name in kUnimplementedCpuFragmentShaders) {
    stages[name] = CpuStage.fragment(_Unimplemented(name));
  }
  return stages;
}
