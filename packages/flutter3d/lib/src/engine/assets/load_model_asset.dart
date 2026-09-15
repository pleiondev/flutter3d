/// `ap-11`: `loadModelAsset('assets_src/chair.glb')` — a model named by its
/// source path, reading the build hook's own converted `.f3d`
/// (`ap-05`/`ap-10`) rather than the source itself, because that is what
/// every build after the first `init` actually ships.
library;

import 'dart:io' show FileSystemException;

import 'package:flutter/foundation.dart'
    show FlutterError, debugPrint, kDebugMode, kIsWeb;
import 'package:flutter3d_formats/flutter3d_formats.dart';

import 'model_loader.dart';

/// `assets_src/`'s own name — the one `AssetLayout.sourcesDir` in
/// `flutter3d_build` also uses — stripped from the front of a source path
/// before it is rewritten under `flutter3d_generated/`.
const String _sourceDirPrefix = 'assets_src/';

/// Where the build hook would have written [sourcePath]'s converted
/// output — `flutter3d_generated/<same relative path>.f3d`, the exact
/// mapping `AssetLayout.plan` computes in `flutter3d_build`, reimplemented
/// here in three lines rather than imported: the engine depends on no
/// build-time package (`tool/structure.dart`'s "a genre package reaches no
/// other genre"), and three lines is not worth a dependency for.
String generatedAssetPathFor(String sourcePath) {
  final relative = sourcePath.startsWith(_sourceDirPrefix)
      ? sourcePath.substring(_sourceDirPrefix.length)
      : sourcePath;
  final dot = relative.lastIndexOf('.');
  final withoutExtension = dot < 0 ? relative : relative.substring(0, dot);
  return 'flutter3d_generated/$withoutExtension.f3d';
}

/// Every [sourcePath] this isolate has already warned about — so a control
/// that calls [loadModelAsset] once per frame (a hot-reload preview, a level
/// that streams models in) prints the missing-hook warning once for the
/// life of the process, not once per call.
final Set<String> _warnedMissingGenerated = <String>{};

/// Loads a model by the source path a person actually wrote —
/// `loadModelAsset('assets_src/chair.glb')` — reading
/// [generatedAssetPathFor]'s own `.f3d` rather than decoding the source
/// itself, because that is what a project that has run `dart run
/// flutter3d_build:init` (`ap-10`) and built at least once ships.
///
/// **Missing the generated file is two different answers, on purpose.** In
/// [debugMode] (default: [kDebugMode]) this decodes [sourcePath] directly
/// instead — a project that has never run a build yet still draws
/// something — and prints one warning per [sourcePath] rather than one per
/// call. Outside [debugMode], a missing `.f3d` is a release build that
/// shipped without its own hook ever running, and that is an error naming
/// `flutter3d_build:init`, not a fallback a release build would keep
/// paying the decode cost of.
///
/// **The fallback reads [sourcePath] from disk, not from the asset
/// bundle.** `assets_src/` is deliberately not declared in a project's own
/// `pubspec.yaml` `assets:` — `ap-10` only writes `flutter3d_generated/`
/// there — so there is nothing bundled at [sourcePath] to read in the
/// first place; a [FileAssetSource] reaches the checkout directly instead,
/// which only exists during `flutter run`/`flutter test` from a source
/// tree, never in a shipped build. That makes the fallback unavailable on
/// the web ([kIsWeb], no `dart:io`): there, a missing generated file is
/// the release error in every build mode, not only outside [debugMode].
///
/// [generatedSource] and [fallbackSource] build the two [AssetSource]s —
/// [BundleAssetSource] and [FileAssetSource] by default. A test overrides
/// either to stand in for what a real asset bundle would serve without
/// declaring throwaway fixtures in this package's own `pubspec.yaml`,
/// which would ship them to every application that depends on it.
Future<ModelDocument> loadModelAsset(
  String sourcePath, {
  bool debugMode = kDebugMode,
  AssetSource Function(String path) generatedSource = BundleAssetSource.new,
  AssetSource Function(String path) fallbackSource = FileAssetSource.new,
}) async {
  final generatedPath = generatedAssetPathFor(sourcePath);
  try {
    return await decodeModelInIsolate(
      ModelLoadRequest(source: generatedSource(generatedPath)),
    );
  } on FlutterError {
    return _fallback(sourcePath, generatedPath, debugMode, fallbackSource);
  } on FileSystemException {
    return _fallback(sourcePath, generatedPath, debugMode, fallbackSource);
  }
}

Future<ModelDocument> _fallback(
  String sourcePath,
  String generatedPath,
  bool debugMode,
  AssetSource Function(String path) fallbackSource,
) async {
  if (!debugMode || kIsWeb) {
    throw StateError(
      '$generatedPath is missing. Run `dart run flutter3d_build:init` once '
      'per project (ap-10), then build again — its hook converts '
      '$sourcePath into $generatedPath on every build after that.',
    );
  }
  if (_warnedMissingGenerated.add(sourcePath)) {
    debugPrint(
      'flutter3d: $generatedPath is missing — decoding $sourcePath directly. '
      'This only happens in debug; run `dart run flutter3d_build:init` and '
      'build once to stop seeing this.',
    );
  }
  return decodeModelInIsolate(
    ModelLoadRequest(source: fallbackSource(sourcePath)),
  );
}
