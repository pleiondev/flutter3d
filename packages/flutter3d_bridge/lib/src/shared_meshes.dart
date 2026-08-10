import 'package:flutter3d/flutter3d.dart';
import 'package:vector_math/vector_math.dart';

/// One uploaded mesh per distinct shape, shared by everything that asks for it.
///
/// A crypt with twenty torches should upload one flame — and sharing the
/// [GpuMesh] is the only form of instancing flutter_gpu offers, so it is worth
/// having a name rather than being a map somebody remembers to check.
///
/// The cache belongs to whoever built it, normally one level load, for the same
/// reason the texture cache does: a GPU resource that outlives the level owning
/// it is a leak nobody notices.
final class SharedMeshes {
  final Map<String, GpuMesh> _meshes = <String, GpuMesh>{};

  /// A box of exactly [size], keyed on its dimensions.
  GpuMesh box(Vector3 size) =>
      shape('box${size.x},${size.y},${size.z}', () => CuboidShape(size: size));

  /// The mesh for [key], building [shape] the first time it is asked for.
  ///
  /// The builder is a callback rather than a value so that the shape is not
  /// constructed at all on the common path, where the mesh is already there.
  GpuMesh shape(String key, Shape Function() shape) =>
      _meshes.putIfAbsent(key, () => GpuMesh.upload(shape().build()));
}
