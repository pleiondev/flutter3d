/// What every reader of `flutter3d convert` shares: the options, the plan
/// of outputs, and the models and prefabs already converted, so a scene
/// that names one model forty times converts it once.
library;

import 'dart:io';

import 'package:flutter3d_core/formats.dart';

import '../convert.dart'
    show F3dRoundTripException, TextureFamily, convertDocument, decodeModelFile;
import 'external.dart';
import 'output.dart';
import 'ply_mesh.dart';
import 'report.dart';
import 'scene.dart';

/// The model-side options, passed to every `.f3d` written.
final class ModelSettings {
  const ModelSettings({
    this.textures = TextureFamily.auto,
    this.mips = true,
    this.lods = const <double>[],
    this.impostor = false,
    this.chunks,
  });

  /// A copy with the given fields replaced. A `clear…` flag resets that
  /// nullable field to null, which passing null cannot say.
  ModelSettings copyWith({
    TextureFamily? textures,
    bool? mips,
    List<double>? lods,
    bool? impostor,
    int? chunks,
    bool clearChunks = false,
  }) => ModelSettings(
    textures: textures ?? this.textures,
    mips: mips ?? this.mips,
    lods: lods ?? this.lods,
    impostor: impostor ?? this.impostor,
    chunks: clearChunks ? null : (chunks ?? this.chunks),
  );

  final TextureFamily textures;
  final bool mips;
  final List<double> lods;
  final bool impostor;
  final int? chunks;
}

/// One run's shared state.
final class ConvertContext {
  ConvertContext({
    required this.plan,
    required this.assetPrefix,
    this.models = const ModelSettings(),
    this.writeMaterials = true,
    this.externalTools = true,
  });

  /// Whether FBX, `.blend` and binary USD may be handed to the programs
  /// in `external.dart`. A server that runs no external binary turns it
  /// off, and those inputs are reported as unsupported there.
  final bool externalTools;

  /// Where outputs are planned.
  final OutputPlan plan;

  /// What a document puts in front of an output's path.
  final String assetPrefix;

  final ModelSettings models;

  /// Whether a model's materials are also written as `.fmat` files.
  final bool writeMaterials;

  /// Source path (absolute) to the `.f3d` planned for it.
  final Map<String, String> _models = <String, String>{};
  final Map<String, ModelDocument> _documents = <String, ModelDocument>{};

  /// Source path (absolute) to the prefabs converted from it, the first
  /// being the file itself.
  final Map<String, List<ScenePrefab>> prefabs = <String, List<ScenePrefab>>{};

  /// SurfaceMaterial id to what was planned for it, across the run.
  final Map<String, SceneMaterial> materials = <String, SceneMaterial>{};

  /// Forgets what was planned at [paths], so a later input that needs the
  /// same model or material plans it again.
  void forget(Iterable<String> paths) {
    final gone = paths.toSet();
    final stale = <String>[
      for (final MapEntry(:key, :value) in _models.entries)
        if (gone.contains(value)) key,
    ];
    for (final key in stale) {
      _models.remove(key);
      _documents.remove(key);
    }
    materials.removeWhere((String _, SceneMaterial m) => gone.contains(m.file));
  }

  /// Plans [document] as `.f3d` at [relative]. Returns the path planned.
  Future<String> planModel(
    ModelDocument document,
    String relative,
    ConvertReport report,
  ) async {
    final converted = await convertDocument(
      document,
      report: (String line) => report.map('model: $line'),
      textures: models.textures,
      mips: models.mips,
      lods: models.lods,
      impostor: models.impostor,
      chunks: models.chunks,
    );
    final path = plan.add(relative, converted.bytes, owner: report.input);
    if (!report.written.contains(path)) report.written.add(path);
    final d = converted.document;
    report.map(
      'model -> $path: ${d.surfaces.length} surfaces, ${d.triangleCount} '
      'triangles, ${d.materials.length} materials, ${d.images.length} '
      'images, ${d.animations.length} animations',
    );
    for (final warning in d.warnings) {
      report.warn('model: $warning');
    }
    return path;
  }

  /// The model file at [source] (glTF, GLB, OBJ, STL, PLY, FBX, `.blend`)
  /// planned as `.f3d`, once per run: [primary] puts it at the top of the
  /// output as `<stem>.f3d`, otherwise under `models/`. Returns the planned
  /// path and the document, or null with the reason in [report].
  Future<(String, ModelDocument)?> modelFile(
    String source,
    ConvertReport report, {
    bool primary = false,
  }) async {
    final key = File(source).absolute.path;
    final known = _models[key];
    final cached = _documents[key];
    if (known != null && cached != null) return (known, cached);
    final document = await readModelFile(source, report);
    if (document == null) return null;
    final relative = primary
        ? '${safeFileName(stemOf(source))}.f3d'
        : '${OutputLayout.models}/${safeFileName(stemOf(source))}.f3d';
    try {
      final path = await planModel(document, relative, report);
      _models[key] = path;
      _documents[key] = document;
      return (path, document);
    } on F3dRoundTripException catch (error) {
      report.fail('the written model does not read back: $error');
      return null;
    }
  }

  /// Reads a model file into a document, through an external tool where the
  /// format needs one. Null with the reason in [report] on failure.
  Future<ModelDocument?> readModelFile(
    String source,
    ConvertReport report,
  ) async {
    if (!File(source).existsSync()) {
      report.fail('no such file: $source');
      return null;
    }
    final extension = extensionOf(source);
    try {
      switch (extension) {
        case '.ply':
          // Its notes ride on the document's warnings, which the report
          // hears when the model is planned.
          return readPlyMesh(File(source).readAsBytesSync());
        case '.fbx' || '.blend' when !externalTools:
          report.fail(
            '${extension.substring(1)} is read through an external program '
            '(FBX2glTF or Blender), and this converter runs none; export glTF',
            as: ConvertOutcome.missingTool,
          );
          return null;
        case '.fbx' || '.blend':
          final work = Directory.systemTemp.createTempSync(
            'flutter3d_convert_',
          );
          try {
            final glb = extension == '.fbx'
                ? fbxToGlb(source, work)
                : blendToGlb(source, work);
            report.map(
              '${extension.substring(1)} -> glTF through '
              '${extension == '.fbx' && fbx2gltf.locate() != null ? 'FBX2glTF' : 'Blender'}',
            );
            return await decodeModelFile(glb);
          } finally {
            work.deleteSync(recursive: true);
          }
        default:
          return await decodeModelFile(source);
      }
    } on MissingToolException catch (error) {
      report.fail(error.message, as: ConvertOutcome.missingTool);
      return null;
    } on Object catch (error) {
      report.fail('could not read $source: $error');
      return null;
    }
  }
}
