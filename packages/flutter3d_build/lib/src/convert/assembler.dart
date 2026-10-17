/// A model document built up piece by piece, by a reader whose source is
/// not a model file: a USD stage, a Godot scene's primitive meshes.
library;

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/geometry.dart' show MeshData;
import 'package:vector_math/vector_math.dart';

import 'materials.dart';

/// Collects nodes, surfaces, materials and images into one
/// [PlainModelDocument].
final class DocumentAssembler {
  final List<ModelSurface> surfaces = <ModelSurface>[];
  final List<ModelNode> nodes = <ModelNode>[];
  final List<SurfaceMaterial> materials = <SurfaceMaterial>[];
  final List<EncodedImage> images = <EncodedImage>[];
  final List<String> warnings = <String>[];
  final Map<String, int> _materials = <String, int>{};

  /// Whether nothing drawable was added.
  bool get isEmpty => surfaces.isEmpty;

  /// The index of the material [key], adding [source] the first time:
  /// its images are appended to the document's, its bindings moved to
  /// match.
  int material(String key, MaterialSource Function() source) {
    final known = _materials[key];
    if (known != null) return known;
    final made = source();
    final offset = images.length;
    for (final image in made.images) {
      images.add(
        EncodedImage(
          bytes: image.bytes,
          name: image.name,
          mimeType: mimeTypeOf(image.name),
          sourceUri: image.name,
        ),
      );
    }
    materials.add(shiftSurfaceImages(made.surface, offset));
    _materials[key] = materials.length - 1;
    return materials.length - 1;
  }

  /// Adds a node placed by [local] under [parent] (an index into [nodes]),
  /// or as a root. Returns its index.
  int node(String name, Matrix4 local, {int? parent}) {
    final translation = Vector3.zero();
    final rotation = Quaternion.identity();
    final scale = Vector3.zero();
    local.decompose(translation, rotation, scale);
    nodes.add(
      ModelNode(
        name: name,
        translation: translation,
        rotation: rotation,
        scale: scale,
      ),
    );
    final index = nodes.length - 1;
    if (parent != null) nodes[parent].children.add(index);
    return index;
  }

  /// Adds [mesh], placed by [world] in the model, to node [node].
  void surface(
    int node,
    MeshData mesh,
    Matrix4 world, {
    int? material,
    String? name,
    Set<String>? authored,
  }) {
    surfaces.add(
      ModelSurface(
        mesh: mesh,
        transform: world,
        materialIndex: material,
        name: name,
        authoredAttributes: authored,
      ),
    );
    nodes[node].surfaces.add(surfaces.length - 1);
  }

  ModelDocument build() => PlainModelDocument(
    surfaces: surfaces,
    materials: materials,
    images: images,
    nodes: nodes,
    warnings: warnings,
  );
}
