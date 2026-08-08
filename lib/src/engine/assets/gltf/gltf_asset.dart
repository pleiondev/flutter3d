import '../../animation/animation.dart';
import '../model_document.dart';

/// The decoded result of a glTF or GLB file.
///
/// A [ModelDocument], so materials, images and surfaces use the shared
/// abstraction rather than glTF-specific types: the uploader and the OBJ decoder
/// then speak the same language, and glTF-shaped concepts stay inside the decoder.
final class GltfAsset extends ModelDocument {
  const GltfAsset({
    required this.surfaces,
    required this.materials,
    required this.images,
    required this.warnings,
    required this.nodes,
    required this.roots,
    this.animations = const <AnimationClip>[],
  });

  @override
  final List<ModelSurface> surfaces;

  @override
  final List<SurfaceMaterial> materials;

  @override
  final List<EncodedImage> images;

  @override
  final List<String> warnings;

  /// The real glTF hierarchy, not the flat default: animation targets nodes by
  /// index, and a node that moves has to take its subtree with it.
  @override
  final List<ModelNode> nodes;

  @override
  final List<int> roots;

  @override
  final List<AnimationClip> animations;

  @override
  String toString() => 'GltfAsset(${surfaces.length} surfaces, $vertexCount '
      'vertices, $triangleCount triangles, ${materials.length} materials, '
      '${images.length} images, ${nodes.length} nodes, '
      '${animations.length} animations)';
}
