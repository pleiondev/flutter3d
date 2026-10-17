/// How a converted material becomes a file: `.fmat` when it is parameters of
/// a built-in lighting model, `.f3dmat` when it is a program.
///
/// **The rule.** Every material format read here — glTF's PBR, an MTL,
/// UsdPreviewSurface, Unity's Standard and Lit, Godot's StandardMaterial3D —
/// describes a surface as numbers and maps fed to a lighting model the
/// engine already has. That is exactly what `.fmat` is: a
/// `SurfaceMaterial` and the image paths it names, read by the loader with
/// no build step. A `.f3dmat` is a program the build compiles into a shader
/// bundle, and writing one for a material that is only parameters would buy
/// a compile and lose nothing but time. So `.f3dmat` is written only for a
/// MaterialX node graph that computes an input — a texture multiplied by a
/// noise, a mix of two colours — which no set of parameters can say.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:vector_math/vector_math.dart';

import 'output.dart';
import 'report.dart';
import 'scene.dart';

/// A material ready to be written: the surface, and the images its texture
/// bindings index, as bytes with the names they arrived under.
final class MaterialSource {
  const MaterialSource(
    this.id,
    this.surface, {
    this.images = const <MaterialImage>[],
    this.program,
  });

  /// The id the level names it by, and its file's stem.
  final String id;

  /// The parameters. Its bindings' `imageIndex` index [images].
  final SurfaceMaterial surface;

  final List<MaterialImage> images;

  /// The material language source, when the material is a program; it is
  /// then written as `.f3dmat` and [surface] is only what the level's own
  /// fields are filled from.
  final String? program;
}

/// An image a material names.
final class MaterialImage {
  const MaterialImage(this.name, this.bytes);

  /// The file name it is written under in `textures/`.
  final String name;
  final Uint8List bytes;
}

/// Plans [material] in [plan] and returns what a level names it by.
SceneMaterial planMaterial(
  MaterialSource material,
  OutputPlan plan, {
  required String owner,
  required ConvertReport report,
}) {
  final id = safeFileName(material.id);
  if (material.program case final String program) {
    final path = plan.addText(
      '${OutputLayout.materials}/$id.f3dmat',
      program,
      owner: owner,
    );
    report.written.add(path);
    report.map('material "${material.id}" -> $path (a program)');
    return SceneMaterial(id, path, material.surface);
  }
  final texturePaths = <String>[
    for (final image in material.images)
      plan.addTexture(image.name, image.bytes, owner: owner),
  ];
  for (final path in texturePaths) {
    if (!report.written.contains(path)) report.written.add(path);
  }
  final text = writeFmat(
    MaterialDocument(
      surface: material.surface,
      images: <String>[
        for (final path in texturePaths)
          relativePath(path, OutputLayout.materials),
      ],
    ),
  );
  final path = plan.addText(
    '${OutputLayout.materials}/$id.fmat',
    text,
    owner: owner,
  );
  report.written.add(path);
  report.map('material "${material.id}" -> $path');
  return SceneMaterial(id, path, material.surface);
}

/// Every material of a decoded model document as a [MaterialSource], its
/// images taken from the document's own.
List<MaterialSource> materialsOfDocument(ModelDocument document, String stem) {
  final used = <String, int>{};
  return <MaterialSource>[
    for (var i = 0; i < document.materials.length; i++)
      () {
        final material = document.materials[i];
        final base = '${stem}_${material.name ?? 'material$i'}';
        final seen = used[base] ?? 0;
        used[base] = seen + 1;
        final (surface, images) = _reindexImages(material, document.images, i);
        return MaterialSource(
          seen == 0 ? base : '$base-$seen',
          surface,
          images: images,
        );
      }(),
  ];
}

/// [material] with its bindings renumbered to index only the images it uses,
/// and those images.
(SurfaceMaterial, List<MaterialImage>) _reindexImages(
  SurfaceMaterial material,
  List<EncodedImage> all,
  int materialIndex,
) {
  final order = <int>[];
  TextureBinding? remap(TextureBinding? binding) {
    if (binding == null) return null;
    if (binding.imageIndex < 0 || binding.imageIndex >= all.length) {
      return null;
    }
    var at = order.indexOf(binding.imageIndex);
    if (at < 0) {
      order.add(binding.imageIndex);
      at = order.length - 1;
    }
    return TextureBinding(
      imageIndex: at,
      texCoordSet: binding.texCoordSet,
      sampling: binding.sampling,
      transform: binding.transform,
    );
  }

  final surface = SurfaceMaterial(
    name: material.name,
    baseColor: material.baseColor,
    metallic: material.metallic,
    roughness: material.roughness,
    baseColorTexture: remap(material.baseColorTexture),
    metallicRoughnessTexture: remap(material.metallicRoughnessTexture),
    normalTexture: remap(material.normalTexture),
    normalScale: material.normalScale,
    occlusionTexture: remap(material.occlusionTexture),
    occlusionStrength: material.occlusionStrength,
    emissiveTexture: remap(material.emissiveTexture),
    emissive: material.emissive,
    emissiveStrength: material.emissiveStrength,
    alphaMode: material.alphaMode,
    alphaCutoff: material.alphaCutoff,
    doubleSided: material.doubleSided,
    unlit: material.unlit,
    lightingModel: material.lightingModel,
    extensions: material.extensions,
    extras: material.extras,
  );
  final images = <MaterialImage>[
    for (final index in order)
      MaterialImage(
        _imageName(all[index], index, materialIndex),
        all[index].bytes,
      ),
  ];
  return (surface, images);
}

String _imageName(EncodedImage image, int index, int materialIndex) {
  final source = image.sourceUri;
  if (source != null && !source.startsWith('data:')) {
    final decoded = Uri.decodeComponent(source);
    return decoded.substring(decoded.lastIndexOf('/') + 1);
  }
  final ext = switch (image.mimeType) {
    'image/jpeg' => '.jpg',
    'image/webp' => '.webp',
    'image/ktx2' => '.ktx2',
    _ => '.png',
  };
  final name = image.name;
  if (name != null && name.isNotEmpty) {
    return name.contains('.') ? name : '$name$ext';
  }
  return 'image$index$ext';
}

/// A colour as `Vector4` from three or four numbers, alpha 1 when absent.
Vector4 colorOf(List<double> rgba) =>
    Vector4(rgba[0], rgba[1], rgba[2], rgba.length > 3 ? rgba[3] : 1.0);

/// [m] with [doubleSided] and [name] replaced, everything else kept.
SurfaceMaterial copySurface(
  SurfaceMaterial m, {
  bool? doubleSided,
  String? name,
}) => SurfaceMaterial(
  name: name ?? m.name,
  baseColor: m.baseColor,
  metallic: m.metallic,
  roughness: m.roughness,
  baseColorTexture: m.baseColorTexture,
  metallicRoughnessTexture: m.metallicRoughnessTexture,
  normalTexture: m.normalTexture,
  normalScale: m.normalScale,
  occlusionTexture: m.occlusionTexture,
  occlusionStrength: m.occlusionStrength,
  emissiveTexture: m.emissiveTexture,
  emissive: m.emissive,
  emissiveStrength: m.emissiveStrength,
  alphaMode: m.alphaMode,
  alphaCutoff: m.alphaCutoff,
  doubleSided: doubleSided ?? m.doubleSided,
  unlit: m.unlit,
  lightingModel: m.lightingModel,
  extensions: m.extensions,
  extras: m.extras,
);

/// [binding] pointing [offset] images further on.
TextureBinding? shiftBinding(TextureBinding? binding, int offset) =>
    binding == null
    ? null
    : TextureBinding(
        imageIndex: binding.imageIndex + offset,
        texCoordSet: binding.texCoordSet,
        sampling: binding.sampling,
        transform: binding.transform,
      );

/// [m] with every binding moved [offset] images on — a material whose
/// images are appended to a document's after others.
SurfaceMaterial shiftSurfaceImages(SurfaceMaterial m, int offset) =>
    SurfaceMaterial(
      name: m.name,
      baseColor: m.baseColor,
      metallic: m.metallic,
      roughness: m.roughness,
      baseColorTexture: shiftBinding(m.baseColorTexture, offset),
      metallicRoughnessTexture: shiftBinding(
        m.metallicRoughnessTexture,
        offset,
      ),
      normalTexture: shiftBinding(m.normalTexture, offset),
      normalScale: m.normalScale,
      occlusionTexture: shiftBinding(m.occlusionTexture, offset),
      occlusionStrength: m.occlusionStrength,
      emissiveTexture: shiftBinding(m.emissiveTexture, offset),
      emissive: m.emissive,
      emissiveStrength: m.emissiveStrength,
      alphaMode: m.alphaMode,
      alphaCutoff: m.alphaCutoff,
      doubleSided: m.doubleSided,
      unlit: m.unlit,
      lightingModel: m.lightingModel,
      extensions: m.extensions,
      extras: m.extras,
    );

/// The MIME type of an image file, by its name.
String mimeTypeOf(String name) => switch (extensionOf(name)) {
  '.jpg' || '.jpeg' => 'image/jpeg',
  '.webp' => 'image/webp',
  '.ktx2' => 'image/ktx2',
  _ => 'image/png',
};
