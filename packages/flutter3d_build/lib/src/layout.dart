/// `ap-04`'s other half: where `assets_src/` and `flutter3d_generated/` sit
/// in a project, and what to convert given an optional [AssetManifest].
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
}

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
