/// The velocity passes, on the software rasteriser — `R1`.
///
/// `post/camera_velocity.frag` line for line: the pixel's point reconstructed
/// from the surface buffer, carried through last frame's view-projection, and
/// the difference in UV written out as red and green.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_color.dart';
import 'cpu_shaders_mesh_vertex.dart';
import 'cpu_shaders_morph.dart';

/// `v_current` and `v_previous`, four floats each, then `v_depth`.
const int _kVelocityVaryings = 9;

final Vector3 _normalScratch = Vector3.zero();
final Vector4 _tangentScratch = Vector4.zero();

/// `MorphPositionWith` in `lib/velocity.glsl`: [position] moved by the eight
/// [weights], or left where it is when the draw morphs nothing.
Vector3 _morphedWith(
  int vertexIndex,
  ShaderBindings b,
  Vector3 position,
  Float32List? weights,
) {
  if (vertexIndex < 0 || weights == null) return position;
  final params = b.vec4('MorphInfo', 'morph_params', Vector4.zero());
  final count = (params.x + 0.5).floor();
  final limit = count < kMorphMax ? count : kMorphMax;
  for (var i = 0; i < limit && i < weights.length; i++) {
    final weight = weights[i];
    if (weight == 0.0) continue;
    addMorphTarget(
      i,
      weight,
      vertexIndex,
      b,
      position,
      _normalScratch,
      _tangentScratch,
    );
  }
  return position;
}

/// Writes the two clip positions and the depth along the camera's axis, and
/// returns the jittered clip position.
Vector4 _velocityOut(
  ShaderBindings b,
  Vector4 now,
  Vector4 then,
  Float32List out,
) {
  final Vector4 current = b.mat4('PrevFrameInfo', 'current_mvp') * now;
  final Vector4 previous = b.mat4('PrevFrameInfo', 'previous_mvp') * then;
  for (var i = 0; i < 4; i++) {
    out[i] = current[i];
    out[4 + i] = previous[i];
  }
  final Vector4 world = b.mat4('FrameInfo', 'model') * now;
  final eye = b.vec4('PrevFrameInfo', 'camera', Vector4.zero());
  final axis = b.vec4('PrevFrameInfo', 'forward', Vector4.zero());
  out[8] =
      (world.x - eye.x) * axis.x +
      (world.y - eye.y) * axis.y +
      (world.z - eye.z) * axis.z;
  return b.mat4('FrameInfo', 'mvp') * now;
}

/// `velocity.vert`: a moved mesh through this frame's and last frame's
/// matrices. The pipeline's layout declares the position alone.
final class VelocityVertexShader implements CpuVertexShaderByIndex {
  const VelocityVertexShader();

  @override
  int get varyingCount => _kVelocityVaryings;

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
    final now = _morphedWith(
      vertexIndex,
      bindings,
      Vector3(a[0], a[1], a[2]),
      bindings.read('MorphInfo', 'morph_weights'),
    );
    final then = _morphedWith(
      vertexIndex,
      bindings,
      Vector3(a[0], a[1], a[2]),
      bindings.read('PrevFrameInfo', 'previous_morph_weights'),
    );
    return _velocityOut(
      bindings,
      Vector4(now.x, now.y, now.z, 1.0),
      Vector4(then.x, then.y, then.z, 1.0),
      out,
    );
  }
}

/// `velocity_skinned.vert`: skinned by this frame's palette and by last
/// frame's, which arrives as a 4 × 64 float texture of columns.
final class VelocitySkinnedVertexShader implements CpuVertexShaderByIndex {
  const VelocitySkinnedVertexShader();

  // Position, then joints, then weights: the layout declares these three.
  static const int _joints = 3;
  static const int _weights = 7;

  @override
  int get varyingCount => _kVelocityVaryings;

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
    final total =
        a[_weights] + a[_weights + 1] + a[_weights + 2] + a[_weights + 3];
    final w = total > 1e-5
        ? <double>[
            a[_weights] / total,
            a[_weights + 1] / total,
            a[_weights + 2] / total,
            a[_weights + 3] / total,
          ]
        : <double>[1.0, 0.0, 0.0, 0.0];

    final previousJoints = bindings.textures['prev_joint_texture'];
    final skin = Matrix4.zero();
    final prevSkin = Matrix4.zero();
    for (var i = 0; i < 4; i++) {
      final joint = MeshSkinnedVertexShader.jointIndex(a[_joints + i]);
      final current = bindings.mat4('SkinInfo', 'joint_matrices', at: joint);
      final v = (joint + 0.5) / MeshSkinnedVertexShader.maxJoints;
      for (var column = 0; column < 4; column++) {
        final texel =
            previousJoints?.sample((column + 0.5) / 4.0, v) ??
            Vector4(
              current[column * 4],
              current[column * 4 + 1],
              current[column * 4 + 2],
              current[column * 4 + 3],
            );
        for (var r = 0; r < 4; r++) {
          final e = column * 4 + r;
          skin[e] = skin[e] + current[e] * w[i];
          prevSkin[e] = prevSkin[e] + texel[r] * w[i];
        }
      }
    }

    final now = _morphedWith(
      vertexIndex,
      bindings,
      Vector3(a[0], a[1], a[2]),
      bindings.read('MorphInfo', 'morph_weights'),
    );
    final then = _morphedWith(
      vertexIndex,
      bindings,
      Vector3(a[0], a[1], a[2]),
      bindings.read('PrevFrameInfo', 'previous_morph_weights'),
    );
    return _velocityOut(
      bindings,
      skin * Vector4(now.x, now.y, now.z, 1.0),
      prevSkin * Vector4(then.x, then.y, then.z, 1.0),
      out,
    );
  }
}

/// `velocity_instanced.vert`: each instance placed by its transform now
/// (slot 1) and by last frame's (slot 2).
final class VelocityInstancedVertexShader implements CpuVertexShaderByIndex {
  const VelocityInstancedVertexShader();

  // Position, then three rows now, then three rows then.
  static const int _now = 3;
  static const int _then = 15;

  @override
  int get varyingCount => _kVelocityVaryings;

  @override
  Vector4 run(Float32List a, ShaderBindings bindings, Float32List out) =>
      runAt(-1, 0, a, bindings, out);

  static Matrix4 _affine(Float32List a, int at) => Matrix4(
    a[at],
    a[at + 4],
    a[at + 8],
    0.0,
    a[at + 1],
    a[at + 5],
    a[at + 9],
    0.0,
    a[at + 2],
    a[at + 6],
    a[at + 10],
    0.0,
    a[at + 3],
    a[at + 7],
    a[at + 11],
    1.0,
  );

  @override
  Vector4 runAt(
    int vertexIndex,
    int instanceIndex,
    Float32List a,
    ShaderBindings bindings,
    Float32List out,
  ) {
    final now = _morphedWith(
      vertexIndex,
      bindings,
      Vector3(a[0], a[1], a[2]),
      bindings.read('MorphInfo', 'morph_weights'),
    );
    final then = _morphedWith(
      vertexIndex,
      bindings,
      Vector3(a[0], a[1], a[2]),
      bindings.read('PrevFrameInfo', 'previous_morph_weights'),
    );
    return _velocityOut(
      bindings,
      _affine(a, _now) * Vector4(now.x, now.y, now.z, 1.0),
      _affine(a, _then) * Vector4(then.x, then.y, then.z, 1.0),
      out,
    );
  }
}

/// `post/velocity.frag`: the two clip positions, divided here, differenced
/// in UV — for a fragment the scene's surface buffer says is in front.
final class VelocityShader implements CpuFragmentShader {
  const VelocityShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final target = b.vec4('VelocityInfo', 'target', Vector4.zero());
    final surface = b.textures['surface_texture'];
    if (surface == null) return null;
    // `FragCoordFromTop`.
    final y = target.z > 0.0 ? target.z - c.coord.y : c.coord.y;
    final stored = surface.sample(c.coord.x * target.x, y * target.y).w;
    if (stored <= 0.0 || v[8] > stored * (1.0 + target.w) + 1e-3) return null;

    if (v[7] <= 0.0) return Vector4(0.0, 0.0, 0.0, 1.0);
    final nowU = v[0] / v[3] * 0.5 + 0.5;
    final nowV = 0.5 - v[1] / v[3] * 0.5;
    final thenU = v[4] / v[7] * 0.5 + 0.5;
    final thenV = 0.5 - v[5] / v[7] * 0.5;
    return Vector4(nowU - thenU, nowV - thenV, 0.0, 1.0);
  }
}

/// `camera_velocity.frag`: how far this pixel moved because the camera did.
final class CameraVelocityShader implements CpuFragmentShader {
  const CameraVelocityShader();

  /// No motion, full weight: a fresh one each time, since a caller owns it.
  static Vector4 get _still => Vector4(0.0, 0.0, 0.0, 1.0);

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final surfaceMap = b.textures['surface_texture'];
    if (surfaceMap == null) return _still;

    final u = v[0];
    final w = v[1];
    final surface = surfaceMap.sample(u, w);

    final inverse = b.mat4('CameraVelocityInfo', 'inverse_view_projection');
    final previous = b.mat4('CameraVelocityInfo', 'previous_view_projection');

    // The sky is at infinity: only the camera's turning moves it, so the
    // direction goes through last frame's matrix with w zero.
    final Vector4 then;
    if (surface.w <= 0.0) {
      final (origin: _, :along) = pixelRay(inverse, u, w);
      then = previous * Vector4(along.x, along.y, along.z, 0.0);
    } else {
      final eye4 = b.vec4('CameraVelocityInfo', 'camera', Vector4.zero());
      final forward4 = b.vec4('CameraVelocityInfo', 'forward', Vector4.zero());
      final world = worldAtDepth(
        inverse,
        Vector3(eye4.x, eye4.y, eye4.z),
        Vector3(forward4.x, forward4.y, forward4.z),
        u,
        w,
        surface.w,
      );
      then = previous * Vector4(world.x, world.y, world.z, 1.0);
    }

    // Behind last frame's eye: nothing to reproject from.
    if (then.w <= 0.0) return _still;
    final thenU = then.x / then.w * 0.5 + 0.5;
    final thenV = 0.5 - then.y / then.w * 0.5;
    return Vector4(u - thenU, w - thenV, 0.0, 1.0);
  }
}
