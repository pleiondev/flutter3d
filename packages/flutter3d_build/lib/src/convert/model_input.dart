/// The model formats: glTF and GLB, OBJ with its MTL, STL, PLY, and FBX and
/// `.blend` through an external tool. Each becomes a `.f3d`; its materials
/// become `.fmat` files; a format with a scene (glTF, FBX, `.blend`) also
/// becomes a level document whose prefab places the model.
library;

import 'dart:io';

import 'package:flutter3d_core/formats.dart';

import 'context.dart';
import 'materials.dart';
import 'output.dart';
import 'ply_mesh.dart';
import 'report.dart';
import 'scene.dart';

/// The extensions read as a model.
const Set<String> modelExtensions = <String>{
  '.gltf',
  '.glb',
  '.obj',
  '.stl',
  '.ply',
  '.spz',
  '.fbx',
  '.blend',
};

/// The model formats whose source is a scene, and so also get a level.
const Set<String> _sceneModelExtensions = <String>{
  '.gltf',
  '.glb',
  '.fbx',
  '.blend',
};

/// The format name a report gives a model file.
String modelFormatName(String path) => switch (extensionOf(path)) {
  '.gltf' || '.glb' => 'gltf',
  '.obj' => 'obj',
  '.stl' => 'stl',
  '.ply' => 'ply',
  '.spz' => 'splat',
  '.fbx' => 'fbx',
  '.blend' => 'blend',
  _ => 'model',
};

/// Converts the model file [source] into [context]'s plan.
Future<void> convertModelInput(
  String source,
  ConvertContext context,
  ConvertReport report,
) async {
  final extension = extensionOf(source);
  if (extension == '.spz' ||
      (extension == '.ply' && isSplatPly(File(source).readAsBytesSync()))) {
    _convertSplat(source, context, report);
    return;
  }
  final converted = await context.modelFile(source, report, primary: true);
  if (converted == null) return;
  final (modelPath, document) = converted;
  _reportDocument(document, report);

  final materials = <SceneMaterial>[
    // STL and PLY carry no material, only the default the reader gives.
    if (context.writeMaterials && extension != '.stl' && extension != '.ply')
      for (final material in materialsOfDocument(
        document,
        safeFileName(stemOf(source)),
      ))
        planMaterial(
          material,
          context.plan,
          owner: report.input,
          report: report,
        ),
  ];

  if (!_sceneModelExtensions.contains(extension)) return;
  final id = safeFileName(stemOf(source));
  final prefab = ScenePrefab(id, <SceneItem>[
    SceneItem(name: id, asset: modelPath),
  ]);
  context.prefabs[File(source).absolute.path] = <ScenePrefab>[prefab];
  final level = levelDocument(
    name: id,
    prefabs: <ScenePrefab>[prefab],
    materials: materials,
    prefix: context.assetPrefix,
    report: report,
  );
  final path = context.plan.addText(
    '$id${OutputLayout.level}',
    level,
    owner: report.input,
  );
  report.written.add(path);
  report.map(
    'scene -> prefab "$id" in $path, placing the model with its own node '
    'tree (${document.nodes.length} nodes)',
  );
}

void _reportDocument(ModelDocument document, ConvertReport report) {
  for (final material in document.materials) {
    final extensions = material.extensions;
    if (extensions == null) continue;
    final layers = <String>[
      if (extensions.clearcoat > 0.0) 'clearcoat',
      if (extensions.transmission > 0.0) 'transmission',
      if (extensions.sheenColor.r > 0.0 ||
          extensions.sheenColor.g > 0.0 ||
          extensions.sheenColor.b > 0.0)
        'sheen',
      if (extensions.iridescence > 0.0) 'iridescence',
      if (extensions.anisotropyStrength > 0.0) 'anisotropy',
      if ((extensions.ior - 1.5).abs() > 1e-6) 'ior',
      if (extensions.specular != 1.0) 'specular',
      if (extensions.thickness > 0.0) 'volume',
      if (extensions.dispersion > 0.0) 'dispersion',
    ];
    if (layers.isNotEmpty) {
      report.map(
        'material "${material.name ?? '?'}" layers: ${layers.join(', ')}',
      );
    }
  }
  if (document.lights.isNotEmpty || document.cameras.isNotEmpty) {
    report.map(
      '${document.lights.length} lights and ${document.cameras.length} '
      'cameras stay on their nodes inside the model',
    );
  }
  if (document.variants.isNotEmpty) {
    report.map('material variants: ${document.variants.join(', ')}');
  }
}

void _convertSplat(
  String source,
  ConvertContext context,
  ConvertReport report,
) {
  final bytes = File(source).readAsBytesSync();
  final SplatCloud cloud;
  try {
    cloud = extensionOf(source) == '.spz'
        ? parseSplatSpz(bytes, keepHigherBands: false)
        : parseSplatPly(bytes);
  } on Object catch (error) {
    report.fail('could not read a splat capture: $error');
    return;
  }
  final tree = buildSplatOctree(cloud, leafCapacity: 512, grid: 8);
  final encoded = encodeSplatOctree(tree);
  final back = parseSplatOctree(encoded);
  if (back.leafSplatCount != cloud.count) {
    report.fail(
      'the written tree holds ${back.leafSplatCount} splats of ${cloud.count}',
    );
    return;
  }
  final path = context.plan.add(
    '${safeFileName(stemOf(source))}$splatOctreeExtension',
    encoded,
    owner: report.input,
  );
  report.written.add(path);
  report.map(
    'splat capture -> $path: ${cloud.count} splats, ${tree.nodes.length} '
    'nodes',
  );
  if (extensionOf(source) == '.spz') {
    report.drop('higher spherical harmonic bands', 'the tree keeps band 0');
  }
}
