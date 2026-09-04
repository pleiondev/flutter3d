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

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import 'mesh_data.dart';
import 'mesh_geometry.dart';

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
/// There is still no explicit release: the buffers are freed when the last
/// reference to this goes, which is what both backends give us and less than a
/// real resource layer would.
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
  final Aabb3 bounds;

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
}
