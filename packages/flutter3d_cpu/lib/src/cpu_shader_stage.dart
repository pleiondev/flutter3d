/// What a vertex stage and a fragment stage are on this backend, and the pair
/// that names one or the other.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader_bindings.dart';

/// Turns one vertex into a clip position and some varyings.
abstract interface class CpuVertexShader {
  /// How many floats of varying this stage writes, so the rasteriser knows how
  /// much to interpolate.
  int get varyingCount;

  /// Reads [attributes] — the vertex, as the engine laid it out — and writes a
  /// clip-space position plus [varyings].
  Vector4 run(Float32List attributes, ShaderBindings bindings,
      Float32List varyings);
}

/// Everything a fragment stage gets that is not a varying or a binding.
///
/// One object rather than more parameters, because both of the things on it are
/// per-fragment state that GLSL provides as globals — and because a stage that
/// grows a third one should not change the signature of the twenty-three that
/// did not.
final class FragmentContext {
  FragmentContext();

  /// `gl_FragCoord`: window x and y, window depth in z, and `1/w` in w.
  ///
  /// The depth is what the shadow pass stores, so this is not a diagnostic —
  /// leaving it out means `ShadowDepth` cannot be written at all.
  final Vector4 coord = Vector4.zero();

  /// How fast each varying moves across the screen, per pixel.
  ///
  /// Filled once per triangle, and only when something bound to the pass has a
  /// mip chain — the arithmetic is cheap but it is not free, and almost no draw
  /// in this engine needs it.
  ///
  /// **Constant across the triangle, where hardware computes it per fragment.**
  /// A GPU differences a quad of neighbouring fragments, so its answer follows
  /// the perspective; this is the affine gradient of the varying in window
  /// space, which is the same thing only for a triangle facing the camera. The
  /// difference is a fraction of a level of detail, and a level is a power of
  /// two — so it changes which mip is picked only for a surface seen at a sharp
  /// angle, and by one level when it does.
  Float32List? ddx;
  Float32List? ddy;

  /// What the stage wrote to attachment one, or null if it wrote nothing.
  ///
  /// The engine's lit models write the surface buffer from the same call that
  /// writes colour, so a surface cannot be lit into the frame without also
  /// describing itself. A stage that declares `F3D_NO_SURFACE_BUFFER` — the
  /// shadow passes — leaves this alone, and the device then writes nothing,
  /// which is the same thing a pass with one attachment does.
  Vector4? surface;
}

/// Turns interpolated varyings into a colour.
abstract interface class CpuFragmentShader {
  /// Returns linear RGBA for attachment zero. Null discards the fragment.
  Vector4? run(
      Float32List varyings, ShaderBindings bindings, FragmentContext context);
}

/// A stage, which is one or the other.
final class CpuStage {
  const CpuStage.vertex(this.vertex) : fragment = null;
  const CpuStage.fragment(this.fragment) : vertex = null;

  final CpuVertexShader? vertex;
  final CpuFragmentShader? fragment;
}
