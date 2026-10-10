/// `ReadSurface` and the material maps, transcribed from `surface.glsl` and
/// `material_maps.glsl`.
///
/// Every lit model — `cpu_shaders_lit.dart` — starts by reading a [Surface]
/// out of the vertex varyings and the bound material, then asks the maps here
/// to perturb it. Split from the lighting math itself (`cpu_shaders_lighting.dart`)
/// because a surface is a question about *this fragment*, independent of which
/// lights see it.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_color.dart';
import 'cpu_shaders_irradiance.dart';
import 'cpu_shaders_layout.dart';

/// `HashedAlphaNoise` in `surface.glsl` and `depth_predraw.frag`, operation
/// for operation: the noise a hashed alpha is compared with at the
/// scene-space point ([x], [y], [z]), counted in sixteenths of a metre from
/// where the world starts. [cutoff] is the hashed sentinel, -2 less the
/// scene's origin in those cells, each below 128, which the renderer packs.
///
/// The cells are wrapped to [0, 128) before the hash sees them, so every
/// number it takes is small; the hash is Hoskins' `hash13`, with no `sin`.
double hashedAlphaNoise(double x, double y, double z, double cutoff) {
  double fract(double v) => v - v.floorToDouble();
  double wrap(double v) => v - 128.0 * (v / 128.0).floorToDouble();
  final key = -2.0 - cutoff;
  final cx = wrap((x * 16.0).floorToDouble() + (key / 16384.0).floorToDouble());
  final cy = wrap(
    (y * 16.0).floorToDouble() + wrap((key / 128.0).floorToDouble()),
  );
  final cz = wrap((z * 16.0).floorToDouble() + wrap(key));
  var px = fract(cx * 0.1031);
  var py = fract(cy * 0.1031);
  var pz = fract(cz * 0.1031);
  // `p3 += dot(p3, p3.zyx + 31.32)`.
  final d = px * (pz + 31.32) + py * (py + 31.32) + pz * (px + 31.32);
  px += d;
  py += d;
  pz += d;
  return fract((px + py) * pz);
}

/// How far the texture coordinate moves per screen pixel, for mip selection.
///
/// **Every map below sampled the base level until this existed**, whatever mip
/// chain the texture had been uploaded with, because `CpuTexture.sample`
/// selects level zero when it is given no derivatives and nothing here was
/// giving it any. The particle stage had been passing them since it was
/// written; the lit path never adopted it, so a normal map read at full
/// resolution wherever the hardware backends read a blurred level. That shows
/// as the fine detail being sharper and darker than it should be — it made
/// `normal-mapping` the widest disagreement this backend had with Impeller —
/// and as aliasing that moves when the camera does.
///
/// The larger of the two directions per axis, which is what the particle stage
/// takes and for the same reason: a hardware sampler uses the longer side of
/// the footprint parallelogram, and the maximum of the axis-aligned components
/// is that for a surface facing the camera.
///
/// [bias] is `texture`'s third argument, [materialLodBias] in the GLSL —
/// `R2`: a level of detail is the log of the footprint, so a bias of `b`
/// is the footprint times `2^b`. Nought leaves it exactly as it was.
UvFootprint uvFootprint(FragmentContext c, {double bias = 0.0}) {
  final ddx = c.ddx;
  final ddy = c.ddy;
  if (ddx == null || ddy == null) {
    return (du: 0.0, dv: 0.0, dudx: 0.0, dvdx: 0.0, dudy: 0.0, dvdy: 0.0);
  }
  if (bias != 0.0) {
    final scale = math.pow(2.0, bias).toDouble();
    final plain = uvFootprint(c);
    return (
      du: plain.du * scale,
      dv: plain.dv * scale,
      dudx: plain.dudx * scale,
      dvdx: plain.dvdx * scale,
      dudy: plain.dudy * scale,
      dvdy: plain.dvdy * scale,
    );
  }
  // **Both vectors, as well as the axis maxima** — `gfx-02n`. `du`/`dv` are
  // what every caller here has always used and what the mip level is still
  // chosen from, unchanged: the maximum of the axis-aligned components, which
  // is the longer side of the footprint for a surface facing the camera.
  //
  // The four below are the footprint itself, before that collapse, and they
  // are why anisotropy needed them: a floor at a grazing angle has a long,
  // thin parallelogram, and `max` over each axis separately throws away
  // exactly the *ratio* between its sides. The sampler reads them only when a
  // sampler asked for taps, so nothing that did not ask can move.
  return (
    du: math.max(ddx[kVUv].abs(), ddy[kVUv].abs()),
    dv: math.max(ddx[kVUv + 1].abs(), ddy[kVUv + 1].abs()),
    dudx: ddx[kVUv],
    dvdx: ddx[kVUv + 1],
    dudy: ddy[kVUv],
    dvdy: ddy[kVUv + 1],
  );
}

/// `MaterialLodBias()`: the bias every material map is read with — `R2`.
double materialLodBias(ShaderBindings b) =>
    b.vec4('FragInfo', 'target_origin', Vector4.zero()).y;

/// What [uvFootprint] returns.
typedef UvFootprint = ({
  double du,
  double dv,
  double dudx,
  double dvdx,
  double dudy,
  double dvdy,
});

/// The maps a lit material reads, in `kMapBaseColor`'s order — `C8`.
const int kMapBaseColor = 0;
const int kMapMetallicRoughness = 1;
const int kMapNormal = 2;
const int kMapOcclusion = 3;
const int kMapEmissive = 4;

/// `MapUv(slot)`: where map [slot] is read, with the footprint there — `C8`.
///
/// The vertex's own coordinate unless [transformed], which only the layered
/// stage is: every other stage's `MapUv` is a macro for `v_texcoord`, and
/// reading `LayerInfo` here for them would read whatever an earlier layered
/// draw left in the encoder. The footprint is the vertex coordinate's carried
/// through the matrix, which is what a GPU's derivative of the transformed
/// coordinate is. The identity reads both back to the bit.
({double u, double v, UvFootprint footprint}) mapUv(
  int slot,
  Float32List v,
  ShaderBindings b,
  FragmentContext c, {
  bool transformed = false,
}) {
  final plain = uvFootprint(c, bias: materialLodBias(b));
  final rows = transformed ? b.read('LayerInfo', 'uv_transform') : null;
  if (rows == null || rows.length < slot * 8 + 8) {
    return (u: v[kVUv], v: v[kVUv + 1], footprint: plain);
  }
  final o = slot * 8;
  final (m00, m01, m02) = (rows[o], rows[o + 1], rows[o + 2]);
  final (m10, m11, m12) = (rows[o + 4], rows[o + 5], rows[o + 6]);
  final dudx = m00 * plain.dudx + m01 * plain.dvdx;
  final dvdx = m10 * plain.dudx + m11 * plain.dvdx;
  final dudy = m00 * plain.dudy + m01 * plain.dvdy;
  final dvdy = m10 * plain.dudy + m11 * plain.dvdy;
  return (
    u: m00 * v[kVUv] + m01 * v[kVUv + 1] + m02,
    v: m10 * v[kVUv] + m11 * v[kVUv + 1] + m12,
    footprint: (
      du: math.max(dudx.abs(), dudy.abs()),
      dv: math.max(dvdx.abs(), dvdy.abs()),
      dudx: dudx,
      dvdx: dvdx,
      dudy: dudy,
      dvdy: dvdy,
    ),
  );
}

/// What `ReadSurface` produces, for the models that need more than the albedo.
/// Mutable, because the GLSL passes it as `inout` to every map function and
/// each one modifies a field. A copy-returning version would read better and
/// would be a different program.
final class Surface {
  Surface(
    this.albedo,
    this.alpha,
    this.normal,
    this.world,
    this.ambient,
    this.metallic,
    this.roughness,
    this.view,
    this.nDotV,
    this.tangent,
  );
  Vector3 albedo;

  /// Opacity, nought to one.
  double alpha;
  Vector3 normal;
  final Vector3 world;

  /// Hemispheric and already scaled by the scene's strength: the sky above,
  /// the ground bounce below, blended by which way the surface faces.
  final Vector3 ambient;

  /// How metallic the surface is, nought to one.
  double metallic;

  /// Perceptual roughness, nought to one.
  double roughness;

  /// Towards the eye, which every specular term needs.
  final Vector3 view;

  /// Clamped away from zero: a grazing view otherwise divides by zero in the
  /// specular visibility term. A cosine, with no unit.
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
/// Null is the GLSL's `discard`: a masked material's fragment under its
/// cutoff. Every model that calls this hands the null on, the way a discarded
/// fragment reaches no lighting loop. Transcribed once the picking stage
/// needed the same hole — an id pass that saw a fence where the picture shows
/// the thing behind it would be picking something the eye cannot see — and a
/// scene pass without it would then have disagreed with the pick.
///
/// [transformed] is the layered stage's `MapUv` — see [mapUv].
Surface? readSurface(
  Float32List v,
  ShaderBindings bindings,
  FragmentContext c, {
  bool transformed = false,
}) {
  final (u: mapU, v: mapV, footprint: uv) = mapUv(
    kMapBaseColor,
    v,
    bindings,
    c,
    transformed: transformed,
  );
  final tint = bindings.vec4('FragInfo', 'base_color', Vector4(1, 1, 1, 1));
  final texture = bindings.textures['base_color_texture'];
  final texel = texture == null
      ? Vector4(1, 1, 1, 1)
      : texture.sample(
          mapU,
          mapV,
          du: uv.du,
          dv: uv.dv,
          // The albedo is the one map a floor's checks live in, and the one
          // this engine's samplers ever ask taps for. The other maps below
          // pass the axis maxima alone, which is what they always did.
          dudx: uv.dudx,
          dvdx: uv.dvdx,
          dudy: uv.dudy,
          dvdy: uv.dvdy,
        );

  // Texture and tint are sRGB; the vertex colour is authored linear, per glTF.
  final albedo = Vector3(
    toLinear(texel.x) * toLinear(tint.x) * v[kVColour],
    toLinear(texel.y) * toLinear(tint.y) * v[kVColour + 1],
    toLinear(texel.z) * toLinear(tint.z) * v[kVColour + 2],
  );
  final textured = texel.w * tint.w * v[kVColour + 3];

  // Alpha masking, glTF's third alpha mode, before anything else for the
  // reason the GLSL gives: a discarded fragment should not pay for the
  // lighting loop. A negative cutoff is "not masked", the encoding the engine
  // writes into `material2.x`.
  final cutoff = bindings
      .vec4('FragInfo', 'material2', Vector4(-1.0, 1.0, 1.0, 1.0))
      .x;
  if (cutoff > 1.0) {
    // `P7`'s coverage, which never reaches this rasteriser: it answers false
    // to `supportsAlphaToCoverage`, so the engine writes the plain cutoff.
    // Cut at the cutoff it carries rather than keep a fragment that one
    // sample a pixel has no coverage to spread.
    if (textured < cutoff - 1.0) return null;
  } else if (cutoff >= 0.0) {
    if (textured < cutoff) return null;
  } else if (cutoff < -1.5) {
    // `gfx-16n`: hashed, the fourth mode. Anchored to the world rather than
    // to the screen so the pattern travels with the surface, and stays put
    // through a shift of the origin — see [hashedAlphaNoise].
    final noise = hashedAlphaNoise(
      v[kVWorld],
      v[kVWorld + 1],
      v[kVWorld + 2],
      cutoff,
    );
    if (textured < noise) return null;
  }
  // What survives a mask's cut is opaque, as `surface.glsl` writes it.
  final alpha = cutoff >= 0.0 && cutoff <= 1.0 ? 1.0 : textured;

  final normal = Vector3(v[kVNormal], v[kVNormal + 1], v[kVNormal + 2]);
  final length = normal.length;
  if (length > 1e-6) normal.scale(1.0 / length);
  // `if (!gl_FrontFacing) s.n = -s.n;`: the back of a double-sided surface
  // is lit from its own side.
  if (!c.frontFacing) normal.negate();

  final material = bindings.vec4('FragInfo', 'material', Vector4.zero());
  final camera = bindings.vec4('FragInfo', 'camera_position', Vector4.zero());
  final world = Vector3(v[kVWorld], v[kVWorld + 1], v[kVWorld + 2]);
  // `P7`: against the view axis through an orthographic lens — `TowardsEye`.
  // The stages without the fog block keep the eye's point, as the GLSL's
  // `F3D_NO_FOG` ones do, and read as perspective here.
  final view = orthographic(bindings)
      ? towardsEye(v, bindings)
      : Vector3(camera.x, camera.y, camera.z) - world;
  final viewLength = view.length;
  if (viewLength > 1e-6) view.scale(1.0 / viewLength);

  // Hemispheric, blended on the geometric normal before any map perturbs it:
  // ambient of this kind says which half of the world a face can see, and
  // millimetres of bump relief are not an answer to that.
  final sky = bindings.vec4('FragInfo', 'ambient_sky', Vector4(1, 1, 1, 1));
  final ground = bindings.vec4(
    'FragInfo',
    'ambient_ground',
    Vector4(1, 1, 1, 1),
  );
  final up = normal.y * 0.5 + 0.5;
  final ambient = Vector3(
    (ground.x + (sky.x - ground.x) * up) * material.z,
    (ground.y + (sky.y - ground.y) * up) * material.z,
    (ground.z + (sky.z - ground.z) * up) * material.z,
  );

  // `L5`: what `g_albedo` carries into the albedo buffer, sRGB-encoded as
  // `WriteSurfaceGeometry` stores it.
  c.albedo = Vector4(
    toSrgb(albedo.x.clamp(0.0, 1.0)),
    toSrgb(albedo.y.clamp(0.0, 1.0)),
    toSrgb(albedo.z.clamp(0.0, 1.0)),
    1.0,
  );
  return Surface(
    albedo,
    alpha,
    normal,
    world,
    ambient,
    material.x.clamp(0.0, 1.0),
    material.y.clamp(0.02, 1.0),
    view,
    math.max(normal.dot(view), 1e-4),
    Vector4(v[kVTangent], v[kVTangent + 1], v[kVTangent + 2], v[kVTangent + 3]),
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
void applyMetallicRoughnessMap(
  Surface s,
  Float32List v,
  ShaderBindings b,
  FragmentContext c, {
  bool transformed = false,
}) {
  final orm = b.textures['metallic_roughness_texture'];
  if (orm == null) return;
  final (u: mu, v: mv, footprint: uv) = mapUv(
    kMapMetallicRoughness,
    v,
    b,
    c,
    transformed: transformed,
  );
  final texel = orm.sample(mu, mv, du: uv.du, dv: uv.dv);
  s.metallic = (s.metallic * texel.z).clamp(0.0, 1.0);
  s.roughness = (s.roughness * texel.y).clamp(0.02, 1.0);
}

/// glTF's `occlusionStrength` lerps between ignoring the map and applying it
/// in full, which is why this is a mix and not a multiply.
void applyOcclusionMap(
  Surface s,
  Float32List v,
  ShaderBindings b,
  FragmentContext c, {
  bool transformed = false,
}) {
  final map = b.textures['occlusion_texture'];
  if (map == null) return;
  final (u: mu, v: mv, footprint: uv) = mapUv(
    kMapOcclusion,
    v,
    b,
    c,
    transformed: transformed,
  );
  final occlusion = map.sample(mu, mv, du: uv.du, dv: uv.dv).x;
  final strength = b
      .vec4('FragInfo', 'material2', Vector4.zero())
      .z
      .clamp(0.0, 1.0);
  s.occlusion = 1.0 + (occlusion - 1.0) * strength;
}

/// `SampleLightmap`: the baked irradiance at this fragment, RGBM-decoded as
/// `rgb × a × 8`, or black when the slot holds the renderer's one-texel
/// fallback — which is every material without a map.
Vector3 sampleLightmap(Float32List v, ShaderBindings b, FragmentContext c) {
  final map = b.textures['lightmap_texture'];
  if (map == null) return Vector3.zero();
  final texel = map.sample(v[kVLightmap], v[kVLightmap + 1]);
  final multiplier = texel.w * 8.0;
  return Vector3(
    texel.x * multiplier,
    texel.y * multiplier,
    texel.z * multiplier,
  );
}

void applyEmissiveMap(
  Surface s,
  Float32List v,
  ShaderBindings b,
  FragmentContext c, {
  bool transformed = false,
}) {
  final map = b.textures['emissive_texture'];
  if (map == null) return;
  final (u: mu, v: mv, footprint: uv) = mapUv(
    kMapEmissive,
    v,
    b,
    c,
    transformed: transformed,
  );
  final texel = map.sample(mu, mv, du: uv.du, dv: uv.dv);
  final factor = b.vec4('FragInfo', 'emissive', Vector4.zero());
  final strength = b.vec4('FragInfo', 'material2', Vector4.zero()).w;
  s.emissive = Vector3(
    toLinear(texel.x) * factor.x * strength,
    toLinear(texel.y) * factor.y * strength,
    toLinear(texel.z) * factor.z * strength,
  );
}

/// Perturbs the normal by the tangent-space map.
void applyNormalMap(
  Surface s,
  Float32List v,
  ShaderBindings b,
  FragmentContext c, {
  bool transformed = false,
}) {
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
  // `C8`: the frame turns with a map its transform turns or mirrors, as
  // `ApplyNormalMap` turns it, on the front face's frame. dP/dv is minus the
  // bitangent, so `m10` adds it.
  final rows = transformed ? b.read('LayerInfo', 'uv_transform') : null;
  if (rows != null && rows.length >= kMapNormal * 8 + 8) {
    const o = kMapNormal * 8;
    final (m00, m01, m10, m11) = (
      rows[o],
      rows[o + 1],
      rows[o + 4],
      rows[o + 5],
    );
    final flip = m00 * m11 - m01 * m10 < 0.0 ? -1.0 : 1.0;
    final front = c.frontFacing ? bitangent : -bitangent;
    final turned = (t * m11 + front * m10)..scale(flip);
    if ((m01 != 0.0 || m10 != 0.0 || m00 < 0.0 || m11 < 0.0) &&
        turned.length2 > 1e-12) {
      t.setFrom(turned..normalize());
      bitangent.setFrom(s.normal.cross(t)..scale(s.tangent.w * flip));
    }
  }
  // The back face turns the whole frame: the normal and the bitangent built
  // from it have turned already, the tangent follows — see
  // `material_maps.glsl`.
  if (!c.frontFacing) t.negate();

  final (u: mu, v: mv, footprint: uv) = mapUv(
    kMapNormal,
    v,
    b,
    c,
    transformed: transformed,
  );
  final texel = map.sample(mu, mv, du: uv.du, dv: uv.dv);
  final scale = b.vec4('FragInfo', 'material2', Vector4.zero()).y;
  final x = texel.x * 2.0 - 1.0;
  final y = texel.y * 2.0 - 1.0;
  // A two-channel map rebuilds z from the unit length, before the scale —
  // `emissive.w`, as `ApplyNormalMap` reads it.
  final sz = b.vec4('FragInfo', 'emissive', Vector4.zero()).w > 0.5
      ? math.sqrt(math.max(1.0 - x * x - y * y, 0.0))
      : texel.z * 2.0 - 1.0;
  final sx = x * scale;
  final sy = y * scale;

  s.normal = (t * sx + bitangent * sy + s.normal * sz)..normalize();
  s.nDotV = math.max(s.normal.dot(s.view), 1e-4);
}

/// The three every lit model uses. Metal-rough is separate because only the
/// models that respond to metallic or roughness may sample it.
void applyCommonMaps(
  Surface s,
  Float32List v,
  ShaderBindings b,
  FragmentContext c, {
  bool transformed = false,
}) {
  // `L3`: the field in place of the hemisphere, before the normal map, as
  // `ApplyCommonMaps` does it.
  if (irradianceEnabled(b)) {
    final strength = b.vec4('FragInfo', 'material', Vector4.zero()).z;
    s.ambient.setFrom(
      sampleIrradiance(b, s.world, s.normal, s.view)..scale(strength),
    );
  }
  applyNormalMap(s, v, b, c, transformed: transformed);
  applyOcclusionMap(s, v, b, c, transformed: transformed);
  applyEmissiveMap(s, v, b, c, transformed: transformed);
}

/// `NonFinite` from `surface.glsl`: NaN or infinite in any channel.
bool nonFinite(Vector3 c) =>
    c.x.isNaN ||
    c.y.isNaN ||
    c.z.isNaN ||
    c.x.isInfinite ||
    c.y.isInfinite ||
    c.z.isInfinite;

/// `DebugIdentityColour` from `surface.glsl` — `A5.21`: a key spread round
/// the hue circle by the golden ratio.
Vector3 debugIdentityColour(double key) {
  final hue = fract(key * 0.6180340 + 0.13);
  double channel(double offset) =>
      ((fract(hue + offset) * 6.0 - 3.0).abs() - 1.0).clamp(0.0, 1.0);
  double toward(double k) => (1.0 + (k - 1.0) * 0.7) * 0.95;
  return Vector3(
    toward(channel(0.0)),
    toward(channel(2.0 / 3.0)),
    toward(channel(1.0 / 3.0)),
  );
}

/// `WriteDebugView` from `surface.glsl` — `P6`: the material channel
/// `FragInfo.debug_view` asks for, in place of [lit], or null when no view
/// is on or the fragment sits left of the split, and the caller writes the
/// light.
///
/// Display values converted to linear, through the surface buffer and the
/// weighted-blended targets as `writeLit` writes them, and without the fog,
/// for the reasons the GLSL gives. [geometric] is the normal the surface
/// buffer takes when the stage hands `writeLit` another than [Surface.normal]
/// — the impostor's card.
Vector4? writeDebugView(
  FragmentContext c,
  Float32List v,
  ShaderBindings b,
  Surface s,
  Vector3 lit, {
  bool transformed = false,
  Vector3? geometric,
}) {
  final debug = b.vec4('FragInfo', 'debug_view', Vector4.zero());
  // `A5.22`: left of the column the view in z, right of it the one in x.
  final view = c.coord.x < debug.y ? debug.z : debug.x;
  if (view < 0.5) return null;
  Vector3 srgbOf(Vector3 linear) => Vector3(
    toSrgb(linear.x.clamp(0.0, 1.0)),
    toSrgb(linear.y.clamp(0.0, 1.0)),
    toSrgb(linear.z.clamp(0.0, 1.0)),
  );
  // `A5.21`: the vertex tangent square to the vertex normal, and the draw's
  // identity unpacked from w, as `WriteDebugView` has them.
  final vertexNormal = Vector3(v[kVNormal], v[kVNormal + 1], v[kVNormal + 2])
    ..normalize();
  final rawTangent = Vector3(v[kVTangent], v[kVTangent + 1], v[kVTangent + 2]);
  final tangent = rawTangent - vertexNormal * vertexNormal.dot(rawTangent);
  final tangentUsable =
      tangent.length2 > 1e-12 && (v[kVTangent + 3].abs() - 1.0).abs() < 0.01;
  final identityObject = (debug.w / 8192.0).floorToDouble();
  final identityRest = debug.w - identityObject * 8192.0;
  final identityMaterial = (identityRest / 2.0).floorToDouble();
  final normalMapped = identityRest - identityMaterial * 2.0 > 0.5;
  final shown = switch ((view + 0.5).floor()) {
    1 => srgbOf(s.albedo),
    2 => Vector3(
      s.normal.x * 0.5 + 0.5,
      s.normal.y * 0.5 + 0.5,
      s.normal.z * 0.5 + 0.5,
    ),
    3 => Vector3.all(s.roughness.clamp(0.0, 1.0)),
    4 => Vector3.all(s.metallic.clamp(0.0, 1.0)),
    5 => Vector3.all(s.occlusion.clamp(0.0, 1.0)),
    6 => srgbOf(s.emissive),
    7 => () {
      final (u: u, v: w, footprint: _) = mapUv(
        kMapBaseColor,
        v,
        b,
        c,
        transformed: transformed,
      );
      return Vector3(fract(u), fract(w), 0.0);
    }(),
    8 =>
      nonFinite(lit)
          ? Vector3(1.0, 0.0, 1.0)
          : () {
              final e = srgbOf(lit);
              return Vector3.all(
                (0.2126 * e.x + 0.7152 * e.y + 0.0722 * e.z) * 0.5,
              );
            }(),
    9 =>
      tangentUsable
          ? ((tangent.normalized()..scale(0.5))..add(Vector3.all(0.5)))
          : Vector3.zero(),
    10 => () {
      final (u: u, v: w, footprint: _) = mapUv(
        kMapBaseColor,
        v,
        b,
        c,
        transformed: transformed,
      );
      final cellSum = (u * 8.0).floorToDouble() + (w * 8.0).floorToDouble();
      final odd = fract(cellSum * 0.5) * 2.0;
      final grey = 0.22 + (0.92 - 0.22) * odd;
      return Vector3(
        grey * (0.55 + 0.45 * fract(u)),
        grey * (0.55 + 0.45 * fract(w)),
        grey * 0.85,
      );
    }(),
    11 => c.frontFacing ? Vector3(0.2, 0.35, 0.95) : Vector3(0.95, 0.15, 0.15),
    12 => srgbOf(Vector3(v[kVColour], v[kVColour + 1], v[kVColour + 2])),
    13 || 14 => debugIdentityColour(
      (view + 0.5).floor() == 13 ? identityObject : identityMaterial,
    )..scale(0.55 + 0.45 * s.nDotV),
    15 => () {
      final e = srgbOf(s.albedo);
      final luma = 0.2126 * e.x + 0.7152 * e.y + 0.0722 * e.z;
      final metal = s.metallic > 0.5;
      final brightest = math.max(e.x, math.max(e.y, e.z));
      return !metal && luma < 30.0 / 255.0
          ? Vector3(0.1, 0.3, 1.0)
          : !metal && brightest > 240.0 / 255.0
          ? Vector3(1.0, 0.1, 0.1)
          : metal && luma < 180.0 / 255.0
          ? Vector3(1.0, 0.85, 0.1)
          : Vector3.all(luma);
    }(),
    16 =>
      s.metallic > 0.05 && s.metallic < 0.95
          ? Vector3(1.0, 0.5, 0.0)
          : Vector3.all(s.metallic > 0.5 ? 1.0 : 0.15),
    17 =>
      !normalMapped
          ? Vector3.all(0.5)
          : tangentUsable
          ? Vector3(0.2, 0.8, 0.3)
          : Vector3(1.0, 0.1, 0.1),
    _ => Vector3.zero(),
  };
  writeSurface(c, v, b, geometric ?? s.normal, s.roughness);
  final weight = premultiplies(b) ? s.alpha : 1.0;
  return writeWeightedBlended(
    c,
    v,
    b,
    Vector4(
      toLinear(shown.x) * weight,
      toLinear(shown.y) * weight,
      toLinear(shown.z) * weight,
      s.alpha,
    ),
  );
}
