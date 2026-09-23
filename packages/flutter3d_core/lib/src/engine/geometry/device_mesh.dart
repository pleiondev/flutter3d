/// The half of the geometry layer that has met a device.
///
/// **Split out of `mesh_geometry.dart` because of what one import cost.** That
/// file declared [MeshGeometry] — an interface whose whole argument is that
/// asking a mesh its size needs no GPU — and, three classes later, [DeviceMesh],
/// which holds two buffers a device made. One `flutter3d_hardware` import served
/// both, and through it every file that touched `geometry.dart` reached
/// `GraphicsDevice`, which returns a `Widget` from `present` and therefore names
/// `package:flutter/widgets.dart`.
///
/// Nothing was wrong on a device. What broke was everything that runs off one:
/// `tool/bench/bench.dart` stopped compiling ahead-of-time, because `dart:ui`
/// does not exist in a standalone VM — so the numbers in ARCHITECTURE.md §14
/// could not be recounted by anybody, and the claim in `geometry.dart` that
/// nothing there depends on a graphics backend had quietly stopped being true.
///
/// So the seam is drawn where the dependency actually falls rather than where
/// the subject matter does: `mesh_geometry.dart` keeps what needs no device,
/// this file takes what does, and `geometry.dart` exports only the first.
/// `flutter3d.dart` exports both, so nothing outside the package can tell the
/// two files apart.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

/// A mesh that has reached the device and can therefore be drawn.
///
/// A subtype of [MeshGeometry] rather than a separate interface, which is not
/// bookkeeping: the renderer's draw loops hold a [MeshGeometry] and ask whether
/// it is drawable, and Dart promotes an `is` test only towards a subtype.
///
/// **Kept at the freeze, and for a different reason than it was created with.**
/// It was introduced so the renderer would not name a backend for the sake of
/// one `is` check — it used to test for `GpuMesh`, the backend class. That
/// reason expired when [DeviceMesh] moved into this package: testing for it
/// would name no backend either.
///
/// What it still does is name the distinction the four `is` checks in the draw
/// loops actually make. [MeshGeometry] has two implementations and only one of
/// them can be drawn: geometry that reached the device, and geometry that is
/// triangles in Dart memory. A check against the concrete class would ask "is
/// it this one" where the loop means "can this be drawn", and those come apart
/// the first time there is a second drawable kind.
///
/// One implementation today, which is why it was on the freeze list at all. The
/// argument for keeping it is the second implementation of its *parent*, not a
/// hypothetical second implementation of itself.
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

/// A [MeshData] that has been uploaded to a device.
///
/// **In `geometry/`, not in a backend directory, and that is the whole point of
/// it.** This was `GpuMesh` and it lived beside the backend, holding two
/// `gpu.DeviceBuffer`s and calling `gpuContext` — a global — from a static
/// factory. `assets/model_asset.dart` therefore imported the backend, which is
/// the single fact that would have turned lifting the backend into its own
/// package from a move into a rewrite.
///
/// Nothing in here was ever backend-specific once a buffer became a handle.
/// What is left is arithmetic and two opaque handles, so one class serves every
/// backend and the device that made it is the only thing that knows which.
///
/// Nothing here releases the buffers. The owner does, with
/// `GraphicsDevice.releaseGeometry` on [vertices] and [indices] once nothing
/// draws the mesh: a backend whose collector frees them treats that as a no-op,
/// and one that does not — WebGL, WebGPU — otherwise keeps them until the
/// device itself goes.
final class DeviceMesh implements DrawableGeometry {
  DeviceMesh._({
    required this.vertices,
    required this.indices,
    required this.vertexCount,
    required this.indexCount,
    required this.indexType,
    required this.bounds,
    required this.source,
  });

  /// Uploads [mesh] through [device].
  ///
  /// The device is an argument and not a global, which is the difference this
  /// class exists to make. A test can hand it a fake and get a mesh that draws
  /// nowhere; a second backend hands it its own device and nothing here
  /// changes.
  factory DeviceMesh.upload(
    GraphicsDevice device,
    MeshData mesh, {
    bool keepSourceData = true,
  }) {
    final packed = mesh.packIndices();
    return DeviceMesh._(
      vertices: device.uploadGeometry(mesh.vertexBytes, GeometryUsage.vertices),
      indices: device.uploadGeometry(packed.bytes, GeometryUsage.indices),
      vertexCount: mesh.vertexCount,
      indexCount: packed.count,
      indexType: packed.is16Bit ? IndexType.int16 : IndexType.int32,
      bounds: mesh.computeBounds(),
      source: keepSourceData ? mesh : null,
    );
  }

  @override
  final GeometryBuffer vertices;

  @override
  final GeometryBuffer indices;

  @override
  final int vertexCount;

  @override
  final int indexCount;

  @override
  final IndexType indexType;

  @override
  Aabb3 bounds;

  /// Bumped on every [overwriteVertices] call.
  ///
  /// [bounds] is compared by a caller that caches it — `MeshNode.
  /// markBoundsDirty` is the escape hatch for that cache today, since
  /// `MeshNode`'s own invalidation compares this mesh by identity and an
  /// in-place overwrite changes nothing an identity check can see. This
  /// counter is for a future caller that would rather poll than remember to
  /// call one, the same reason `MorphState.version` and `SceneNode.
  /// worldVersion` already exist.
  int get version => _version;
  int _version = 0;

  /// The geometry this was uploaded from, retained for anything the CPU still
  /// has to answer about the mesh: raycasting against triangles, drawing
  /// normals, and later collision shapes.
  ///
  /// Neither backend offers readback, so the alternative to keeping this is not
  /// being able to answer those questions at all. Callers that will never need
  /// it — a streamed scene where memory matters more than picking — can drop it
  /// with `keepSourceData: false`.
  @override
  final MeshData? source;

  @override
  double get boundingRadius {
    final extent = (bounds.max - bounds.min)..scale(0.5);
    return extent.length;
  }

  /// Overwrites [vertexCount] vertices' worth of interleaved attribute bytes
  /// starting at [firstVertex], in place — `pro-eng-01`.
  ///
  /// **[bounds] grows to cover the overwritten range; it never shrinks.**
  /// Every layout in this engine starts with `position` — `VertexLayout.
  /// positionOnly` through `skinned` all list it first — so the first three
  /// floats of each vertex are read as a position with no layout of its own
  /// needed here. The result is unioned into the existing box rather than
  /// replacing it: this call sees only the overwritten range, and a vertex
  /// untouched by it may still be the one holding the box's own far corner.
  /// A box that only grows stays a correct, if not always tight, answer;
  /// tightening it back down would need the whole mesh's current positions,
  /// which this call does not have and `keepSourceData: false` may mean
  /// nothing has.
  ///
  /// [version] is bumped once regardless of how many vertices changed.
  /// `MeshNode`'s own bounds cache compares this mesh by identity, which an
  /// in-place overwrite does not change — a caller also holding a node this
  /// mesh belongs to still has to call `MeshNode.markBoundsDirty` itself.
  ///
  /// [vertexBytes]' own length must be an exact multiple of this mesh's vertex
  /// stride — `vertices.lengthInBytes ~/ vertexCount` — and
  /// `firstVertex + (vertexBytes.lengthInBytes ~/ stride)` must not exceed
  /// [vertexCount]; both are checked here rather than left to
  /// [GraphicsDevice.overwriteGeometry], which knows bytes and offsets but not
  /// that they mean vertices.
  void overwriteVertices(
    GraphicsDevice device,
    int firstVertex,
    ByteData vertexBytes,
  ) {
    final stride = vertices.lengthInBytes ~/ vertexCount;
    if (vertexBytes.lengthInBytes % stride != 0) {
      throw ArgumentError(
        'overwriteVertices: ${vertexBytes.lengthInBytes} bytes is not a '
        'whole number of $stride-byte vertices',
      );
    }
    final count = vertexBytes.lengthInBytes ~/ stride;
    if (firstVertex < 0 || firstVertex + count > vertexCount) {
      throw ArgumentError(
        'overwriteVertices: vertices $firstVertex..${firstVertex + count} '
        'do not fit in a $vertexCount-vertex mesh',
      );
    }
    device.overwriteGeometry(vertices, firstVertex * stride, vertexBytes);

    final floatsPerVertex = stride ~/ 4;
    bounds.hull(_boundsOf(vertexBytes, count, floatsPerVertex));
    _version++;
  }

  /// The bounding box of the positions in [vertexBytes], read as [count]
  /// vertices of [floatsPerVertex] floats each with position first.
  static Aabb3 _boundsOf(ByteData vertexBytes, int count, int floatsPerVertex) {
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = -double.infinity,
        maxY = -double.infinity,
        maxZ = -double.infinity;
    for (var v = 0; v < count; v++) {
      final base = (v * floatsPerVertex) * 4;
      final x = vertexBytes.getFloat32(base, Endian.host);
      final y = vertexBytes.getFloat32(base + 4, Endian.host);
      final z = vertexBytes.getFloat32(base + 8, Endian.host);
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (z < minZ) minZ = z;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
      if (z > maxZ) maxZ = z;
    }
    return Aabb3.minMax(Vector3(minX, minY, minZ), Vector3(maxX, maxY, maxZ));
  }
}
