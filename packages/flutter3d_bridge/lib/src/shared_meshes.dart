import 'package:flutter3d/flutter3d.dart';
import 'package:vector_math/vector_math.dart';

/// One uploaded mesh per distinct shape, shared by everything that asks for it.
///
/// A crypt with twenty torches should upload one flame — and sharing the
/// [DeviceMesh] is the only form of instancing either backend offers, so it is
/// worth having a name rather than being a map somebody remembers to check.
///
/// The cache belongs to whoever built it, normally one level load, for the same
/// reason the texture cache does: a GPU resource that outlives the level owning
/// it is a leak nobody notices.
final class SharedMeshes {
  SharedMeshes(this._device);

  /// Held rather than passed per call: a cache that could be asked to upload
  /// through two different devices would hand one device's buffers to another.
  final GraphicsDevice _device;

  final Map<String, DeviceMesh> _meshes = <String, DeviceMesh>{};

  /// A box of exactly [size], keyed on its dimensions.
  DeviceMesh box(Vector3 size) =>
      shape('box${size.x},${size.y},${size.z}', () => CuboidShape(size: size));

  /// The mesh for [key], building [shape] the first time it is asked for.
  ///
  /// The builder is a callback rather than a value so that the shape is not
  /// constructed at all on the common path, where the mesh is already there.
  DeviceMesh shape(String key, Shape Function() shape) => _meshes.putIfAbsent(
    key,
    () => DeviceMesh.upload(_device, shape().build()),
  );

  /// Gives every uploaded mesh back to the device.
  ///
  /// **The class doc has said "a GPU resource that outlives the level owning it
  /// is a leak nobody notices" since it was written, and there was no way to
  /// end one.** The cache belongs to a level load, every level load made
  /// another, and nothing ever released the buffers — which on WebGL2 is a
  /// real leak per level, because nothing reclaims a `WebGLBuffer` but
  /// `gl.deleteBuffer`.
  ///
  /// Call it when the level that owns this cache is over — see
  /// `RunSession.close`, which is the hook that says when that is. Afterwards
  /// asking for a shape uploads a new one, so this is a teardown rather than a
  /// way to save memory mid-level.
  void dispose() {
    for (final mesh in _meshes.values) {
      _device.releaseGeometry(mesh.vertices);
      _device.releaseGeometry(mesh.indices);
    }
    _meshes.clear();
  }
}
