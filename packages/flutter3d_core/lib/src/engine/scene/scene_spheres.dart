import 'dart:typed_data';

import 'mesh_node.dart';

/// Packs a scene's world bounding spheres for [SceneBvh].
///
/// A free function rather than a method on the tree: the tree indexes spheres
/// and must stay clear of `MeshNode`, whose material reaches the graphics backend and
/// through it `dart:ui`. That is not a purity argument — an index that pulls in
/// `dart:ui` cannot be compiled ahead of time, and ahead-of-time is where its
/// cost gets measured.
///
/// Returns the version stamp for the packed data.
int packSceneSpheres(List<MeshNode> meshes, Float32List out) {
  for (var i = 0; i < meshes.length; i++) {
    final node = meshes[i];
    final centre = node.worldBoundsCentre;
    out[i * 4] = centre.x;
    out[i * 4 + 1] = centre.y;
    out[i * 4 + 2] = centre.z;
    out[i * 4 + 3] = node.worldBoundsRadius;
  }

  // **A rolling hash of the spheres themselves, not of the transforms.** It
  // was the transform versions, and a sphere moves without its node's
  // transform moving more often than that suggests: a skinned mesh's bounds
  // follow its joints, an instanced batch's follow its instances, a morph's
  // follow its weights, and `MeshNode.markBoundsDirty` exists for all the rest.
  // Each of those left the stamp alone, so the tree kept the old sphere and
  // rejected the mesh wherever it had gone until something else in the scene
  // happened to move. Hashing the packed bits asks the question the tree
  // actually depends on. A collision leaves the tree stale until the next
  // change, which at 29 bits is a chance a caller can ignore.
  final bits = Uint32List.view(
    out.buffer,
    out.offsetInBytes,
    meshes.length * 4,
  );
  var hash = meshes.length;
  for (var i = 0; i < bits.length; i++) {
    hash = 0x1fffffff & (hash * 31 + bits[i]);
  }
  // Zero is the tree's "never built" stamp, so never hand it back as a real one.
  return hash == 0 ? 1 : hash;
}

/// Grows [current] to hold [count] spheres, reusing it when it already does.
Float32List ensureSphereCapacity(Float32List current, int count) =>
    current.length >= count * 4 ? current : Float32List(count * 4);
