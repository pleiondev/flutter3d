/// The particle stages: billboards, sprite-textured and radial, plus the
/// per-instance mesh variant.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_color.dart';

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
  const ParticleTexturedShader();

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
    final scale = v[3] * texel.w * fogged;
    return Vector4(
      v[0] * texel.x * scale,
      v[1] * texel.y * scale,
      v[2] * texel.z * scale,
      1.0,
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
  const ParticleShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final cx = v[4] * 2.0 - 1.0;
    final cy = v[5] * 2.0 - 1.0;
    final radius = math.sqrt(cx * cx + cy * cy);
    final falloff = 1.0 - smoothstep(0.0, 1.0, radius);
    final intensity = falloff * falloff;

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
