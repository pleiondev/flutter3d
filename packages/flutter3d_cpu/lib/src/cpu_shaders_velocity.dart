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

/// `camera_velocity.frag`: how far this pixel moved because the camera did.
final class CameraVelocityShader implements CpuFragmentShader {
  const CameraVelocityShader();

  static final Vector4 _still = Vector4(0.0, 0.0, 0.0, 1.0);

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final surfaceMap = b.textures['surface_texture'];
    if (surfaceMap == null) return _still.clone();

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
    if (then.w <= 0.0) return _still.clone();
    final thenU = then.x / then.w * 0.5 + 0.5;
    final thenV = 0.5 - then.y / then.w * 0.5;
    return Vector4(u - thenU, w - thenV, 0.0, 1.0);
  }
}
