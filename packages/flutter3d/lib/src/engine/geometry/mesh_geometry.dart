import 'package:vector_math/vector_math.dart';

import '../graphics/formats.dart';
import '../graphics/geometry_buffer.dart';
import 'mesh_data.dart';

/// What the scene needs to know about a mesh, without knowing where it lives.
///
/// The scene graph asks a mesh for three things: how big it is (culling and
/// framing), whether it has anything to draw, and — for picking and collision —
/// its triangles. None of that requires a GPU, and stating so in an interface is
/// what keeps `lib/src/engine/scene/` free of `flutter_gpu`.
///
/// That matters beyond tidiness. A scene layer that imports flutter_gpu can only
/// be exercised on a device, so transform composition, culling and raycasting
/// would all lose their unit tests to a dependency they never use. [GpuMesh]
/// implements this; so does [CpuMesh], for geometry that has no reason to be
/// uploaded.
abstract interface class MeshGeometry {
  /// Object-space bounds.
  Aabb3 get bounds;

  int get vertexCount;

  int get indexCount;

  /// The CPU-side geometry, when it is still around.
  ///
  /// Null means "triangles unavailable" — raycasting then falls back to the
  /// bounding box, and normals cannot be drawn. flutter_gpu has no buffer
  /// readback, so this is the only way triangles can be had at all.
  MeshData? get source;

  /// Radius of the sphere around the bounds centre, used to frame a camera.
  double get boundingRadius;
}

/// A mesh that has reached the device and can therefore be drawn.
///
/// A subtype of [MeshGeometry] rather than a separate interface, which is not
/// bookkeeping: the renderer's draw loops hold a [MeshGeometry] and ask whether
/// it is drawable, and Dart promotes an `is` test only towards a subtype.
///
/// It exists so that the renderer names no backend for the sake of one `is`
/// check. It used to test for `GpuMesh` — the flutter_gpu class — which meant
/// the engine's central draw loop knew which backend it was on, and would have
/// gone on knowing when the backend became a package of its own.
///
/// Nothing here is CPU-readable: the buffers are opaque handles, and
/// [MeshGeometry.source] is still where triangles come from when anything needs
/// them.
abstract interface class DrawableGeometry implements MeshGeometry {
  /// Interleaved vertex attributes, in the layout the vertex stage declares.
  GeometryBuffer get vertices;

  GeometryBuffer get indices;

  /// The width of one index. Chosen at upload from the vertex count.
  IndexType get indexType;
}

/// A mesh that lives only on the CPU.
///
/// For geometry that is queried but never drawn — collision proxies, navigation
/// meshes, a headless scene under test — and for the tests of everything that
/// consumes [MeshGeometry].
final class CpuMesh implements MeshGeometry {
  CpuMesh(this.source) : bounds = source.computeBounds();

  @override
  final MeshData source;

  @override
  final Aabb3 bounds;

  @override
  int get vertexCount => source.vertexCount;

  @override
  int get indexCount => source.indexCount;

  @override
  double get boundingRadius {
    final extent = (bounds.max - bounds.min)..scale(0.5);
    return extent.length;
  }

  @override
  String toString() => 'CpuMesh($source)';
}
