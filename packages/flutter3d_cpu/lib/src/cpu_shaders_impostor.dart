/// `impostor.vert` and `lighting/impostor.frag`: an octahedral impostor's
/// card, and the lit stage that reads its atlases — `C4`.
///
/// See the GLSL for the layout and the reasoning, and `lib/impostor.glsl` for
/// the grid. This is the same arithmetic in the same order, down to the
/// selects that pick a triangle of the grid.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_color.dart';
import 'cpu_shaders_layout.dart';
import 'cpu_shaders_lighting.dart';
import 'cpu_shaders_surface.dart';

/// `kImpostorGrid`.
const double _kGrid = 8.0;

/// `ImpostorEncode`.
Vector2 _encode(Vector3 d) {
  final l1 = math.max(d.x.abs() + d.y.abs() + d.z.abs(), 1e-8);
  final px = d.x / l1, py = d.z / l1;
  final sx = px >= 0.0 ? 1.0 : -1.0, sy = py >= 0.0 ? 1.0 : -1.0;
  final (x, y) = d.y >= 0.0
      ? (px, py)
      : ((1.0 - py.abs()) * sx, (1.0 - px.abs()) * sy);
  return Vector2(x * 0.5 + 0.5, y * 0.5 + 0.5);
}

/// `ImpostorDecode`.
Vector3 _decode(double u, double v) {
  final px = u * 2.0 - 1.0, py = v * 2.0 - 1.0;
  final y = 1.0 - px.abs() - py.abs();
  final sx = px >= 0.0 ? 1.0 : -1.0, sy = py >= 0.0 ? 1.0 : -1.0;
  final (x, z) = y >= 0.0
      ? (px, py)
      : ((1.0 - py.abs()) * sx, (1.0 - px.abs()) * sy);
  return Vector3(x, y, z)..normalize();
}

/// `ImpostorRight`.
Vector3 _right(Vector3 d) {
  final up = d.y.abs() > 0.999 ? Vector3(0, 0, -1) : Vector3(0, 1, 0);
  return up.cross(d)..normalize();
}

/// The impostor card's vertex stage — `impostor.vert`.
final class ImpostorVertexShader implements CpuVertexShaderByIndex {
  const ImpostorVertexShader();

  @override
  int get varyingCount => kMeshVaryings;

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
    final mvp = bindings.mat4('FrameInfo', 'mvp');
    final model = bindings.mat4('FrameInfo', 'model');
    final normalMatrix = bindings.mat4('FrameInfo', 'normal_matrix');

    final radius = a[kTangent + 3];
    final u = a[kTexcoord], v = a[kTexcoord + 1];
    final centre = Vector3(
      a[kPosition] - (u * 2.0 - 1.0) * radius,
      a[kPosition + 1] - (1.0 - v * 2.0) * radius,
      a[kPosition + 2],
    );

    // `MvpRow`: row r of the matrix, which `Matrix4.getRow` reads directly.
    final rx = mvp.getRow(0), ry = mvp.getRow(1);
    final rz = mvp.getRow(2), rw = mvp.getRow(3);
    final yw = ry.xyz.cross(rw.xyz);
    final wx = rw.xyz.cross(rx.xyz);
    final xy = rx.xyz.cross(ry.xyz);
    final det = rx.xyz.dot(yw);
    final singular = det.abs() <= 1e-20;
    final toEye = singular
        ? -rz.xyz
        : (yw * rx.w + wx * ry.w + xy * rw.w).scaled(-1.0 / det) - centre;
    final d = toEye.dot(toEye) > 1e-20
        ? (toEye..normalize())
        : (Vector3(a[kNormal], a[kNormal + 1], a[kNormal + 2])..normalize());

    final right = _right(d);
    final up = d.cross(right);
    final corner =
        centre +
        (right * (u * 2.0 - 1.0) + up * (1.0 - v * 2.0)).scaled(radius);

    final Vector4 world = model * Vector4(corner.x, corner.y, corner.z, 1.0);
    out[kVWorld] = world.x;
    out[kVWorld + 1] = world.y;
    out[kVWorld + 2] = world.z;

    final Vector3 facing = normalMatrix.getRotation() * d;
    facing.normalize();
    out[kVNormal] = facing.x;
    out[kVNormal + 1] = facing.y;
    out[kVNormal + 2] = facing.z;

    final Vector3 worldRight = model.getRotation() * right;
    worldRight.normalize();
    out[kVTangent] = worldRight.x;
    out[kVTangent + 1] = worldRight.y;
    out[kVTangent + 2] = worldRight.z;
    out[kVTangent + 3] = 1.0;

    out[kVUv] = u;
    out[kVUv + 1] = v;
    out[kVColour] = d.x;
    out[kVColour + 1] = d.y;
    out[kVColour + 2] = d.z;
    out[kVColour + 3] = a[kColour + 3];
    out[kVLightmap] = 0.0;
    out[kVLightmap + 1] = 0.0;

    return mvp * Vector4(corner.x, corner.y, corner.z, 1.0);
  }
}

/// `ImpostorViewUv`: view [cellX], [cellY] of the grid, read at [offset].
(double, double) _viewUv(double cellX, double cellY, Vector3 offset) {
  final d = _decode(cellX / (_kGrid - 1.0), cellY / (_kGrid - 1.0));
  final right = _right(d);
  final up = d.cross(right);
  final lu = (offset.dot(right) * 0.5 + 0.5).clamp(0.0, 1.0);
  final lv = (0.5 - offset.dot(up) * 0.5).clamp(0.0, 1.0);
  return ((cellX + lu) / _kGrid, (cellY + lv) / _kGrid);
}

/// The impostor's lit stage — `lighting/impostor.frag`.
final class ImpostorShader implements CpuFragmentShader {
  const ImpostorShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final read = readSurface(v, b, c);
    if (read == null) return null;

    final d = Vector3(v[kVColour], v[kVColour + 1], v[kVColour + 2])
      ..normalize();
    final right = _right(d);
    final up = d.cross(right);
    final offset =
        right * (v[kVUv] * 2.0 - 1.0) + up * (1.0 - v[kVUv + 1] * 2.0);

    final g = _encode(d)..scale(_kGrid - 1.0);
    final baseX = g.x.floorToDouble().clamp(0.0, _kGrid - 2.0);
    final baseY = g.y.floorToDouble().clamp(0.0, _kGrid - 2.0);
    final fx = g.x - baseX, fy = g.y - baseY;
    final lower = fx + fy < 1.0;
    final cells = <(double, double)>[
      lower ? (baseX, baseY) : (baseX + 1.0, baseY + 1.0),
      (baseX + 1.0, baseY),
      (baseX, baseY + 1.0),
    ];
    final weights = lower
        ? <double>[1.0 - fx - fy, fx, fy]
        : <double>[fx + fy - 1.0, 1.0 - fy, 1.0 - fx];

    final albedoAtlas = b.textures['base_color_texture'];
    final normalAtlas = b.textures['normal_texture'];
    final srgb = Vector3.zero();
    final local = Vector3.zero();
    var alpha = 0.0;
    for (var k = 0; k < 3; k++) {
      final (u, w) = _viewUv(cells[k].$1, cells[k].$2, offset);
      final a = albedoAtlas?.sample(u, w) ?? Vector4(1, 1, 1, 1);
      final n = normalAtlas?.sample(u, w) ?? Vector4(0.5, 0.5, 1, 1);
      final wa = weights[k] * a.w;
      alpha += wa;
      srgb.add(a.xyz.scaled(wa));
      local.add(
        Vector3(n.x * 2.0 - 1.0, n.y * 2.0 - 1.0, n.z * 2.0 - 1.0).scaled(wa),
      );
    }
    if (alpha < 0.5) return null;
    srgb.scale(1.0 / alpha);
    if (local.dot(local) > 1e-12) {
      local.normalize();
    } else {
      local.setFrom(d);
    }

    final worldRight = Vector3(v[kVTangent], v[kVTangent + 1], v[kVTangent + 2])
      ..normalize();
    final worldFacing = Vector3(v[kVNormal], v[kVNormal + 1], v[kVNormal + 2])
      ..normalize();
    final worldUp = worldFacing.cross(worldRight);
    final normal =
        (worldRight.scaled(local.dot(right)) +
              worldUp.scaled(local.dot(up)) +
              worldFacing.scaled(local.dot(d)))
          ..normalize();

    final tint = b.vec4('FragInfo', 'base_color', Vector4(1, 1, 1, 1));
    final albedo = Vector3(
      toLinear(srgb.x) * toLinear(tint.x),
      toLinear(srgb.y) * toLinear(tint.y),
      toLinear(srgb.z) * toLinear(tint.z),
    );
    c.albedo = Vector4(
      toSrgb(albedo.x.clamp(0.0, 1.0)),
      toSrgb(albedo.y.clamp(0.0, 1.0)),
      toSrgb(albedo.z.clamp(0.0, 1.0)),
      1.0,
    );

    final material = b.vec4('FragInfo', 'material', Vector4.zero());
    final sky = b.vec4('FragInfo', 'ambient_sky', Vector4(1, 1, 1, 1));
    final ground = b.vec4('FragInfo', 'ambient_ground', Vector4(1, 1, 1, 1));
    final t = normal.y * 0.5 + 0.5;
    final ambient = Vector3(
      (ground.x + (sky.x - ground.x) * t) * material.z,
      (ground.y + (sky.y - ground.y) * t) * material.z,
      (ground.z + (sky.z - ground.z) * t) * material.z,
    );

    final s = Surface(
      albedo,
      1.0,
      normal,
      read.world,
      ambient,
      read.metallic,
      read.roughness,
      read.view,
      math.max(normal.dot(read.view), 1e-4),
      read.tangent,
    );
    final lit = accumulateLights(
      s,
      b,
      c,
      shade: (s, light) => s.albedo,
      shadowed: true,
    );
    final total = lit + (albedo.clone()..multiply(ambient));

    // `WriteSurfaceGeometry` reads the geometric normal, `v_normal`, turned
    // on a back face as every lit stage turns it.
    final geometric = worldFacing.clone();
    if (!c.frontFacing) geometric.negate();
    return writeLit(
      c,
      v,
      b,
      colour: total,
      alpha: 1.0,
      normal: geometric,
      roughness: 1.0,
    );
  }
}
