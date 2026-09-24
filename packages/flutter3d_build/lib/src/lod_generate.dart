/// `C5`: the levels of detail a converted model carries without anybody
/// making them by hand — `convert --lods=0.5,0.25,0.1` and a manifest rule's
/// `lods:` both end here, before the impostor bake and texture encoding.
library;

import 'dart:math' as math;

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';

/// What one generated level turned out to be, across every node that got one.
final class LodLevelReport {
  const LodLevelReport({
    required this.ratio,
    required this.targetTriangles,
    required this.triangles,
    required this.error,
  });

  /// The fraction of the base's triangles this level was asked for.
  final double ratio;

  /// What [ratio] comes to, summed over every simplified surface.
  final int targetTriangles;

  /// What the simplifier actually reached, summed the same way.
  final int triangles;

  /// The largest `SimplifiedMesh.error` any surface of this level reached, in
  /// model units.
  final double error;

  @override
  String toString() =>
      'lod ${ratio.toStringAsFixed(2)}: $triangles of $targetTriangles '
      'triangles, error ${error.toStringAsExponential(2)}';
}

/// The screen fraction below which a level cut to [ratio] of the base takes
/// over.
///
/// **The square root, because triangles cover area and the fraction is a
/// height.** Holding triangles per pixel steady as an object shrinks means the
/// triangle count falls with the square of its size on screen, so a quarter of
/// the triangles is right at half the height. The base is held to half the
/// frame: past that the object is the subject of the shot, and nobody wants a
/// cheaper version of the subject.
double lodScreenFraction(double ratio) => 0.5 * math.sqrt(ratio);

/// [document] with a chain of coarser levels on every node that draws
/// something and has none yet, one per entry of [ratios].
///
/// **Each level is cut from the base, not from the level before it.** A chain
/// of simplifications of simplifications stacks each step's error on the
/// last; cutting every level from the full mesh keeps each as good as its own
/// budget allows, and because the simplifier is deterministic a lower target
/// is a higher one's run continued — so the errors still only grow down the
/// chain.
///
/// **A surface that morphs is kept whole in every level.** Its targets are
/// deltas per original vertex, and a simplified mesh has different vertices;
/// dropping the morph would freeze a face at a distance where an animated one
/// is still readable. A node whose surfaces all morph gets no levels at all.
///
/// **Back into the surface's own layout**, for the reason
/// `flutter3d_model_core`'s `project_document.dart` gives: the simplifier
/// answers in the attributes it reads, and a mesh node draws every level
/// through one vertex layout.
///
/// [report] receives one [LodLevelReport] per ratio, in the order given.
ModelDocument generateLods(
  ModelDocument document,
  List<double> ratios, {
  void Function(LodLevelReport level)? report,
}) {
  if (ratios.isEmpty) return document;
  final ordered = <double>[...ratios]..sort((a, b) => b.compareTo(a));

  final surfaces = <ModelSurface>[...document.surfaces];
  final nodes = document.nodes;
  // Per ratio: the target and reached triangles, and the worst error.
  final targets = List<int>.filled(ordered.length, 0);
  final reached = List<int>.filled(ordered.length, 0);
  final errors = List<double>.filled(ordered.length, 0.0);
  // One simplification per surface and ratio, however many nodes draw it.
  final cut = <(int, int), int>{};

  int levelSurface(int surfaceIndex, int level) => cut.putIfAbsent(
    (surfaceIndex, level),
    () {
      final source = document.surfaces[surfaceIndex];
      final base = source.mesh;
      if (base.morphTargets.isNotEmpty || base.triangleCount < 2) {
        return surfaceIndex;
      }
      final target = (base.triangleCount * ordered[level]).round().clamp(
        1,
        base.triangleCount,
      );
      final simplified = simplifyMeshWithAttributesMeasured(
        base,
        targetTriangleCount: target,
      );
      targets[level] += target;
      reached[level] += simplified.mesh.triangleCount;
      errors[level] = math.max(errors[level], simplified.error);
      surfaces.add(
        ModelSurface(
          mesh: simplified.mesh.convertedTo(base.layout),
          transform: source.transform.clone(),
          materialIndex: source.materialIndex,
          skinIndex: source.skinIndex,
          flipWinding: source.flipWinding,
          name: source.name == null ? null : '${source.name} lod ${level + 1}',
          meshName: source.meshName,
          morphWeights: source.morphWeights,
          authoredAttributes: source.authoredAttributes,
        ),
      );
      return surfaces.length - 1;
    },
  );

  bool simplifiable(int surfaceIndex) =>
      document.surfaces[surfaceIndex].mesh.morphTargets.isEmpty;

  final withLevels = <ModelNode>[
    for (final node in nodes)
      if (node.lods.isNotEmpty ||
          node.surfaces.isEmpty ||
          !node.surfaces.any(simplifiable))
        node
      else
        ModelNode(
          name: node.name,
          translation: node.translation,
          rotation: node.rotation,
          scale: node.scale,
          children: node.children,
          surfaces: node.surfaces,
          extras: node.extras,
          lightIndex: node.lightIndex,
          cameraIndex: node.cameraIndex,
          lods: <ModelLod>[
            for (var level = 0; level < ordered.length; level++)
              ModelLod(
                surfaceIndices: <int>[
                  for (final s in node.surfaces) levelSurface(s, level),
                ],
                maxScreenFraction: lodScreenFraction(ordered[level]),
              ),
          ],
        ),
  ];

  for (var level = 0; level < ordered.length; level++) {
    report?.call(
      LodLevelReport(
        ratio: ordered[level],
        targetTriangles: targets[level],
        triangles: reached[level],
        error: errors[level],
      ),
    );
  }

  return PlainModelDocument(
    surfaces: surfaces,
    materials: document.materials,
    images: document.images,
    nodes: withLevels,
    animations: document.animations,
    skins: document.skins,
    lights: document.lights,
    cameras: document.cameras,
    warnings: document.warnings,
    asset: document.asset,
  );
}

/// `0.5,0.25,0.1` as ratios, or null when any entry is not a number strictly
/// between zero and one — a level at the base's own size is no level, and a
/// ratio past it asks the simplifier for detail there is not.
List<double>? parseLodRatios(String text) {
  final ratios = <double>[];
  for (final part in text.split(',')) {
    final ratio = double.tryParse(part.trim());
    if (ratio == null || ratio <= 0 || ratio >= 1) return null;
    ratios.add(ratio);
  }
  return ratios;
}
