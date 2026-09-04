/// Colour and encoding helpers every stage in `cpu_shaders_*.dart` shares —
/// the Dart transcription of `color.glsl` plus the tone mapper from
/// `composite.frag`.
///
/// Split out on its own because nearly everything else here imports it: the
/// lighting models, the sky, the particles and the post-processing passes all
/// convert between linear and sRGB or fade toward the fog, and none of that
/// depends on a surface, a light or a shadow — only on a colour.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_layout.dart';

/// sRGB to linear, per `color.glsl`.
double toLinear(double c) =>
    c < 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

/// Linear to sRGB, the inverse.
double toSrgb(double c) => c < 0.0031308
    ? c * 12.92
    : 1.055 * math.pow(math.max(c, 0.0), 1.0 / 2.4) - 0.055;

double smoothstep(double edge0, double edge1, double x) {
  // **Two equal edges are a step, not a division.** GLSL leaves this
  // undefined; Dart does not, and what it does is `0/0`, which is a NaN that
  // multiplies through the rest of the shader and comes out as a black pixel
  // nobody can trace back. The engine's own copy in `sky_settings.dart` has had
  // this line since it was written and this one lost it.
  if (edge0 == edge1) return x < edge0 ? 0.0 : 1.0;
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

double fract(double x) => x - x.floor();

/// `EncodeOctahedral` from `color.glsl`: a unit normal in two channels.
Vector2 encodeOctahedral(Vector3 n) {
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

/// `DecodeOctahedral`, the inverse of what the surface buffer stored.
Vector3 decodeOctahedral(double ex, double ey) {
  final x = ex * 2.0 - 1.0;
  final y = ey * 2.0 - 1.0;
  final n = Vector3(x, y, 1.0 - x.abs() - y.abs());
  final t = math.max(-n.z, 0.0);
  n.x += n.x >= 0.0 ? -t : t;
  n.y += n.y >= 0.0 ? -t : t;
  return n..normalize();
}

/// `WriteSurfaceGeometry`: the octahedral normal, the roughness, the depth.
///
/// Called from the same place that writes colour, so a surface cannot be lit
/// into the frame without also describing itself — which is the failure that
/// leaves a screen-space effect reflecting whatever was in the buffer before.
///
/// A debug pass takes the buffer over rather than getting one of its own, the
/// way the GLSL does: the surface buffer already has an attachment, a viewer
/// and a golden, and a second one would need all three built before it could
/// answer anything.
void writeSurface(FragmentContext c, Vector3 normal, double roughness) {
  // A debug pass takes the buffer over rather than getting one of its own, as
  // `WriteSurfaceGeometry` does with `g_debug_surface_on`.
  final debug = c.debugSurface;
  if (debug != null) {
    c.surface = Vector4(debug.x, debug.y, debug.z, c.coord.z);
    return;
  }
  final encoded = encodeOctahedral(normal);
  c.surface = Vector4(
    encoded.x,
    encoded.y,
    roughness.clamp(0.0, 1.0),
    c.coord.z,
  );
}

/// `ApplyFog` from `color.glsl`: fades [colour] toward the fog with distance.
///
/// Exponential rather than linear, for the reason the GLSL gives: linear fog
/// has a visible plane where it starts. The early return at zero density is
/// not an optimisation — it is what keeps a scene with no fog byte-identical,
/// which is what the golden sets are recorded against.
Vector3 applyFog(Vector3 colour, Float32List v, ShaderBindings b) {
  final fog = b.vec4('FogInfo', 'fog', Vector4.zero());
  final density = fog.w;
  if (density <= 0.0) return colour;

  final eye = b.vec4('FogInfo', 'eye', Vector4.zero());
  final dx = v[kVWorld] - eye.x;
  final dy = v[kVWorld + 1] - eye.y;
  final dz = v[kVWorld + 2] - eye.z;
  final distance = math.sqrt(dx * dx + dy * dy + dz * dz);
  final t = math.exp(-density * distance).clamp(0.0, 1.0);

  return Vector3(
    fog.x * (1.0 - t) + colour.x * t,
    fog.y * (1.0 - t) + colour.y * t,
    fog.z * (1.0 - t) + colour.z * t,
  );
}

/// `WriteSurface` from `color.glsl`: the lit colour, faded by the fog, written
/// beside the surface geometry.
///
/// One function rather than two calls at each of five sites, because that is
/// what the GLSL is — there the fog and the geometry are written together, and
/// a transcription that splits them is one where a shader can be fogged and the
/// next one forgotten. That is exactly what had happened: of everything drawn,
/// only the three particle shaders faded with distance, and every road, wall
/// and car was drawn at full contrast to the horizon. A test that passed
/// `FogSettings` to this rasteriser was measuring a renderer with no weather.
Vector4 writeLit(
  FragmentContext c,
  Float32List v,
  ShaderBindings b, {
  required Vector3 colour,
  required double alpha,
  required Vector3 normal,
  required double roughness,
}) {
  writeSurface(c, normal, roughness);
  final fogged = applyFog(colour, v, b);
  return Vector4(fogged.x, fogged.y, fogged.z, alpha);
}

/// The Khronos PBR Neutral tone mapper, from `composite.frag`.
///
/// Transcribed rather than replaced with something simpler: this is the one
/// part of the chain that is pure arithmetic on a colour, so a Reinhard curve
/// here would make every cell of the comparison differ for a reason that has
/// nothing to do with the backend.
Vector3 tonemapNeutral(Vector3 colour) {
  const startCompression = 0.8 - 0.04;
  const desaturation = 0.15;

  final minChannel = math.min(colour.x, math.min(colour.y, colour.z));
  final offset = minChannel < 0.08
      ? minChannel - 6.25 * minChannel * minChannel
      : 0.04;
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
