import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import '../geometry/geometry.dart';
import '../graphics/formats.dart';

/// GPU-resident counterpart of a [MeshData].
///
/// Uploads happen once at construction. flutter_gpu offers no explicit release
/// for a [gpu.DeviceBuffer] — handles are collected once unreachable — so
/// dropping the last reference to a [GpuMesh] is what frees it. Real resource
/// lifetime management (ref counting, deferred release while the GPU may still
/// be reading) belongs in the RHI layer, not here.
final class GpuMesh implements MeshGeometry {
  GpuMesh._({
    required this.vertexBuffer,
    required this.indexBuffer,
    required this.vertexCount,
    required this.indexCount,
    required this.indexType,
    required this.bounds,
    required this.source,
  });

  final gpu.DeviceBuffer vertexBuffer;
  final gpu.DeviceBuffer indexBuffer;

  @override
  final int vertexCount;

  @override
  final int indexCount;

  final IndexType indexType;

  /// Object-space bounds, kept for culling and for framing the camera.
  @override
  final Aabb3 bounds;

  /// The geometry this was uploaded from, retained for anything the CPU still
  /// has to answer about the mesh: raycasting against triangles, drawing
  /// normals, and later collision shapes.
  ///
  /// flutter_gpu offers no readback, so the alternative to keeping this is not
  /// being able to answer those questions at all. Callers that will never need
  /// it — a streamed scene where memory matters more than picking — can drop it
  /// with `keepSourceData: false`.
  @override
  final MeshData? source;

  factory GpuMesh.upload(MeshData mesh, {bool keepSourceData = true}) {
    final packed = mesh.packIndices();

    return GpuMesh._(
      vertexBuffer: gpu.gpuContext.createDeviceBufferWithCopy(mesh.vertexBytes),
      indexBuffer: gpu.gpuContext.createDeviceBufferWithCopy(packed.bytes),
      vertexCount: mesh.vertexCount,
      indexCount: packed.count,
      indexType: packed.is16Bit ? IndexType.int16 : IndexType.int32,
      bounds: mesh.computeBounds(),
      source: keepSourceData ? mesh : null,
    );
  }

  /// Radius of the sphere around the AABB centre, used to frame the camera.
  @override
  double get boundingRadius {
    final extent = (bounds.max - bounds.min)..scale(0.5);
    return extent.length;
  }

  gpu.BufferView get vertexView => gpu.BufferView(
        vertexBuffer,
        offsetInBytes: 0,
        lengthInBytes: vertexBuffer.sizeInBytes,
      );

  gpu.BufferView get indexView => gpu.BufferView(
        indexBuffer,
        offsetInBytes: 0,
        lengthInBytes: indexBuffer.sizeInBytes,
      );
}
