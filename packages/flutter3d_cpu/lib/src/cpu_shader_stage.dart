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
  Vector4 run(
    Float32List attributes,
    ShaderBindings bindings,
    Float32List varyings,
  );
}

/// A vertex stage that also wants to know *which* vertex it is running on.
///
/// **A second interface rather than a parameter on [CpuVertexShader]**, which
/// is an `abstract interface class` in a published package: adding to it breaks
/// every implementer, and the thirteen stages in this backend are not the only
/// ones that could exist. The rasteriser asks with `is` and calls this when the
/// answer is yes, so a stage that does not care is not rewritten and a stage
/// outside this repository goes on compiling.
///
/// It exists for morph targets, and for now they are its only caller. The two
/// indices are `gl_VertexIndex` and `gl_InstanceIndex`: the number the draw
/// addressed this vertex with, which is the column of the delta texture
/// `lib/morph.glsl` reads, and the copy being drawn, which is the row of the
/// weights texture `lib/morph_instanced.glsl` reads. Every backend needed both
/// and this one had no way to say either.
abstract interface class CpuVertexShaderByIndex implements CpuVertexShader {
  /// The same as [CpuVertexShader.run], plus the vertex's and the instance's
  /// own indices.
  ///
  /// [run] must still work — a caller that has no indices, or a rasteriser that
  /// has not been taught to pass them, falls back to it — so an implementation
  /// answers both and shares whatever it can.
  Vector4 runAt(
    int vertexIndex,
    int instanceIndex,
    Float32List attributes,
    ShaderBindings bindings,
    Float32List varyings,
  );
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

  /// `gl_FrontFacing`: whether the triangle being shaded faces the camera by
  /// the pass's winding. True for a line, which has no facing and takes the
  /// front state, as GL does.
  bool frontFacing = true;

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

  /// What the stage wrote to attachment two, the albedo buffer — `L5`: the
  /// surface's colour, sRGB-encoded. Set by `readSurface` in the lit models;
  /// a stage that writes [surface] and not this leaves black there, which is
  /// what `g_albedo` holds in the GLSL for a stage that reflects nothing.
  Vector4? albedo;

  /// `gl_FragDepth`, when the stage wrote one — `S1`: the depth the device
  /// stores in place of the interpolated one. Null for every stage but the
  /// shadow copy.
  ///
  /// **Written after the test, not tested.** The rasteriser tests depth
  /// before running the stage, so a stage that moves its depth is tested at
  /// the depth it had. The one stage that writes this draws with the test
  /// off, where the order does not matter.
  double? fragDepth;

  /// A picture a debug pass wants shown instead of the geometry.
  ///
  /// The stand-in for `g_debug_surface` and `g_debug_surface_on` in
  /// `lib/color.glsl`, which are two file-scope globals there and cannot be
  /// two here: a Dart shader is one object shared by every fragment, so the
  /// thing that is per-fragment is this context. Set deep inside the lighting —
  /// the point-shadow penumbra estimate is what fills it — and read at the
  /// moment [surface] is written, which happens after, so the value is there by
  /// then.
  ///
  /// A debug pass takes the surface buffer over rather than getting one of its
  /// own: that buffer already has an attachment, a viewer and a golden, and a
  /// second one would need all three built before it could answer anything.
  /// `g_debug_surface` and `g_debug_surface_on`, as one nullable.
  ///
  /// Where a debug pass leaves the picture it wants shown instead of the
  /// normal. The GLSL declares a pair of globals in `color.glsl` and writes
  /// them from `surface.glsl`, which is included afterwards; a field here is
  /// the same reach, since the two functions share nothing else. Null is the
  /// GLSL's `g_debug_surface_on == false`.
  ///
  /// Read at the moment the surface buffer is written, which happens after the
  /// lighting loop has run — so the value is there by then, exactly as it is
  /// on a device.
  Vector3? debugSurface;
}

/// Turns interpolated varyings into a colour.
abstract interface class CpuFragmentShader {
  /// Returns linear RGBA for attachment zero. Null discards the fragment.
  Vector4? run(
    Float32List varyings,
    ShaderBindings bindings,
    FragmentContext context,
  );
}

/// A stage, which is one or the other.
final class CpuStage {
  const CpuStage.vertex(this.vertex) : fragment = null, compute = null;
  const CpuStage.fragment(this.fragment) : vertex = null, compute = null;

  /// A compute stage — `H6`.
  const CpuStage.compute(this.compute) : vertex = null, fragment = null;

  final CpuVertexShader? vertex;
  final CpuFragmentShader? fragment;
  final CpuComputeShader? compute;
}

/// What a compute stage is handed: its storage buffers and uniform blocks,
/// by the names the GLSL gives them.
final class CpuComputeBindings {
  CpuComputeBindings(this.storage, this.blocks);

  /// The buffers themselves, not copies: a stage writes into them.
  final Map<String, ByteData> storage;
  final Map<String, Map<String, Float32List>> blocks;
}

/// A compute stage in Dart, standing in for a `.comp` shader — `H6`.
///
/// **Run a workgroup at a time, not an invocation at a time.** A compute
/// shader that shares memory between its invocations synchronises them with
/// `barrier()`, and every invocation has to reach one before any passes it.
/// Run one invocation to the end and then the next, and the second reads
/// what the first wrote after the barrier as if it had been there before. So
/// the mirror is handed the whole group and runs the phases between barriers
/// across all of its invocations in turn, which is what a barrier means.
abstract interface class CpuComputeShader {
  /// `local_size_x`, `local_size_y`, `local_size_z`.
  (int, int, int) get workgroupSize;

  /// Runs every invocation of the workgroup at [group].
  void runWorkgroup((int, int, int) group, CpuComputeBindings bindings);
}
