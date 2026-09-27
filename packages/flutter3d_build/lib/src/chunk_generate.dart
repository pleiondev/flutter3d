/// `C9`: the huge static meshes of a converted model cut into clusters the
/// scene pass culls one by one — `convert --chunks` and a manifest rule's
/// `chunks:` both end here, after the levels of detail and before the
/// impostor bake.
library;

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';

/// The triangle count above which `--chunks` with no number splits a mesh.
///
/// Where a single draw stops being the cheap way to show a mesh: below it the
/// whole mesh costs less than the tests and the repacking would save, and a
/// model made by hand for a game is almost always below it. A scan or a CAD
/// export is almost always far above.
const int kDefaultChunkThreshold = 65536;

/// [document] with every static surface of more than [threshold] triangles
/// split by `clusterMesh`, and how many meshes that was.
///
/// **Static only.** A surface with morph targets or a skin moves its
/// vertices after the boxes and cones were measured, so a cluster could be
/// culled where its triangles have gone into view; those are left whole, and
/// the renderer would draw them whole anyway. A mesh shared by several
/// surfaces is split once and shared again, so the file still holds it once.
(ModelDocument, int) splitLargeMeshes(
  ModelDocument document, {
  int threshold = kDefaultChunkThreshold,
}) {
  final split = <MeshData, MeshData>{};
  // Deformed anywhere is deformed: a mesh one surface skins cannot be culled
  // by boxes measured for another surface that draws it still.
  final deformed = <MeshData>{
    for (final surface in document.surfaces)
      if (surface.skinIndex != null || surface.mesh.morphTargets.isNotEmpty)
        surface.mesh,
  };
  bool splittable(ModelSurface surface) =>
      surface.mesh.triangleCount > threshold &&
      surface.mesh.clusters == null &&
      !deformed.contains(surface.mesh);

  final surfaces = <ModelSurface>[
    for (final surface in document.surfaces)
      if (!splittable(surface))
        surface
      else
        ModelSurface(
          mesh: split.putIfAbsent(
            surface.mesh,
            () => clusterMesh(surface.mesh),
          ),
          transform: surface.transform.clone(),
          materialIndex: surface.materialIndex,
          skinIndex: surface.skinIndex,
          flipWinding: surface.flipWinding,
          name: surface.name,
          meshName: surface.meshName,
          morphWeights: surface.morphWeights,
          authoredAttributes: surface.authoredAttributes,
          variantMaterials: surface.variantMaterials,
        ),
  ];
  if (split.isEmpty) return (document, 0);

  return (
    PlainModelDocument(
      surfaces: surfaces,
      materials: document.materials,
      images: document.images,
      nodes: document.nodes,
      animations: document.animations,
      skins: document.skins,
      lights: document.lights,
      cameras: document.cameras,
      warnings: document.warnings,
      asset: document.asset,
      variants: document.variants,
    ),
    split.length,
  );
}

/// `--chunks=<triangles>`'s number, or null when it is not a positive whole
/// number.
int? parseChunkThreshold(String text) {
  final threshold = int.tryParse(text.trim());
  return threshold == null || threshold < 1 ? null : threshold;
}
