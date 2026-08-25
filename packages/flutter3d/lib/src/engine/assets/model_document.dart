import 'package:vector_math/vector_math.dart';

import '../animation/animation.dart';
import 'model_node.dart';
import 'surface_material.dart';

// `SurfaceMaterial` and its texture inputs describe how a surface looks;
// `ModelSurface`/`ModelNode`/`ModelSkin` describe the hierarchy they hang
// from. Neither group touches anything private in the other or in this file,
// so they are ordinary files, re-exported here so every existing import of
// `model_document.dart` keeps seeing the whole document vocabulary.
export 'model_node.dart';
export 'surface_material.dart';

/// A decoded model, whatever format it came from.
///
/// The seam between decoders and the rest of the engine: glTF and OBJ both
/// produce one of these, so uploading, instancing and material conversion are
/// written once instead of per format.
abstract class ModelDocument {
  const ModelDocument();

  List<ModelSurface> get surfaces;
  List<SurfaceMaterial> get materials;
  List<EncodedImage> get images;

  /// The model's node hierarchy.
  ///
  /// Defaults to one node per surface, which is the truth for a format that has
  /// no hierarchy at all — OBJ groups are siblings, not a tree. A decoder with a
  /// real hierarchy overrides this, and animation then has something to target.
  List<ModelNode> get nodes {
    final translation = Vector3.zero();
    final rotation = Quaternion.identity();
    final scale = Vector3(1.0, 1.0, 1.0);

    return <ModelNode>[
      for (var i = 0; i < surfaces.length; i++)
        () {
          surfaces[i].transform.decompose(translation, rotation, scale);
          return ModelNode(
            name: surfaces[i].name,
            translation: translation.clone(),
            rotation: rotation.clone(),
            scale: scale.clone(),
            surfaces: <int>[i],
          );
        }(),
    ];
  }

  /// Indices into [nodes] with no parent.
  List<int> get roots => <int>[for (var i = 0; i < nodes.length; i++) i];

  /// Clips that drive [nodes]. Empty for formats that carry no animation.
  List<AnimationClip> get animations => const <AnimationClip>[];

  /// Skeletons. Empty for formats that carry no skinning.
  List<ModelSkin> get skins => const <ModelSkin>[];

  /// Non-fatal findings from decoding: ignored extensions, skipped primitives,
  /// unresolved references. Surfaced rather than logged so callers can decide
  /// whether to care.
  List<String> get warnings;

  int get vertexCount {
    var total = 0;
    for (final surface in surfaces) {
      total += surface.mesh.vertexCount;
    }
    return total;
  }

  int get triangleCount {
    var total = 0;
    for (final surface in surfaces) {
      total += surface.mesh.triangleCount;
    }
    return total;
  }

  /// Bounds in the model's own space.
  ///
  /// Transforms the eight corners of each surface's local box rather than the box
  /// itself, because rotating a box and taking its extents is only correct for
  /// axis-aligned rotations.
  Aabb3 computeBounds() {
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = -double.infinity,
        maxY = -double.infinity,
        maxZ = -double.infinity;
    var any = false;

    final corner = Vector3.zero();
    for (final surface in surfaces) {
      if (surface.mesh.vertexCount == 0) continue;
      final local = surface.mesh.computeBounds();
      for (var i = 0; i < 8; i++) {
        corner.setValues(
          (i & 1) == 0 ? local.min.x : local.max.x,
          (i & 2) == 0 ? local.min.y : local.max.y,
          (i & 4) == 0 ? local.min.z : local.max.z,
        );
        surface.transform.transform3(corner);
        any = true;
        if (corner.x < minX) minX = corner.x;
        if (corner.y < minY) minY = corner.y;
        if (corner.z < minZ) minZ = corner.z;
        if (corner.x > maxX) maxX = corner.x;
        if (corner.y > maxY) maxY = corner.y;
        if (corner.z > maxZ) maxZ = corner.z;
      }
    }

    if (!any) return Aabb3();
    return Aabb3.minMax(Vector3(minX, minY, minZ), Vector3(maxX, maxY, maxZ));
  }
}
