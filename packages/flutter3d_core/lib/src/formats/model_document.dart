import 'package:vector_math/vector_math.dart';

import 'animation/animation_clip.dart';
import 'animation/animation_mask.dart';
import 'model_camera.dart';
import 'model_light.dart';
import 'model_node.dart';
import 'surface_material.dart';

// `SurfaceMaterial` and its texture inputs describe how a surface looks;
// `ModelSurface`/`ModelNode`/`ModelSkin` describe the hierarchy they hang
// from; `ModelLight`/`ModelCamera` are the two things a node can point at
// besides a mesh. None of the four touches anything private in another or
// in this file, so they are ordinary files, re-exported here so every
// existing import of `model_document.dart` keeps seeing the whole document
// vocabulary.
export 'model_camera.dart';
export 'model_light.dart';
export 'model_node.dart';
export 'surface_material.dart';

/// What the source file said about itself, as opposed to what it contains:
/// the tool that wrote it, and who made it and on what terms.
///
/// **The rights travel with the model.** A model loaded from the hub, or
/// from anywhere else somebody else made it, carries its [author], its
/// [license] and its [copyright] on the result of the load, so an
/// application can credit it and a tool can refuse to ship one with no
/// licence. glTF says them in two places, and both are read and written:
/// `asset.copyright`, and the document's `KHR_xmp_json_ld` packet, whose
/// `dc:creator` is the author and whose `dc:rights` is the licence. The
/// packet is kept whole in [xmp], so a key nothing here reads survives a
/// write.
///
/// glTF's required schema `version` is not here: it is the format's, not
/// the file's.
final class DocumentAsset {
  /// What a file said about itself; every field it did not say is null.
  const DocumentAsset({
    this.generator,
    this.extras,
    this.copyright,
    this.author,
    this.license,
    this.xmp,
  });

  /// The tool that wrote the file — glTF's `asset.generator`, e.g. `"Blender
  /// 4.2"`. Null when the file does not say, which most hand-built test
  /// documents and every OBJ do not.
  final String? generator;

  /// The copyright notice, as the file writes it — glTF's
  /// `asset.copyright`, e.g. `"© 2026 Ada Modeller"`. Null when it says none.
  final String? copyright;

  /// Who made the model, as the file names them — the `dc:creator` of
  /// glTF's `KHR_xmp_json_ld` packet, several creators joined with `, `.
  /// Null when the file does not say.
  final String? author;

  /// The terms the model may be used on: an SPDX identifier (`CC-BY-4.0`)
  /// where the author wrote one, otherwise their words — the `dc:rights` of
  /// glTF's `KHR_xmp_json_ld` packet. Null when the file does not say,
  /// which is not the same as free to use.
  final String? license;

  /// The document's own XMP packet, as JSON-LD — glTF's `KHR_xmp_json_ld`
  /// packet the root `asset` points at — carried whole the way [extras] is.
  /// [author] and [license] are read from it; a writer writes it back with
  /// those two put in, so the keys nothing here reads survive. Null for a
  /// file with none.
  final Map<String, Object?>? xmp;

  /// This asset with the fields given changed.
  DocumentAsset copyWith({
    String? generator,
    Map<String, Object?>? extras,
    String? copyright,
    String? author,
    String? license,
    Map<String, Object?>? xmp,
  }) => DocumentAsset(
    generator: generator ?? this.generator,
    extras: extras ?? this.extras,
    copyright: copyright ?? this.copyright,
    author: author ?? this.author,
    license: license ?? this.license,
    xmp: xmp ?? this.xmp,
  );

  /// The root glTF document's own `extras` — `fmt-19`'s own row, and the
  /// "document" of "extras on node/material/skin/clip/document." Carried
  /// opaquely the same way `ModelNode.extras` is: nothing here reads a key
  /// out of it, a decoder copies the JSON object verbatim, and a writer
  /// copies it back.
  final Map<String, Object?>? extras;

  @override
  bool operator ==(Object other) =>
      other is DocumentAsset &&
      other.generator == generator &&
      other.copyright == copyright &&
      other.author == author &&
      other.license == license &&
      _mapEquals(other.extras, extras) &&
      _mapEquals(other.xmp, xmp);

  @override
  // The two maps compare deeply and would hash by identity, so they stay
  // out: equal assets must hash alike.
  int get hashCode => Object.hash(generator, copyright, author, license);

  @override
  String toString() =>
      'DocumentAsset(generator: $generator, author: $author, '
      'license: $license)';
}

/// Deep-enough equality for two `extras` blocks — plain JSON values, so
/// `Map`/`List`/`String`/`num`/`bool`/`null` is the whole alphabet either
/// side of `==` needs to agree on. `DeepCollectionEquality` is `package
/// :collection`'s and this file has no other reason to depend on it, so a
/// small recursive check is cheaper than the import.
bool _mapEquals(Map<String, Object?>? a, Map<String, Object?>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key)) return false;
    if (!_jsonEquals(entry.value, b[entry.key])) return false;
  }
  return true;
}

bool _jsonEquals(Object? a, Object? b) {
  if (a is Map<String, Object?> && b is Map<String, Object?>) {
    return _mapEquals(a, b);
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// A decoded model, whatever format it came from.
///
/// The seam between decoders and the rest of the engine: glTF and OBJ both
/// produce one of these, so uploading, instancing and material conversion are
/// written once instead of per format.
abstract base class ModelDocument {
  /// A const constructor for the documents that extend this one.
  const ModelDocument();

  /// Every drawable piece of the model: a mesh, its material index and its
  /// transform.
  List<ModelSurface> get surfaces;

  /// The materials [surfaces] refer to by index.
  List<SurfaceMaterial> get materials;

  /// The encoded images the materials' texture bindings refer to by index.
  List<EncodedImage> get images;

  /// What the source file said about itself. Null for a format that carries
  /// no such block, or a document nobody has set one on.
  DocumentAsset? get asset => null;

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
  ///
  /// **Worked out from [nodes], not assumed to be all of them.** Every node was
  /// a root while the only default hierarchy was the flat one above; a
  /// document handed a real tree of nodes and no roots of its own — the
  /// converter rebuilding a glTF scene as a `PlainModelDocument` is one — then
  /// listed every child as a root as well, so a scene built from it placed the
  /// child twice and a glTF written from it named a child in `scene.nodes`.
  List<int> get roots {
    final all = nodes;
    final children = <int>{for (final node in all) ...node.children};
    return <int>[
      for (var i = 0; i < all.length; i++)
        if (!children.contains(i)) i,
    ];
  }

  /// Clips that drive [nodes]. Empty for formats that carry no animation.
  List<AnimationClip> get animations => const <AnimationClip>[];

  /// The joints at and under the node called [name], as a mask a layer takes.
  ///
  /// **The hierarchy walk lives here because the hierarchy does.**
  /// `AnimationTarget` is three setters and no parents, deliberately — see
  /// `AnimationMask` — so the player cannot work out what is under a spine and
  /// is handed the answer instead. [nodes] is the tree, and its indices are the
  /// ones an animation channel addresses, so the set that comes out needs no
  /// translation on the way in.
  ///
  /// An empty mask when nothing carries that name, which a caller should treat
  /// as a miss rather than as "everything": a layer over an empty mask writes
  /// nothing, so a misspelt joint is a layer that does nothing rather than a
  /// layer that takes over the whole skeleton. [AnimationMask.everything] is
  /// how a caller asks for the whole skeleton on purpose.
  AnimationMask maskUnder(String name) {
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i].name == name) return maskUnderIndex(i);
    }
    return AnimationMask(const <int>[]);
  }

  /// The same, from an index into [nodes].
  ///
  /// Iterative rather than recursive, and it carries a seen set: a malformed
  /// document whose children point back up their own branch would otherwise
  /// walk for ever, and a decoder is exactly the place a cycle arrives from.
  AnimationMask maskUnderIndex(int root) {
    if (root < 0 || root >= nodes.length) return AnimationMask(const <int>[]);
    final found = <int>{};
    final pending = <int>[root];
    while (pending.isNotEmpty) {
      final index = pending.removeLast();
      if (index < 0 || index >= nodes.length) continue;
      if (!found.add(index)) continue;
      pending.addAll(nodes[index].children);
    }
    return AnimationMask(found);
  }

  /// Skeletons. Empty for formats that carry no skinning.
  List<ModelSkin> get skins => const <ModelSkin>[];

  /// Punctual lights a node in [nodes] may point at, by
  /// [ModelNode.lightIndex] — `fmt-28`'s own row. Empty for formats that
  /// carry no light, which is every one of them except glTF's own
  /// `KHR_lights_punctual`.
  List<ModelLight> get lights => const <ModelLight>[];

  /// Names of the material variants a surface may switch to —
  /// `KHR_materials_variants`. A surface's own
  /// [ModelSurface.variantMaterials] says which material it wears in each,
  /// by index into this list. Empty for the models that come in one look,
  /// which is nearly all of them and every format but glTF and `.f3d`.
  List<String> get variants => const <String>[];

  /// Cameras a node in [nodes] may point at, by [ModelNode.cameraIndex].
  /// Empty for formats that carry none — OBJ and `.f3d` among them.
  List<ModelCamera> get cameras => const <ModelCamera>[];

  /// Gaussian splat clouds, each with the node that carries it — `C1`.
  /// Empty for every format except glTF with `KHR_gaussian_splatting`; a PLY
  /// capture is read by `parseSplatPly` into a bare `SplatCloud` instead,
  /// since it has no nodes to attach one to.
  List<ModelSplat> get splats => const <ModelSplat>[];

  /// Non-fatal findings from decoding: ignored extensions, skipped primitives,
  /// unresolved references. Surfaced rather than logged so callers can decide
  /// whether to care.
  List<String> get warnings;

  /// Count of vertices across every surface's mesh.
  int get vertexCount {
    var total = 0;
    for (final surface in surfaces) {
      total += surface.mesh.vertexCount;
    }
    return total;
  }

  /// Count of triangles across every surface's mesh.
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
