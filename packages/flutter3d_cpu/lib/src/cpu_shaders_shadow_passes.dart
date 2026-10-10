/// The stages that render *into* a shadow map, as opposed to the ones that
/// look one up while lighting a surface — see `cpu_shaders_shadow_directional.dart`
/// and `cpu_shaders_shadow_point.dart` for those.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_layout.dart';
import 'cpu_shaders_surface.dart' show hashedAlphaNoise, uvFootprint;

/// `shadow_depth.frag`: window depth into a colour target.
///
/// A colour target rather than the depth buffer because flutter_gpu gives no
/// way to sample a depth texture, and the workaround is in the engine rather
/// than in any one backend. `gl_FragCoord.z` is the right value *because* the
/// shadow camera is orthographic — under perspective it would be hyperbolic,
/// all its precision near the near plane, and comparing two of them would mean
/// nothing.
final class ShadowDepthShader extends CpuFragmentShader {
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
final class ShadowDistanceShader extends CpuFragmentShader {
  const ShadowDistanceShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) {
    final light = bindings.vec4('ShadowLight', 'light', Vector4.zero());
    final range = math.max(light.w, 1e-4);
    final world = Vector3(v[kVWorld], v[kVWorld + 1], v[kVWorld + 2]);
    final distance = (world - Vector3(light.x, light.y, light.z)).length;
    return Vector4((distance / range).clamp(0.0, 1.0), 0.0, 0.0, 1.0);
  }
}

/// Whether a cut-out caster covers this fragment — `gfx-60n`.
///
/// Shared by both masked stages because both ask the same question of the same
/// two numbers: the base colour map's alpha times the material's own alpha,
/// against the material's cutoff. glTF's MASK mode is a hard threshold rather
/// than coverage, and a shadow map holds one depth per texel, so a
/// half-transparent fragment either records or does not.
bool _maskPasses(ShaderBindings bindings, Float32List v) {
  final texture = bindings.textures['base_color_texture'];
  final mask = bindings.vec4('MaskInfo', 'mask', Vector4.zero());
  // No map bound is a caster with nothing to cut out, which passes: the engine
  // only selects these stages for a material that has one, and a stage that
  // discarded everything on a missing binding would turn a mistake into an
  // invisible shadow rather than a loud one.
  if (texture == null) return true;
  final alpha = texture.sample(v[kVUv], v[kVUv + 1]).w * mask.y;
  return alpha >= mask.x;
}

/// `shadow_depth_masked.frag`: window depth, where the caster is opaque
/// enough — `gfx-60n`.
///
/// Null is a discard here, which is what the rasteriser does with it, and it
/// is the whole stage: a leaf card that does not cut out casts the shadow of
/// its quad, which is a stack of dark slabs where the eye expects dappled
/// light.
final class ShadowDepthMaskedShader extends CpuFragmentShader {
  const ShadowDepthMaskedShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) =>
      _maskPasses(bindings, v) ? Vector4(c.coord.z, 0.0, 0.0, 1.0) : null;
}

/// `shadow_distance_masked.frag`: the point-light twin of the above.
final class ShadowDistanceMaskedShader extends CpuFragmentShader {
  const ShadowDistanceMaskedShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) {
    if (!_maskPasses(bindings, v)) return null;
    final light = bindings.vec4('ShadowLight', 'light', Vector4.zero());
    final range = math.max(light.w, 1e-4);
    final world = Vector3(v[kVWorld], v[kVWorld + 1], v[kVWorld + 2]);
    final distance = (world - Vector3(light.x, light.y, light.z)).length;
    return Vector4((distance / range).clamp(0.0, 1.0), 0.0, 0.0, 1.0);
  }
}

/// `shadow_transmittance.frag`: what a see-through caster lets through to
/// the sun — `ShadowSettings.translucentCasters`.
///
/// Green and blue are what it takes from red and green, alpha what it leaves
/// of blue, red nought so the depth beneath survives the blend; the GLSL
/// stage has the reasons, and this is the same arithmetic.
final class ShadowTransmittanceShader extends CpuFragmentShader {
  const ShadowTransmittanceShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) {
    final color = bindings.vec4('TransmittanceInfo', 'color', Vector4.zero());
    final light = bindings.vec4('TransmittanceInfo', 'light', Vector4.zero());
    final params = bindings.vec4('TransmittanceInfo', 'params', Vector4.zero());
    final opacity = color.w.clamp(0.0, 1.0);
    final transmission = params.x.clamp(0.0, 1.0);
    final map = bindings.textures['base_color_texture'];
    final texel = map?.sample(v[kVUv], v[kVUv + 1]) ?? Vector4.all(1.0);
    double body(double channel, double mapped) =>
        (1.0 - opacity) +
        opacity * transmission * math.max(channel, 0.0) * mapped;

    final normal = Vector3(v[kVNormal], v[kVNormal + 1], v[kVNormal + 2]);
    final length = normal.length;
    final facing = length > 0.0
        ? (normal.dot(Vector3(light.x, light.y, light.z)) / length).abs()
        : 1.0;
    final f0 = params.y.clamp(0.0, 1.0);
    final fresnel =
        f0 + (1.0 - f0) * math.pow(1.0 - facing.clamp(0.0, 1.0), 5.0);
    // What is reflected is lost only as far as it is turned away: 2 cos²θ
    // of it, held to one — `shadow_transmittance.frag` has the reasons.
    final lost = fresnel * math.min(2.0 * facing * facing, 1.0);
    // A caster whose photons are followed stops all of its light here.
    final stops = params.z > 0.5;
    double through(double channel, double mapped) => stops
        ? 0.0
        : math.sqrt(math.max(body(channel, mapped), 0.0)) * (1.0 - lost);
    return Vector4(
      0.0,
      1.0 - through(color.x, texel.x),
      1.0 - through(color.y, texel.y),
      through(color.z, texel.z),
    );
  }
}

/// `shadow_copy.frag`: one cascade's tile of the static atlas, into colour
/// and depth — `S1`.
final class ShadowCopyShader extends CpuFragmentShader {
  const ShadowCopyShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) {
    final source = bindings.textures['static_shadow_texture'];
    if (source == null) return null;
    final tile = bindings.vec4('ShadowCopyInfo', 'tile', Vector4.zero());
    final shift = bindings.vec4('ShadowCopyInfo', 'shift', Vector4.zero());
    final fromU = v[0] - shift.x;
    final fromV = v[1] - shift.y;
    final inside = fromU >= 0.0 && fromU <= 1.0 && fromV >= 0.0 && fromV <= 1.0;
    final stored = source
        .sample(
          tile.x + fromU.clamp(0.0, 1.0) * tile.z,
          tile.y + fromV.clamp(0.0, 1.0) * tile.w,
        )
        .x;
    // Nothing stays nothing: the far end is not a depth the move shifts. One
    // the ordinary way round, nought turned round, and mode two writes the
    // turned map back the ordinary way — `A2.8`, as `shadow_copy.frag`.
    final mode = shift.w;
    final nothing = mode > 0.5 ? 0.0 : 1.0;
    final moved = inside && stored != nothing
        ? (stored + shift.z).clamp(0.0, 1.0)
        : nothing;
    final depth = mode > 1.5 ? 1.0 - moved : moved;
    c.fragDepth = depth;
    return Vector4(depth, 0.0, 0.0, 1.0);
  }
}

/// `depth_predraw.frag`: a surface's depth where it covers the pixel, and no
/// colour — `A1.2`, `A1.3`.
///
/// The cut the lit stage's opaque variant leaves out, made here instead and
/// to the texel the same: the base colour map read with the same footprint
/// and level bias, its alpha times the material's and the vertex colour's,
/// against the cutoff or the world-anchored hash; then a cross-fading level's
/// share of the pixels from the same pattern the GLSL takes, interleaved
/// gradient noise at the pixel. Null is the discard; anything else is drawn
/// under a blend that keeps what is there.
final class DepthPredrawShader extends CpuFragmentShader {
  const DepthPredrawShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) {
    final mask = bindings.vec4('PredrawInfo', 'mask', Vector4(-1, 1, 1, 0));
    final cutoff = mask.x;
    double alpha() {
      final texture = bindings.textures['base_color_texture'];
      if (texture == null) return mask.y * v[kVColour + 3];
      final uv = uvFootprint(c, bias: mask.w);
      final texel = texture.sample(
        v[kVUv],
        v[kVUv + 1],
        du: uv.du,
        dv: uv.dv,
        dudx: uv.dudx,
        dvdx: uv.dvdx,
        dudy: uv.dudy,
        dvdy: uv.dvdy,
      );
      return texel.w * mask.y * v[kVColour + 3];
    }

    if (cutoff >= 0.0 && cutoff <= 1.0) {
      if (alpha() < cutoff) return null;
    } else if (cutoff < -1.5) {
      final noise = hashedAlphaNoise(
        v[kVWorld],
        v[kVWorld + 1],
        v[kVWorld + 2],
        cutoff,
      );
      if (alpha() < noise) return null;
    }

    final share = mask.z;
    if (share < 1.0) {
      double fract(double x) => x - x.floorToDouble();
      final pattern = fract(
        52.9829189 * fract(c.coord.x * 0.06711056 + c.coord.y * 0.00583715),
      );
      final kept = share >= 0.0 ? pattern < share : pattern >= 1.0 + share;
      if (!kept) return null;
    }
    return Vector4.zero();
  }
}

/// `shadow_tile_reset.frag`: one, the far end of the range.
///
/// A texel no caster covers means "nothing between the light and its range",
/// which is the right answer for a direction with nothing in it.
final class ShadowTileResetShader extends CpuFragmentShader {
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
final class ShadowTileResetVertexShader extends CpuVertexShader {
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

/// `caustic_surface.frag`: a refracting caster's normal and depth, as the sun
/// sees it — `ShadowSettings.caustics`.
final class CausticSurfaceShader extends CpuFragmentShader {
  const CausticSurfaceShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) {
    final normal = Vector3(v[kVNormal], v[kVNormal + 1], v[kVNormal + 2]);
    if (normal.length2 > 0.0) normal.normalize();
    return Vector4(normal.x, normal.y, normal.z, c.coord.z);
  }
}

/// `caustic_photon.vert`: one photon followed through a caster to where it
/// lands, sized by where its neighbours land — the same arithmetic, with the
/// instance index as the texel.
final class CausticPhotonVertexShader extends CpuVertexShaderByIndex {
  const CausticPhotonVertexShader();

  @override
  int get varyingCount => 5;

  @override
  Vector4 run(Float32List a, ShaderBindings bindings, Float32List out) =>
      runAt(0, 0, a, bindings, out);

  static Vector2 _mapUv(Vector4 p) => Vector2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);

  static double _schlick(double f0, double cosine) {
    final c = (1.0 - cosine).clamp(0.0, 1.0);
    return f0 + (1.0 - f0) * c * c * c * c * c;
  }

  /// GLSL's `refract`, zero on total internal reflection.
  static Vector3 _refract(Vector3 i, Vector3 n, double eta) {
    final d = n.dot(i);
    final k = 1.0 - eta * eta * (1.0 - d * d);
    if (k < 0.0) return Vector3.zero();
    return i * eta - n * (eta * d + math.sqrt(k));
  }

  static Vector4 _sample(BoundTexture? t, double u, double v) =>
      t?.sample(u.clamp(0.0, 1.0), v.clamp(0.0, 1.0)) ?? Vector4.zero();

  /// `Follow`: where the photon at [u], [v] lands in clip space, and what it
  /// carries; null if it does not land.
  static (Vector2, Vector3)? _follow(ShaderBindings b, double u, double v) {
    const block = 'CausticInfo';
    final mapToWorld = b.mat4(block, 'map_to_world');
    final worldToMap = b.mat4(block, 'world_to_map');
    final worldToTile = b.mat4(block, 'world_to_tile');
    final worldToClip = b.mat4(block, 'world_to_clip');
    final light = b.vec4(block, 'light', Vector4.zero());
    final optics = b.vec4(block, 'optics', Vector4.zero());
    final tint = b.vec4(block, 'tint', Vector4.zero());
    final attenuation = b.vec4(block, 'attenuation', Vector4.zero());
    final frontMap = b.textures['caustic_front'];
    final backMap = b.textures['caustic_back'];
    final depthMap = b.textures['caustic_depth'];

    final front = _sample(frontMap, u, v);
    final frontNormal = Vector3(front.x, front.y, front.z);
    if (front.w >= 1.0 || frontNormal.length2 < 0.25) return null;

    final ndc = Vector4(u * 2.0 - 1.0, (0.5 - v) * 2.0, front.w, 1.0);
    final entry4 = mapToWorld.transform(ndc);
    final entry = Vector3(entry4.x, entry4.y, entry4.z);
    final depthAxis = mapToWorld.transform(Vector4(0, 0, 1, 0));
    final range = Vector3(depthAxis.x, depthAxis.y, depthAxis.z).length;

    final l = Vector3(light.x, light.y, light.z)..normalize();
    var n1 = frontNormal.normalized();
    if (n1.dot(l) > 0.0) n1 = -n1;
    final index = math.max(optics.x, 1.0);
    final inside = _refract(l, n1, 1.0 / index);

    final back = _sample(backMap, u, v);
    if (back.w <= front.w) return null;
    final across = (back.w - front.w) * range;
    final exit = entry + inside * (across / math.max(inside.dot(l), 0.2));
    final atMap = _mapUv(
      worldToMap.transform(Vector4(exit.x, exit.y, exit.z, 1)),
    );
    final there = _sample(backMap, atMap.x, atMap.y);
    final thereNormal = Vector3(there.x, there.y, there.z);
    var n2 = thereNormal.length2 > 0.25
        ? thereNormal.normalized()
        : Vector3(back.x, back.y, back.z).normalized();
    if (n2.dot(inside) < 0.0) n2 = -n2;
    var outRay = _refract(inside, -n2, index);
    if (outRay.length2 < 1e-6) return null;
    outRay = outRay.normalized();
    if (outRay.dot(l) < 0.3) return null;

    final f0 = optics.y;
    final keep =
        (1.0 - _schlick(f0, l.dot(n1).abs())) *
        (1.0 - _schlick(f0, outRay.dot(n2).abs()));
    var er = tint.x * keep, eg = tint.y * keep, eb = tint.z * keep;
    final fading = optics.z;
    if (fading > 0.0) {
      final depth = (exit - entry).length / fading;
      er *= math.pow(math.max(attenuation.x, 1e-4), depth);
      eg *= math.pow(math.max(attenuation.y, 1e-4), depth);
      eb *= math.pow(math.max(attenuation.z, 1e-4), depth);
    }

    var p = exit.clone();
    final down = math.max(outRay.dot(l), 0.05);
    for (var k = 0; k < 4; k++) {
      final q = worldToTile.transform(Vector4(p.x, p.y, p.z, 1));
      final at = _mapUv(q);
      final receiver = _sample(depthMap, at.x, at.y).x;
      var advance = (receiver - q.z) * range / down;
      if (k == 0) advance = math.max(advance, 0.0);
      p += outRay * advance;
    }
    final landed = worldToTile.transform(Vector4(p.x, p.y, p.z, 1));
    final landedAt = _mapUv(landed);
    final under = _sample(depthMap, landedAt.x, landedAt.y).x;
    if ((under - landed.z).abs() * range > 0.02) return null;

    final clip = worldToClip.transform(Vector4(p.x, p.y, p.z, 1));
    return (Vector2(clip.x / clip.w, clip.y / clip.w), Vector3(er, eg, eb));
  }

  static Vector2 _atLeast(Vector2 a, Vector2 fallback, double least) {
    final size = a.length;
    if (size < 1e-9) return fallback.normalized() * least;
    return size < least ? a * (least / size) : a;
  }

  @override
  Vector4 runAt(
    int vertexIndex,
    int instanceIndex,
    Float32List a,
    ShaderBindings b,
    Float32List out,
  ) {
    out[0] = a[0];
    out[1] = a[1];
    out[2] = 0.0;
    out[3] = 0.0;
    out[4] = 0.0;
    final away = Vector4(4.0, 4.0, 0.5, 1.0);
    final grid = b.vec4('CausticInfo', 'grid', Vector4.zero());
    final n = grid.x.round();
    if (n < 1) return away;
    final u = (instanceIndex % n + 0.5) / n;
    final v = (instanceIndex ~/ n + 0.5) / n;
    final texel = 1.0 / n;

    final here = _follow(b, u, v);
    if (here == null) return away;
    final (at, energy) = here;

    final spacingX = Vector2(grid.z, 0.0);
    final spacingY = Vector2(0.0, grid.w);
    var across = spacingX;
    final nextX = _follow(b, u + texel, v);
    if (nextX != null) {
      across = nextX.$1 - at;
    } else {
      final prevX = _follow(b, u - texel, v);
      if (prevX != null) across = at - prevX.$1;
    }
    var down = spacingY;
    final nextY = _follow(b, u, v + texel);
    if (nextY != null) {
      down = nextY.$1 - at;
    } else {
      final prevY = _follow(b, u, v - texel);
      if (prevY != null) down = at - prevY.$1;
    }
    final least = grid.y;
    final ax = _atLeast(across * 1.5, spacingX, least);
    final by = _atLeast(down * 1.5, spacingY, least);
    final area = math.max((ax.x * by.y - ax.y * by.x).abs(), least * least);
    final share = grid.z * grid.w;
    final scale = share / (1.0471976 * area);
    out[2] = energy.x * scale;
    out[3] = energy.y * scale;
    out[4] = energy.z * scale;
    return Vector4(
      at.x + a[0] * ax.x + a[1] * by.x,
      at.y + a[0] * ax.y + a[1] * by.y,
      0.5,
      1.0,
    );
  }
}

/// `caustic_photon.frag`: a photon's quad, given back into the atlas.
final class CausticPhotonShader extends CpuFragmentShader {
  const CausticPhotonShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) {
    final r2 = v[0] * v[0] + v[1] * v[1];
    if (r2 >= 1.0) return null;
    final k = (1.0 - r2) * (1.0 - r2);
    return Vector4(0.0, v[2] * k, v[3] * k, v[4] * k);
  }
}
