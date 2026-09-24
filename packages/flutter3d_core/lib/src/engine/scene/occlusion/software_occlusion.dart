import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import '../../render/material.dart';
import '../instanced_mesh_node.dart';
import '../mesh_node.dart';
import 'occlusion_buffer.dart';
import 'occlusion_test.dart';

/// `OcclusionMode.software`: this frame's occluders rasterised into an
/// [OcclusionBuffer] before the render list is built — `C2`.
///
/// Owns the buffer so a renderer allocates it once, on the first frame that
/// asks, and a renderer that never asks allocates nothing.
final class SoftwareOcclusion {
  /// Occluder triangles a frame may draw.
  ///
  /// The cost of the method is these triangles on the CPU, so a cap is what
  /// keeps a scene with a thousand marked occluders from paying for all of
  /// them. The largest on screen go first — a wall filling half the view
  /// hides more than a crate at the end of the street — and a mesh that does
  /// not fit in what is left is skipped rather than drawn in part.
  static const int triangleBudget = 2000;

  final OcclusionBuffer buffer = OcclusionBuffer();

  /// How many meshes the last [prepare] drew into the buffer.
  int get occluders => _occluders;
  int _occluders = 0;

  final List<({double size, MeshNode node, MeshData data})> _candidates =
      <({double size, MeshNode node, MeshData data})>[];

  /// Fills the buffer from the marked occluders among [meshes] that
  /// [frustum] keeps and [layerMask] shows, and returns it as the frame's
  /// test.
  ///
  /// [viewProjection] is the view's own, in the engine's `[0, 1]` depth
  /// convention; [eye] ranks occluders by how large they are on screen.
  /// [cullBackFaces] is the scene pass's own setting: with culling off the
  /// back of a wall is drawn and hides what is behind it as well.
  OcclusionTest prepare({
    required List<MeshNode> meshes,
    required Matrix4 viewProjection,
    required Frustum frustum,
    required Vector3 eye,
    required int layerMask,
    bool cullBackFaces = true,
    int budget = triangleBudget,
  }) {
    buffer.begin(viewProjection);
    _candidates.clear();
    for (final node in meshes) {
      if (!node.occluder) continue;
      final data = occluderGeometry(node);
      if (data == null) continue;
      if (!node.visibleInHierarchy || !node.shadowCasting.drawsColour) continue;
      if ((node.layerMask & layerMask) == 0) continue;
      if (!frustum.intersectsWithAabb3(node.worldBounds)) continue;
      // The angle the bounding sphere spans, near enough: what the mesh can
      // cover of the view. Inside the sphere is as large as it gets.
      final distance = node.worldBoundsCentre.distanceTo(eye);
      final size = node.worldBoundsRadius / (distance > 1e-3 ? distance : 1e-3);
      _candidates.add((size: size, node: node, data: data));
    }
    _candidates.sort((a, b) => b.size.compareTo(a.size));

    var left = budget;
    _occluders = 0;
    for (final (size: _, :node, :data) in _candidates) {
      final triangles = data.triangleCount;
      if (triangles > left) continue;
      buffer.draw(
        data,
        node.worldMatrix,
        cullBackFaces: cullBackFaces && !node.material.doubleSided,
      );
      left -= triangles;
      _occluders++;
    }
    _candidates.clear();
    return buffer;
  }

  /// The triangles [node] occludes with, or null when it cannot occlude.
  ///
  /// Only a surface the depth test treats as solid hides anything: a blended
  /// or cut-out material lets what is behind it through, and one that writes
  /// no depth, or tests it some other way, is a backdrop rather than a wall.
  static MeshData? occluderGeometry(MeshNode node) {
    // An instanced batch is its mesh at many places, and its world matrix is
    // none of them.
    if (node is InstancedMeshNode) return null;
    final material = node.material;
    if (material.alphaMode != MaterialAlphaMode.opaque) return null;
    if (material.depthWrite == false) return null;
    final compare = material.depthCompare;
    if (compare != null &&
        compare != CompareFunction.less &&
        compare != CompareFunction.lessEqual) {
      return null;
    }
    if (node.occluderMesh case final proxy?) return proxy;
    if (node.skeleton != null || node.morph != null) return null;
    return node.mesh.source;
  }
}
