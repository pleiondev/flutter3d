/// `polyline.vert`: a line of constant screen width, widened per vertex —
/// `gfx-86n`.
///
/// See the GLSL for the repacked layout and the reasoning; this is the same
/// arithmetic in the same order, including the two places it has to decline —
/// a neighbour behind the eye, and a mitre past four half widths.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_layout.dart';

/// `kNear` in the GLSL.
const double _kNear = 1e-4;

/// `kMiterLimit` in the GLSL.
const double _kMiterLimit = 4.0;

/// The polyline vertex stage — `polyline.vert`.
final class PolylineVertexShader implements CpuVertexShaderByIndex {
  const PolylineVertexShader();

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

    // `params.viewport` in the GLSL. Zero is no answer at all — it would
    // divide the offset by nothing — so an unbound block draws the line one
    // pixel wide on a one-pixel screen rather than throwing mid-frame; the
    // draw is still wrong, visibly, which is what a missing parameter should
    // look like.
    final viewport = bindings.vec4(
      'MaterialParams',
      'viewport',
      Vector4(1, 1, 0, 0),
    );
    final viewportX = viewport.x;
    final viewportY = viewport.y;
    final signedHalf = a[kTangent + 3];
    final halfWidth = signedHalf.abs();
    final side = signedHalf < 0 ? -1.0 : 1.0;

    Vector4 project(int at) => mvp * Vector4(a[at], a[at + 1], a[at + 2], 1.0);

    var here = project(kPosition);
    var before = project(kNormal);
    var after = project(kTangent);

    if (here.w < _kNear) {
      here = after.w >= _kNear ? _inFront(here, after) : _inFront(here, before);
    }
    before = _inFront(before, here);
    after = _inFront(after, here);

    final atX = here.x / here.w * viewportX * 0.5;
    final atY = here.y / here.w * viewportY * 0.5;
    var inX = atX - before.x / before.w * viewportX * 0.5;
    var inY = atY - before.y / before.w * viewportY * 0.5;
    var outX = after.x / after.w * viewportX * 0.5 - atX;
    var outY = after.y / after.w * viewportY * 0.5 - atY;

    if (inX * inX + inY * inY < 1e-12) {
      inX = outX;
      inY = outY;
    }
    if (outX * outX + outY * outY < 1e-12) {
      outX = inX;
      outY = inY;
    }

    var offsetX = 0.0;
    var offsetY = 0.0;
    if (inX * inX + inY * inY >= 1e-12) {
      final inLength = math.sqrt(inX * inX + inY * inY);
      final outLength = math.sqrt(outX * outX + outY * outY);
      final inDirX = inX / inLength, inDirY = inY / inLength;
      final outDirX = outX / outLength, outDirY = outY / outLength;
      final segmentNormalX = -inDirY, segmentNormalY = inDirX;

      final alongX = inDirX + outDirX, alongY = inDirY + outDirY;
      final alongLength2 = alongX * alongX + alongY * alongY;
      final double miterX, miterY;
      if (alongLength2 < 1e-12) {
        miterX = segmentNormalX;
        miterY = segmentNormalY;
      } else {
        final alongLength = math.sqrt(alongLength2);
        miterX = -alongY / alongLength;
        miterY = alongX / alongLength;
      }

      final stretch =
          1.0 /
          math.max(
            miterX * segmentNormalX + miterY * segmentNormalY,
            1.0 / _kMiterLimit,
          );
      offsetX = miterX * halfWidth * stretch * side;
      offsetY = miterY * halfWidth * stretch * side;
    }

    final Vector4 world =
        model * Vector4(a[kPosition], a[kPosition + 1], a[kPosition + 2], 1.0);
    out[kVWorld] = world.x;
    out[kVWorld + 1] = world.y;
    out[kVWorld + 2] = world.z;

    // Typed, because `Matrix3.operator*` returns `dynamic`.
    final Vector3 up = normalMatrix.getRotation() * Vector3(0, 1, 0);
    up.normalize();
    out[kVNormal] = up.x;
    out[kVNormal + 1] = up.y;
    out[kVNormal + 2] = up.z;

    out[kVUv] = a[kTexcoord];
    out[kVUv + 1] = a[kTexcoord + 1];
    for (var i = 0; i < 4; i++) {
      out[kVColour + i] = a[kColour + i];
    }
    out[kVTangent] = 1.0;
    out[kVTangent + 1] = 0.0;
    out[kVTangent + 2] = 0.0;
    out[kVTangent + 3] = 1.0;
    out[kVLightmap] = 0.0;
    out[kVLightmap + 1] = 0.0;

    return Vector4(
      here.x + offsetX / (viewportX * 0.5) * here.w,
      here.y + offsetY / (viewportY * 0.5) * here.w,
      here.z,
      here.w,
    );
  }
}

/// `InFront` in the GLSL.
Vector4 _inFront(Vector4 from, Vector4 to) {
  if (from.w >= _kNear) return from;
  final t = ((_kNear - from.w) / (to.w - from.w)).clamp(0.0, 1.0);
  return Vector4(
    from.x + (to.x - from.x) * t,
    from.y + (to.y - from.y) * t,
    from.z + (to.z - from.z) * t,
    from.w + (to.w - from.w) * t,
  );
}
