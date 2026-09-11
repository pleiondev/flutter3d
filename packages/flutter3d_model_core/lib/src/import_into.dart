/// `ImportInto(project, document, options)` — merging a second file into a
/// project that already has objects in it, rather than starting over.
///
/// **Reuses [fromModelDocument] wholesale rather than reimplementing the
/// node walk, the up-axis correction or the socket handling.** The only
/// difference between "import" and "import into" is what happens to the
/// result afterwards: [fromModelDocument] hands back a project of its own,
/// built from id 1; this renumbers every one of its objects under fresh ids
/// that continue [project]'s own, and folds its material and image tables
/// into [project]'s existing ones instead of replacing them.
///
/// **Materials and images are deduplicated by content, not by name or
/// position.** Importing the same asset twice — this row's own acceptance,
/// "два импорта подряд" — must not double the material table just because
/// the file was opened a second time: two materials that would write the
/// identical manifest entry are the same material, whatever each file
/// happened to call it or in what order its own textures came in. Images
/// compare by their own bytes alone — `sourceUri`, `name` and `mimeType`
/// are where a picture came from, not what it is — and materials compare by
/// every field a `.f3dproj` manifest would write for one, *after* the
/// incoming material's own texture bindings have already been rewritten
/// onto the merged image table: two materials sampling the same picture are
/// not "the same" by their raw, pre-merge index alone, which could differ
/// even when the pictures do not.
///
/// **The comparison is a fresh, parallel statement of the same fields
/// `project_format.dart`'s own `_materialJson`/`_bindingJson` write, not a
/// shared function.** The two are separate libraries within this package —
/// `project_format.dart`'s helpers are file-private — and duplicating a
/// dozen field names here is the honest cost of that, the same trade this
/// session has made at other package boundaries: a wrong field here
/// compiles, runs, and is wrong only for the material that hits it, which is
/// exactly why both copies are covered by their own tests rather than one
/// standing in for the other.
///
/// **Skeletons are not carried across yet.** The plan's own row asks for
/// them to come in "as new" alongside the objects and the tables; `anim-*`
/// (phase 3) is what gives [ModelProject] a skeleton list to add one to, so
/// there is nothing here for a skeleton to become until then —
/// [fromModelDocument] itself is in the identical position today, and this
/// inherits it rather than gets ahead of it.
library;

import 'dart:convert';

import 'package:flutter3d_formats/flutter3d_formats.dart';

import 'material.dart';
import 'project.dart';
import 'project_document.dart';

/// [document] merged into [project]: every one of its objects added under a
/// fresh id, its materials and images folded into the existing tables by
/// content, and its own hierarchy and roots preserved as roots of the
/// merged project too — at [options]'s own scale and up-axis correction,
/// the same ones [fromModelDocument] would apply importing the document on
/// its own.
ImportReport importInto(
  ModelProject project,
  ModelDocument document, {
  ImportOptions options = const ImportOptions(),
}) {
  final incoming = fromModelDocument(document, options: options);

  // Images first: a material's own texture bindings have to be rewritten
  // onto the merged table before two materials can be honestly compared —
  // see the library doc comment.
  final imageAt = <int, int>{};
  var images = project.images;
  final imageKeys = <String>[
    for (final EncodedImage each in images) base64Encode(each.bytes),
  ];
  for (var i = 0; i < incoming.images.length; i++) {
    final key = base64Encode(incoming.images[i].bytes);
    final existing = imageKeys.indexOf(key);
    if (existing >= 0) {
      imageAt[i] = existing;
    } else {
      imageAt[i] = images.length;
      images = <EncodedImage>[...images, incoming.images[i]];
      imageKeys.add(key);
    }
  }

  final materialAt = <int, int>{};
  var materials = project.materials;
  final materialKeys = <String>[
    for (final ProjectMaterial each in materials) _materialKey(each.surface),
  ];
  for (var i = 0; i < incoming.materials.length; i++) {
    final remapped = _remapMaterial(incoming.materials[i].surface, imageAt);
    final key = _materialKey(remapped);
    final existing = materialKeys.indexOf(key);
    if (existing >= 0) {
      materialAt[i] = existing;
    } else {
      materialAt[i] = materials.length;
      materials = <ProjectMaterial>[
        ...materials,
        ProjectMaterial(surface: remapped),
      ];
      materialKeys.add(key);
    }
  }

  var merged = project.copyWith(materials: materials, images: images);

  // `incoming.objects` is guaranteed parent-before-child: `fromModelDocument`
  // only ever queues a node's children after that node itself has already
  // been added to its own project and handed a real id, so every non-null
  // `parent` here names an object earlier in this same list.
  final idAt = <int, int>{};
  for (final ModelObject object in incoming.objects) {
    final assignedId = merged.nextId;
    idAt[object.id] = assignedId;
    merged = merged.added(
      (int id) => ModelObject(
        id: id,
        name: object.name,
        geometry: object.geometry,
        transform: object.transform,
        parent: object.parent == null ? null : idAt[object.parent],
        materialSlots: <int>[
          for (final int slot in object.materialSlots) materialAt[slot]!,
        ],
      ),
    );
  }

  return ImportReport(
    project: merged,
    issues: List<String>.unmodifiable(document.warnings),
    counts: ImportCounts(
      objects: incoming.objects.length,
      materials: incoming.materials.length,
      images: incoming.images.length,
      triangles: incoming.objects.fold(
        0,
        (int sum, ModelObject o) => sum + o.geometry.triangleCount,
      ),
    ),
  );
}

/// [surface] with every texture binding's own `imageIndex` rewritten
/// through [imageAt] — the index it would have in the *merged* image table
/// rather than the one it had in the document it came from.
SurfaceMaterial _remapMaterial(SurfaceMaterial surface, Map<int, int> imageAt) {
  TextureBinding? remap(TextureBinding? binding) => binding == null
      ? null
      : TextureBinding(
          imageIndex: imageAt[binding.imageIndex]!,
          texCoordSet: binding.texCoordSet,
          sampling: binding.sampling,
        );
  return SurfaceMaterial(
    name: surface.name,
    baseColor: surface.baseColor,
    metallic: surface.metallic,
    roughness: surface.roughness,
    baseColorTexture: remap(surface.baseColorTexture),
    metallicRoughnessTexture: remap(surface.metallicRoughnessTexture),
    normalTexture: remap(surface.normalTexture),
    normalScale: surface.normalScale,
    occlusionTexture: remap(surface.occlusionTexture),
    occlusionStrength: surface.occlusionStrength,
    emissiveTexture: remap(surface.emissiveTexture),
    emissive: surface.emissive,
    emissiveStrength: surface.emissiveStrength,
    alphaMode: surface.alphaMode,
    alphaCutoff: surface.alphaCutoff,
    doubleSided: surface.doubleSided,
    unlit: surface.unlit,
  );
}

/// [surface], as a string that is equal for two materials that would write
/// the identical `.f3dproj` manifest entry and different otherwise — see the
/// library doc comment for why this is a parallel statement of
/// `project_format.dart`'s own field list rather than a shared function.
String _materialKey(SurfaceMaterial surface) => jsonEncode(<String, Object?>{
  'name': surface.name,
  'baseColor': <double>[
    surface.baseColor.x,
    surface.baseColor.y,
    surface.baseColor.z,
    surface.baseColor.w,
  ],
  'metallic': surface.metallic,
  'roughness': surface.roughness,
  'baseColorTexture': _bindingKey(surface.baseColorTexture),
  'metallicRoughnessTexture': _bindingKey(surface.metallicRoughnessTexture),
  'normalTexture': _bindingKey(surface.normalTexture),
  'normalScale': surface.normalScale,
  'occlusionTexture': _bindingKey(surface.occlusionTexture),
  'occlusionStrength': surface.occlusionStrength,
  'emissiveTexture': _bindingKey(surface.emissiveTexture),
  'emissive': <double>[
    surface.emissive.x,
    surface.emissive.y,
    surface.emissive.z,
  ],
  'emissiveStrength': surface.emissiveStrength,
  'alphaMode': surface.alphaMode.name,
  'alphaCutoff': surface.alphaCutoff,
  'doubleSided': surface.doubleSided,
  'unlit': surface.unlit,
});

Map<String, Object?>? _bindingKey(TextureBinding? binding) => binding == null
    ? null
    : <String, Object?>{
        'imageIndex': binding.imageIndex,
        'texCoordSet': binding.texCoordSet,
        'magLinear': binding.sampling.magLinear,
        'minLinear': binding.sampling.minLinear,
        'useMipmaps': binding.sampling.useMipmaps,
        'mipLinear': binding.sampling.mipLinear,
        'wrapS': binding.sampling.wrapS.name,
        'wrapT': binding.sampling.wrapT.name,
      };
