/// `post/contact_shadow.frag`, the short march toward the sun — `gfx-76n`.
///
/// The second hand-written half of the pass, and the only reason the row can be
/// checked at all: the software rasteriser is the oracle the three GPU backends
/// are compared against, so a seam that appears here and there is a seam, while
/// one that appears in only one of them is a bug. See `cpu_shaders_ssao.dart`
/// for the other march over the same buffer, whose reconstruction this shares
/// line for line.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_color.dart';

/// `contact_shadow.frag`: whether the sun reaches this point over the first few
/// centimetres, which is the stretch a shadow map cannot answer for.
final class ContactShadowShader implements CpuFragmentShader {
  const ContactShadowShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final surfaceMap = b.textures['surface_texture'];
    if (surfaceMap == null) return Vector4(1.0, 1.0, 1.0, 1.0);

    final u = v[0];
    final w = v[1];
    final surface = surfaceMap.sample(u, w);

    // Nothing was drawn here. A zero alpha is the sky, not a surface sitting on
    // the near plane, and the sky casts nothing on itself.
    if (surface.w <= 0.0) return Vector4(1.0, 1.0, 1.0, 1.0);

    final toLight4 = b.vec4('ContactShadowInfo', 'to_light', Vector4.zero());
    final toLight = Vector3(toLight4.x, toLight4.y, toLight4.z);
    if (toLight.length2 == 0.0) return Vector4(1.0, 1.0, 1.0, 1.0);
    toLight.normalize();

    final normal = decodeOctahedral(surface.x, surface.y);
    // A surface already turned away from the sun is dark by the light term
    // itself, and a march from it would find its own far side. One is the honest
    // answer: the half of the picture that knows about the normal is the half
    // that should darken this.
    if (normal.dot(toLight) <= 0.0) return Vector4(1.0, 1.0, 1.0, 1.0);

    final params = b.vec4('ContactShadowInfo', 'params', Vector4.zero());
    final reach = math.max(params.x, 1e-4);
    final steps = (params.y + 0.5).floor().clamp(1, 16);
    final thickness = math.max(params.z, 1e-4);

    final inverse = b.mat4('ContactShadowInfo', 'inverse_view_projection');
    final projection = b.mat4('ContactShadowInfo', 'view_projection');
    final eye4 = b.vec4('ContactShadowInfo', 'camera', Vector4.zero());
    final eye = Vector3(eye4.x, eye4.y, eye4.z);
    final forward4 = b.vec4('ContactShadowInfo', 'forward', Vector4.zero());
    final axis = Vector3(forward4.x, forward4.y, forward4.z);

    // Lifted along the normal, in metres, for the reason `SsaoShader` lifts its
    // own origin: a bias in window depth is a different physical distance at
    // every range.
    final origin = worldAtDepth(inverse, eye, axis, u, w, surface.w)
      ..addScaled(normal, params.w);
    final stride = reach / steps;

    for (var i = 0; i < steps; i++) {
      final at = origin + toLight * (stride * (i + 1));
      final Vector4 clip = projection * Vector4(at.x, at.y, at.z, 1.0);
      // Behind the eye: the march has left the frame, and dividing by a
      // negative w would fold it back into view somewhere it is not.
      if (clip.w <= 0.0) break;
      final ndcX = clip.x / clip.w;
      final ndcY = clip.y / clip.w;
      // Off the edge of the buffer. Nothing is known out there, and guessing
      // would put a dark rim around every frame.
      if (ndcX.abs() > 1.0 || ndcY.abs() > 1.0) break;

      final su = ndcX * 0.5 + 0.5;
      // v runs the other way from clip-space y; `toFramebufferOrigin` has
      // already put the backend's convention into the matrices, so this pair is
      // the same arithmetic everywhere.
      final sv = 0.5 - ndcY * 0.5;
      final there = surfaceMap.sample(su, sv);
      if (there.w <= 0.0) continue;

      final gap = (at - eye).dot(axis) - there.w;
      // In front of the ray, and not so far in front that it is a different
      // object seen past the one casting: without the thickness test a wall four
      // metres nearer than the floor shadows everything the ray crosses, which
      // is the halo the occlusion pass's range check exists to stop.
      if (gap > 0.0 && gap < thickness) {
        // Darker the nearer the blocker, which is what makes this a contact
        // shadow rather than a stencil: a hit on the first step is a surface
        // touching this one, a hit at the far end of the march is most of a
        // metre off and barely counts. Without it the pass writes zero or one
        // and the march's reach shows up as a hard band on the floor.
        final fade = i / steps;
        return Vector4(fade, fade, fade, fade);
      }
    }

    return Vector4(1.0, 1.0, 1.0, 1.0);
  }
}
