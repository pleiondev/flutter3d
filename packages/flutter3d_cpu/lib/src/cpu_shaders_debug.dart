/// The debug-only stages: line overlays and the world-normal view.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_color.dart';
import 'cpu_shaders_layout.dart';

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

/// `object_id.frag`: the id the renderer handed this draw, as three bytes.
///
/// One attachment: the picking target has no surface buffer beside it, so
/// nothing is written to the context's second output, the way the shadow
/// stages leave it.
final class ObjectIdShader implements CpuFragmentShader {
  const ObjectIdShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final id = b.vec4('IdInfo', 'id', Vector4.zero());
    return Vector4(id.x, id.y, id.z, 1.0);
  }
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
    final n = Vector3(v[kVNormal], v[kVNormal + 1], v[kVNormal + 2])
      ..normalize();
    final display = Vector3(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5);
    writeSurface(c, n, 1.0);
    return Vector4(
      toLinear(display.x),
      toLinear(display.y),
      toLinear(display.z),
      1.0,
    );
  }
}
