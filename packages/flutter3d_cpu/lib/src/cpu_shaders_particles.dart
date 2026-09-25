/// The particle stages: billboards, sprite-textured and radial, plus the
/// per-instance mesh variant.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_color.dart';
import 'cpu_shaders_lighting.dart';

/// `lib/particle_soft.glsl`'s `SoftParticleFade`: how much of a particle
/// fragment at world `(x, y, z)` is left once it nears the scene the surface
/// buffer holds at [c]'s pixel — one a softness in front or further, nought
/// at it, and one where nothing was drawn.
///
/// One as well while no depth is bound, which is never how a soft stage is
/// drawn and is how a test that leaves the slot empty reads the stage.
double softParticleFade(
  ShaderBindings b,
  FragmentContext c,
  double x,
  double y,
  double z,
) {
  final surface = b.textures['scene_depth_texture'];
  if (surface == null) return 1.0;
  const block = 'SoftParticleInfo';
  final target = b.vec4(block, 'target', Vector4.zero());
  final eye = b.vec4(block, 'eye', Vector4.zero());
  final forward = b.vec4(block, 'forward', Vector4.zero());
  // `FragCoordFromTop`.
  final row = target.z > 0.0 ? target.z - c.coord.y : c.coord.y;
  final stored = surface.sample(c.coord.x * target.x, row * target.y).w;
  final depth =
      (x - eye.x) * forward.x +
      (y - eye.y) * forward.y +
      (z - eye.z) * forward.z;
  final fade = ((stored - depth) * target.w).clamp(0.0, 1.0);
  return stored > 0.0 ? fade : 1.0;
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

/// `particle_textured.frag`: a sprite, premultiplied, fogged, and mipped.
///
/// The one stage in this file that asks for a mip level, and therefore the one
/// place the derivative machinery is used. Varying four and five are the
/// texture coordinate — `ParticleVertexShader` puts them there — and nothing
/// but this stage could know that, which is why the derivative is passed in
/// rather than read off the texture.
final class ParticleTexturedShader implements CpuFragmentShader {
  const ParticleTexturedShader({this.soft = false});

  /// `particle_textured_soft.frag`: the same, faded by [softParticleFade].
  final bool soft;

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final texture = b.textures['particle_texture'];
    var texel = Vector4(1, 1, 1, 1);
    if (texture != null) {
      // The larger of the two directions per axis. A hardware sampler uses the
      // longer side of the whole footprint parallelogram; taking the maximum of
      // the axis-aligned components is the same thing for a quad facing the
      // camera, which every billboard is by construction.
      var du = 0.0;
      var dv = 0.0;
      final ddx = c.ddx;
      final ddy = c.ddy;
      if (ddx != null && ddy != null) {
        du = math.max(ddx[4].abs(), ddy[4].abs());
        dv = math.max(ddx[5].abs(), ddy[5].abs());
      }
      texel = texture.sample(v[4], v[5], du: du, dv: dv);
    }

    var fogged = 1.0;
    final fog = b.vec4('FogInfo', 'fog', Vector4.zero());
    if (fog.w > 0.0) {
      final eye = b.vec4('FogInfo', 'eye', Vector4.zero());
      final d =
          (Vector3(v[6], v[7], v[8]) - Vector3(eye.x, eye.y, eye.z)).length;
      fogged = math.exp(-fog.w * d).clamp(0.0, 1.0);
    }

    // The texture's alpha is coverage and the particle's is brightness, so the
    // two multiply.
    final scale =
        v[3] *
        texel.w *
        fogged *
        (soft ? softParticleFade(b, c, v[6], v[7], v[8]) : 1.0);
    return Vector4(
      v[0] * texel.x * scale,
      v[1] * texel.y * scale,
      v[2] * texel.z * scale,
      1.0,
    );
  }
}

/// `particle_six_way.frag` — `N6`: smoke lit by the scene's lights through
/// six pictures of itself, blended over what is behind it.
///
/// The same varyings as the sprite stage: colour in 0..3, the cell's texture
/// coordinate in 4..5, the world position in 6..8.
final class ParticleSixWayShader implements CpuFragmentShader {
  const ParticleSixWayShader({this.soft = false});

  /// `particle_six_way_soft.frag`: the same, its coverage faded by
  /// [softParticleFade].
  final bool soft;

  static const String _block = 'SixWayInfo';

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    var du = 0.0;
    var dv = 0.0;
    final ddx = c.ddx;
    final ddy = c.ddy;
    if (ddx != null && ddy != null) {
      du = math.max(ddx[4].abs(), ddy[4].abs());
      dv = math.max(ddx[5].abs(), ddy[5].abs());
    }
    Vector4 read(String name) =>
        b.textures[name]?.sample(v[4], v[5], du: du, dv: dv) ??
        Vector4(1.0, 1.0, 1.0, 1.0);
    final positive = read('six_way_positive');
    final negative = read('six_way_negative');

    final right = b.vec4(_block, 'right', Vector4.zero()).xyz;
    final up = b.vec4(_block, 'up', Vector4.zero()).xyz;
    final forward = b.vec4(_block, 'forward', Vector4.zero()).xyz;
    double response(Vector3 l) {
      final x = l.dot(right);
      final y = l.dot(up);
      final z = l.dot(forward);
      return x * x * (x > 0.0 ? positive.x : negative.x) +
          y * y * (y > 0.0 ? positive.y : negative.y) +
          z * z * (z > 0.0 ? positive.z : negative.z);
    }

    final world = Vector3(v[6], v[7], v[8]);
    final lit = Vector3.zero();
    final count = contributorLightCount(b, world);
    for (var i = 0; i < count; i++) {
      final light = contributorLight(b, i, world);
      lit.addScaled(light.radiance, response(light.toLight));
    }

    final mean =
        (positive.x +
            positive.y +
            positive.z +
            negative.x +
            negative.y +
            negative.z) /
        6.0;
    final ambient = b.vec4(_block, 'ambient', Vector4.zero());
    final emission = b.vec4(_block, 'emission', Vector4.zero());
    final colour = Vector3(
      v[0] * (lit.x + ambient.x * mean) + emission.x * negative.w,
      v[1] * (lit.y + ambient.y * mean) + emission.y * negative.w,
      v[2] * (lit.z + ambient.z * mean) + emission.z * negative.w,
    );

    // A mix toward the fog, not the additive stages' attenuation: this one
    // covers what is behind it.
    final fog = b.vec4('FogInfo', 'fog', Vector4.zero());
    if (fog.w > 0.0) {
      final eye = b.vec4('FogInfo', 'eye', Vector4.zero());
      final d = (world - Vector3(eye.x, eye.y, eye.z)).length;
      final fogged = math.exp(-fog.w * d).clamp(0.0, 1.0);
      colour
        ..x = fog.x + (colour.x - fog.x) * fogged
        ..y = fog.y + (colour.y - fog.y) * fogged
        ..z = fog.z + (colour.z - fog.z) * fogged;
    }

    // Coverage, not colour: the blend is premultiplied, so a fading puff has
    // to let what is behind it through as well.
    final coverage =
        (v[3] * positive.w).clamp(0.0, 1.0) *
        (soft ? softParticleFade(b, c, v[6], v[7], v[8]) : 1.0);
    return Vector4(
      colour.x * coverage,
      colour.y * coverage,
      colour.z * coverage,
      coverage,
    );
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
  const ParticleShader({this.soft = false});

  /// `particle_soft.frag`: the same, faded by [softParticleFade].
  final bool soft;

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final cx = v[4] * 2.0 - 1.0;
    final cy = v[5] * 2.0 - 1.0;
    final radius = math.sqrt(cx * cx + cy * cy);
    final falloff = 1.0 - smoothstep(0.0, 1.0, radius);
    final intensity =
        falloff *
        falloff *
        (soft ? softParticleFade(b, c, v[6], v[7], v[8]) : 1.0);

    var fogged = 1.0;
    final fog = b.vec4('FogInfo', 'fog', Vector4.zero());
    if (fog.w > 0.0) {
      final eye = b.vec4('FogInfo', 'eye', Vector4.zero());
      final d =
          (Vector3(v[6], v[7], v[8]) - Vector3(eye.x, eye.y, eye.z)).length;
      fogged = math.exp(-fog.w * d).clamp(0.0, 1.0);
    }

    final scale = v[3] * intensity * fogged;
    // Alpha one with the colour premultiplied: these draw additively, so the
    // alpha channel is not what decides how much of them lands.
    return Vector4(v[0] * scale, v[1] * scale, v[2] * scale, 1.0);
  }
}

/// `splat.frag` — `gfx-80n`.
///
/// The same varyings the particle stage reads, because it shares
/// `particle.vert`: colour in 0..3, the quad's own coordinates in 4..5, the
/// world position in 6..8. What differs is that `v_uv` here is not a texture
/// coordinate but the fragment's position in the Gaussian's own frame, in
/// standard deviations, already centred — so there is no `* 2 - 1`.
final class SplatShader implements CpuFragmentShader {
  const SplatShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final power = -0.5 * (v[4] * v[4] + v[5] * v[5]);
    // Cut off at three standard deviations, where the falloff is under a
    // hundredth: a Gaussian never reaches zero, so without this the quad's own
    // square edge shows and the cloud reads as a field of faint rectangles.
    if (power < -4.5) return null;

    final alpha = v[3] * math.exp(power);
    if (alpha < 1.0 / 255.0) return null;

    var r = v[0];
    var g = v[1];
    var bl = v[2];
    final fog = b.vec4('FogInfo', 'fog', Vector4.zero());
    if (fog.w > 0.0) {
      final eye = b.vec4('FogInfo', 'eye', Vector4.zero());
      final d =
          (Vector3(v[6], v[7], v[8]) - Vector3(eye.x, eye.y, eye.z)).length;
      final visibility = math.exp(-fog.w * d).clamp(0.0, 1.0);
      // A mix rather than an attenuation, which is the opposite of the particle
      // stage and for the opposite reason: this is blended, so a splat that
      // faded toward black would put black into the wall behind it.
      r = fog.x + (r - fog.x) * visibility;
      g = fog.y + (g - fog.y) * visibility;
      bl = fog.z + (bl - fog.z) * visibility;
    }

    // Premultiplied, for the blend state this draws under.
    return Vector4(r * alpha, g * alpha, bl * alpha, alpha);
  }
}

/// `splat_hashed.frag` — `N5`: the splat kept or dropped whole at a pixel,
/// against noise, and written opaque.
///
/// The identity hash is whole-number arithmetic under 2^24, exact in doubles
/// and in a GPU's floats alike, so a splat reads the same cell of the noise
/// here as on a GPU — see [splatNoiseOffset].
final class SplatHashedShader implements CpuFragmentShader {
  const SplatHashedShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final power = -0.5 * (v[4] * v[4] + v[5] * v[5]);
    if (power < -4.5) return null;

    final alpha = v[3] * math.exp(power);
    if (alpha < 1.0 / 255.0) return null;

    // The splat's identity as a whole number — millimetres along the view
    // axis, the colour in 8-bit steps — and the offset into the noise it
    // hashes to.
    final eye = b.vec4('SplatHashInfo', 'eye', Vector4.zero());
    final forward = b.vec4('SplatHashInfo', 'forward', Vector4.zero());
    final along =
        (v[6] - eye.x) * forward.x +
        (v[7] - eye.y) * forward.y +
        (v[8] - eye.z) * forward.z;
    final identity =
        ((along * 1000.0).floorToDouble() +
            (v[0] * 255.0 +
                    v[1] * 255.0 * 7.0 +
                    v[2] * 255.0 * 31.0 +
                    v[3] * 255.0 * 127.0)
                .floorToDouble()) %
        4096.0;
    final (offsetX, offsetY) = splatNoiseOffset(identity);

    // This frame's slice of the blue noise, at the pixel moved by the offset.
    final table = b.textures['blue_noise_texture'];
    if (table == null) return null;
    final frame = b.vec4('SplatHashInfo', 'frame', Vector4.zero());
    final slice = frame.x;
    // `FragCoordFromTop`.
    final row = frame.y > 0.0 ? frame.y - c.coord.y : c.coord.y;
    final cellX = (c.coord.x.floorToDouble() + offsetX) % 64.0;
    final cellY = (row.floorToDouble() + offsetY) % 64.0;
    final cornerX = (slice % 8.0).floorToDouble() * 64.0;
    final cornerY = (slice / 8.0).floorToDouble() * 64.0;
    final threshold =
        table
            .sample(
              (cornerX + cellX + 0.5) / 512.0,
              (cornerY + cellY + 0.5) / 256.0,
            )
            .x *
        (255.0 / 256.0);

    if (alpha <= threshold) return null;

    final fog = b.vec4('FogInfo', 'fog', Vector4.zero());
    if (fog.w <= 0.0) return Vector4(v[0], v[1], v[2], 1.0);
    final fogEye = b.vec4('FogInfo', 'eye', Vector4.zero());
    final d =
        (Vector3(v[6], v[7], v[8]) - Vector3(fogEye.x, fogEye.y, fogEye.z))
            .length;
    final visibility = math.exp(-fog.w * d).clamp(0.0, 1.0);
    return Vector4(
      fog.x + (v[0] - fog.x) * visibility,
      fog.y + (v[1] - fog.y) * visibility,
      fog.z + (v[2] - fog.z) * visibility,
      1.0,
    );
  }
}

/// `splat_hashed.frag`'s offset into the 64 × 64 noise tile for a splat's
/// [identity], a whole number in `[0, 4096)`: column and row, each whole.
///
/// A permutation of the tile's cells, so two identities never share one: an
/// affine step and `2a² + a` modulo 4096, then the high six bits stirred into
/// the low six. Every product stays under 2^24 and every divisor is a power
/// of two, so a GPU's 32-bit floats and these doubles give the same answer.
(double, double) splatNoiseOffset(double identity) {
  final affine = (identity * 1597.0 + 2531.0) % 4096.0;
  final mixed = (affine * ((2.0 * affine + 1.0) % 4096.0)) % 4096.0;
  final row = (mixed / 64.0).floorToDouble();
  return ((mixed + row * 37.0) % 64.0, row);
}
