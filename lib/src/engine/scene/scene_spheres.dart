import 'dart:typed_data';

import 'mesh_node.dart';

/// Packs a scene's world bounding spheres for [SceneBvh].
///
/// A free function rather than a method on the tree: the tree indexes spheres
/// and must stay clear of `MeshNode`, whose material reaches flutter_gpu and
/// through it `dart:ui`. That is not a purity argument — an index that pulls in
/// `dart:ui` cannot be compiled ahead of time, and ahead-of-time is where its
/// cost gets measured.
///
/// Returns the version stamp for the packed data.
int packSceneSpheres(List<MeshNode> meshes, Float32List out) {
  // A rolling hash of the transform versions. Versions come from one global
  // counter and never repeat, so two different scene states cannot produce the
  // same stamp by reusing a number — only by hash collision, which costs a
  // stale tree for one frame rather than a wrong answer forever.
  var hash = meshes.length;
  for (var i = 0; i < meshes.length; i++) {
    final node = meshes[i];
    final centre = node.worldBoundsCentre;
    out[i * 4] = centre.x;
    out[i * 4 + 1] = centre.y;
    out[i * 4 + 2] = centre.z;
    out[i * 4 + 3] = node.worldBoundsRadius;
    hash = 0x1fffffff & (hash * 31 + node.worldVersion);
  }
  // Zero is the tree's "never built" stamp, so never hand it back as a real one.
  return hash == 0 ? 1 : hash;
}

/// Grows [current] to hold [count] spheres, reusing it when it already does.
Float32List ensureSphereCapacity(Float32List current, int count) =>
    current.length >= count * 4 ? current : Float32List(count * 4);
