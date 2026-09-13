/// `ap-06`'s real logic — compiling this package's own shader bundle
/// through `impellerc` — kept apart from `hook/build.dart`'s
/// `BuildInput`/`BuildOutputBuilder` and from `bin/build_shader_bundle.dart`'s
/// argument parsing, for the same reason `ap-05`'s `runAssetBuild` sits
/// apart from `buildAssets`: a plain `Directory` is what a test can hand it
/// directly, and what both real callers actually have once they have found
/// their own package root.
library;

import 'dart:convert';
import 'dart:io';

/// Thrown on any failure here — `hook/build.dart` wraps it as a
/// [BuildError][], `bin/build_shader_bundle.dart` prints it and exits
/// non-zero. Plain rather than a `package:hooks` type, because this file
/// has no reason to depend on hooks at all.
///
/// [BuildError]: https://pub.dev/documentation/hooks/latest/hooks/BuildError-class.html
final class ShaderBundleBuildException implements Exception {
  const ShaderBundleBuildException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Compiles `flutter3d_shaders`'s own manifest into
/// `<packageRoot>/assets/shaders/flutter3d.shaderbundle` through
/// `impellerc`, and returns the sources it read — the manifest and every
/// GLSL file under `flutter3d_shaders/shaders/` — so a caller with a build
/// hook's own dependency list can declare them.
Future<List<Uri>> buildShaderBundle({
  required Directory packageRoot,
  IOSink? log,
}) async {
  final sink = log ?? stdout;
  final shadersRoot = _resolvePackageRoot('flutter3d_shaders', packageRoot);
  final manifest = File(
    '${shadersRoot.path}/shaders/flutter3d.shaderbundle.json',
  );
  if (!manifest.existsSync()) {
    throw ShaderBundleBuildException('no manifest at ${manifest.path}');
  }

  final sdkRoot = _flutterSdkRoot();
  final platform = _hostArtifactPlatform(sdkRoot);
  final impellerc = File(
    '$sdkRoot/bin/cache/artifacts/engine/$platform/impellerc',
  );
  if (!impellerc.existsSync()) {
    throw ShaderBundleBuildException(
      'impellerc not found at ${impellerc.path} — run "flutter precache" '
      'for this platform',
    );
  }
  final shaderLib = '$sdkRoot/bin/cache/artifacts/engine/$platform/shader_lib';

  final outFile = File('${packageRoot.path}/assets/shaders/flutter3d.shaderbundle')
    ..parent.createSync(recursive: true);

  final result = await Process.run(impellerc.path, <String>[
    '--shader-bundle=${manifest.readAsStringSync()}',
    '--sl=${outFile.path}',
    '--include=${shadersRoot.path}/shaders',
    '--include=$shaderLib',
  ], workingDirectory: shadersRoot.path);

  if (result.exitCode != 0) {
    throw ShaderBundleBuildException(
      'impellerc failed (${result.exitCode}):\n${result.stderr}',
    );
  }

  sink.writeln(
    'flutter3d_impeller: shader bundle written to ${outFile.path} '
    '(${outFile.lengthSync()} bytes)',
  );

  return <Uri>[
    manifest.uri,
    for (final entity in Directory('${shadersRoot.path}/shaders').listSync(recursive: true))
      if (entity is File) entity.uri,
  ];
}

/// Resolves another workspace package's own root directory by reading
/// `.dart_tool/package_config.json` directly — the same file, read the
/// same way, as `tool/package_root.dart` already reads it for
/// `build_shaders.sh`'s own `-P`/`sources.txt` resolution, ported here
/// rather than shared, because a `tool/` script is not a package this one
/// can depend on.
///
/// **Not `Isolate.resolvePackageUri`, and that was a real finding, not a
/// style choice.** It works from `hook/build.dart` and from
/// `bin/build_shader_bundle.dart` alike, but throws `Unsupported operation:
/// Isolate.resolvePackageUriSync` inside `flutter_test`'s own test
/// environment — found by writing the test this function's own suite
/// needed and watching it fail there specifically, not in either real
/// caller. Reading the JSON directly has no such gap: it is the same file
/// pub already writes for every consumer of this package, workspace member
/// or not.
///
/// `flutter3d_impeller` names `flutter3d_shaders` as a real dependency (see
/// its pubspec) specifically so this resolves for an external consumer
/// too, not only inside this workspace.
Directory _resolvePackageRoot(String packageName, Directory from) {
  final configFile = _findPackageConfig(from);
  if (configFile == null) {
    throw ShaderBundleBuildException(
      'no .dart_tool/package_config.json at or above ${from.path} — has '
      '"flutter pub get" run?',
    );
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(configFile.readAsStringSync());
  } on FormatException catch (error) {
    throw ShaderBundleBuildException('${configFile.path}: ${error.message}');
  }
  if (decoded is! Map<String, Object?> || decoded['packages'] is! List) {
    throw ShaderBundleBuildException(
      '${configFile.path} is not a package config',
    );
  }

  for (final entry in decoded['packages']! as List<Object?>) {
    if (entry is! Map<String, Object?> || entry['name'] != packageName) {
      continue;
    }
    final rootUri = entry['rootUri'];
    if (rootUri is! String) {
      throw ShaderBundleBuildException(
        'package "$packageName" has no string "rootUri" in '
        '${configFile.path}',
      );
    }
    // A relative rootUri resolves against package_config.json's own
    // location — workspace members read as `../../packages/foo` — while
    // an absolute `file:` URI (the pub cache) resolves to itself.
    final resolved = Uri.file(configFile.absolute.path).resolve(rootUri);
    var path = resolved.toFilePath();
    if (path.length > 1 && path.endsWith(Platform.pathSeparator)) {
      path = path.substring(0, path.length - 1);
    }
    return Directory(path);
  }

  throw ShaderBundleBuildException(
    'package "$packageName" is not in ${configFile.path} — is it a '
    'dependency, and has "flutter pub get" run since it was added?',
  );
}

/// Walks up from [start] looking for `.dart_tool/package_config.json` — a
/// workspace has exactly one, at the workspace root, not one per member.
File? _findPackageConfig(Directory start) {
  var directory = start.absolute;
  if (directory.existsSync()) {
    directory = Directory(directory.resolveSymbolicLinksSync());
  }
  while (true) {
    final candidate = File(
      '${directory.path}${Platform.pathSeparator}.dart_tool'
      '${Platform.pathSeparator}package_config.json',
    );
    if (candidate.existsSync()) return candidate;

    final parent = directory.parent;
    if (parent.path == directory.path) return null;
    directory = parent;
  }
}

/// The Flutter SDK root, derived from the executable actually running this
/// process rather than from `flutter` on PATH or `$FLUTTER_ROOT`.
///
/// **Proven empirically, not assumed — twice.** A real `flutter build
/// macos -v` on a throwaway project showed `Platform.resolvedExecutable`
/// pointing at `<flutter_root>/bin/cache/dart-sdk/bin/dart` and
/// `$FLUTTER_ROOT` unset — hooks do not inherit it, so `tool/
/// build_shaders.sh`'s own `flutter --version --machine` fallback has
/// nothing to read from a hook. Writing this function's own test then
/// found the second shape: `flutter test` does not run under that Dart VM
/// at all — it runs under `flutter_tester`, the engine's own headless
/// embedder, under the same SDK's `bin/cache/artifacts/engine/` as
/// `impellerc` itself. Both are real, both are checked.
String _flutterSdkRoot() {
  final executable = Platform.resolvedExecutable;

  const dartSuffix = '/bin/cache/dart-sdk/bin/dart';
  if (executable.endsWith(dartSuffix)) {
    return executable.substring(0, executable.length - dartSuffix.length);
  }

  const artifactsMarker = '/bin/cache/artifacts/engine/';
  final markerIndex = executable.indexOf(artifactsMarker);
  if (markerIndex >= 0 && executable.endsWith('/flutter_tester')) {
    return executable.substring(0, markerIndex);
  }

  throw ShaderBundleBuildException(
    'cannot find the Flutter SDK root from $executable — this only '
    'understands running under a Flutter-bundled Dart SDK or under '
    'flutter_tester',
  );
}

/// The artifact directory name for this host, tried in the same order
/// `tool/build_shaders.sh` does — macOS ships one universal `darwin-x64`
/// bundle even on Apple silicon, so the candidate that actually exists on
/// disk wins rather than a guess from `Platform.operatingSystem`.
String _hostArtifactPlatform(String sdkRoot) {
  final artifacts = Directory('$sdkRoot/bin/cache/artifacts/engine');
  final candidates = switch (Platform.operatingSystem) {
    'macos' => const <String>['darwin-x64', 'darwin-arm64'],
    'linux' => const <String>['linux-x64', 'linux-arm64'],
    'windows' => const <String>['windows-x64', 'windows-arm64'],
    _ => const <String>['darwin-x64', 'linux-x64', 'windows-x64'],
  };
  for (final candidate in candidates) {
    if (File('${artifacts.path}/$candidate/impellerc').existsSync()) {
      return candidate;
    }
  }
  throw ShaderBundleBuildException(
    'no impellerc under ${artifacts.path} for any of $candidates — run '
    '"flutter precache"',
  );
}
