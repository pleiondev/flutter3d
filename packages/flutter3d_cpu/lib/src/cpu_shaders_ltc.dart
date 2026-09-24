/// `lib/ltc.glsl`: the GGX lobe over a rectangle light, by linearly
/// transformed cosines — `L7`.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';

/// `LtcUv`.
({double u, double v}) _uv(double x, double y, double half) {
  final u = x * (63.0 / 64.0) + 0.5 / 64.0;
  final v = y * (63.0 / 64.0) + 0.5 / 64.0;
  return (u: u, v: (v + half) * 0.5);
}

/// `LtcEdge`.
Vector3 _edge(Vector3 a, Vector3 b) {
  final axis = a.cross(b);
  final len = axis.length;
  final angle = math.acos(a.dot(b).clamp(-1.0, 1.0));
  return len > 1e-6 ? (axis..scale(angle / (len * 6.2831853))) : Vector3.zero();
}

/// `LtcRectangle`: x the lobe integrated over the rectangle, y the norm, z
/// the Fresnel term.
Vector3 ltcRectangle(
  BoundTexture table,
  Vector3 n,
  Vector3 v,
  double roughness,
  List<Vector3> corners,
) {
  final x = roughness.clamp(0.0, 1.0);
  final y = math.sqrt((1.0 - n.dot(v)).clamp(0.0, 1.0));
  final upper = _uv(x, y, 0.0);
  final lower = _uv(x, y, 1.0);
  final inverse = table.sample(upper.u, upper.v);
  final fit = table.sample(lower.u, lower.v);

  final along = v - n * n.dot(v);
  final alongLength = along.length;
  final t1 = alongLength > 1e-5
      ? (along..scale(1.0 / alongLength))
      : (n.cross(
          n.z.abs() < 0.999 ? Vector3(0.0, 0.0, 1.0) : Vector3(1.0, 0.0, 0.0),
        )..normalize());
  final t2 = n.cross(t1);

  // `mat3(vec3(m00, 0, m02), vec3(0, 1, 0), vec3(m20, 0, m22))`, columns.
  Vector3 transform(Vector3 p) {
    final a = p.dot(t1);
    final b = p.dot(t2);
    final c = p.dot(n);
    return Vector3(
      inverse.x * a + inverse.z * c,
      b,
      inverse.y * a + inverse.w * c,
    )..normalize();
  }

  final l = <Vector3>[for (final p in corners) transform(p)];
  final f =
      -(_edge(l[0], l[1]) +
          _edge(l[1], l[2]) +
          _edge(l[2], l[3]) +
          _edge(l[3], l[0]));
  final len = f.length;
  final z = len > 1e-9 ? f.z / len : 0.0;
  final at = _uv(z * 0.5 + 0.5, len.clamp(0.0, 1.0), 1.0);
  final sphere = table.sample(at.u, at.v).w;
  return Vector3(math.max(len * sphere, 0.0), fit.x, fit.y);
}
