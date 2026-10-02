/// `ap-04`'s other half: where `assets_src/` and `flutter3d_generated/` sit
/// in a project, and what to convert given an optional [AssetManifest] —
/// models, and since P8 materials written in the material language.
library;

import 'dart:io';

import 'convert.dart';
import 'manifest.dart';

/// One file [AssetLayout.plan] found: where it is, where the converted
/// output goes, and the rule (if any) that governs how.
final class AssetPlan {
  const AssetPlan({required this.source, required this.destination, this.rule});

  final String source;
  final String destination;
  final AssetRule? rule;
}

/// A project's asset directories, and the plan a hook (`ap-05`) or the CLI's
/// own batch mode reads to know what to convert and where.
final class AssetLayout {
  AssetLayout({required this.projectRoot, AssetManifest? manifest})
    : manifest = manifest ?? AssetManifest.readFrom(projectRoot);

  final Directory projectRoot;
  final AssetManifest manifest;

  /// Every source a project author writes by hand.
  Directory get sourcesDir => Directory('${projectRoot.path}/assets_src');

  /// What a hook writes, and what `flutter: assets:` names — `ap-00`'s own
  /// spike proved a plain `assets:` directory is the half of build hooks
  /// that works on stable, and this is that directory's one name.
  Directory get generatedDir =>
      Directory('${projectRoot.path}/flutter3d_generated');

  /// Every recognised source under [sourcesDir], paired with where it lands
  /// and the rule that applies — empty when [sourcesDir] does not exist or
  /// holds nothing recognised, which is `ap-04`'s own "an empty project
  /// plans cleanly" half of its acceptance: nothing here needs `ap-05`'s
  /// hook to exist to prove it, because planning and converting are two
  /// different questions and this answers only the first.
  List<AssetPlan> plan() {
    if (!sourcesDir.existsSync()) return const <AssetPlan>[];

    final result = <AssetPlan>[];
    for (final entity in sourcesDir.listSync(recursive: true)) {
      if (entity is! File) continue;
      final relative = entity.path.substring(sourcesDir.path.length + 1);
      if (!recognisedExtensions.contains(_extensionOf(relative))) continue;

      final rule = manifest.ruleFor(relative);
      if (rule?.exclude ?? false) continue;

      result.add(
        AssetPlan(
          source: entity.path,
          destination: '${generatedDir.path}/${_asF3d(relative)}',
          rule: rule,
        ),
      );
    }
    return result;
  }

  /// Every material source under [sourcesDir] — P8 — paired with the shader
  /// bundle it compiles into: `assets_src/fx/rim.f3dmat` becomes
  /// `flutter3d_generated/fx/rim.f3dshaders`.
  ///
  /// **The same tree as the models, not a `shaders/` of its own.** A material
  /// belongs to the asset that wears it, and an author who keeps `crate.glb`
  /// and `crate_glow.f3dmat` side by side should not have to split them
  /// because one is compiled by a different program. The output lands where
  /// `flutter: assets:` already looks, so a project that bundles
  /// `flutter3d_generated/` ships its materials with no new line in its
  /// pubspec. A manifest rule's `glob` and `exclude` hold here as they do for
  /// a model; nothing else in a rule means anything to a material.
  ///
  /// **`.f3dmat`, a name nothing else claims** — and kept out of
  /// [recognisedExtensions], so the model plan never tries to decode one.
  List<AssetPlan> materialPlan() {
    if (!sourcesDir.existsSync()) return const <AssetPlan>[];
    return <AssetPlan>[
      for (final entity in sourcesDir.listSync(recursive: true))
        if (entity is File && _extensionOf(entity.path) == materialExtension)
          if (_relativeTo(entity) case final relative)
            if (manifest.ruleFor(relative) case final rule
                when !(rule?.exclude ?? false))
              AssetPlan(
                source: entity.path,
                destination:
                    '${generatedDir.path}/'
                    '${relative.substring(0, relative.length - materialExtension.length)}'
                    '$shaderBundleExtension',
                rule: rule,
              ),
    ];
  }

  String _relativeTo(File file) =>
      file.path.substring(sourcesDir.path.length + 1);
}

/// What a material source is called — P8. Matched case-insensitively, like
/// every other extension here.
const String materialExtension = '.f3dmat';

/// What a compiled material is called: a `ShaderBundle`, the same container
/// `GraphicsDevice.loadShaders` takes from any other packer.
const String shaderBundleExtension = '.f3dshaders';

String _extensionOf(String path) {
  final dot = path.lastIndexOf('.');
  final slash = path.lastIndexOf('/');
  return dot > slash ? path.substring(dot).toLowerCase() : '';
}

String _asF3d(String relativePath) {
  final dot = relativePath.lastIndexOf('.');
  final slash = relativePath.lastIndexOf('/');
  return dot > slash
      ? '${relativePath.substring(0, dot)}.f3d'
      : '$relativePath.f3d';
}
