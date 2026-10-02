/// P8: a project's materials, written in the material language, compiled
/// ahead of time into shader bundles every GPU backend loads.
///
/// `assets_src/**/*.f3dmat` in, `flutter3d_generated/**/*.f3dshaders` out —
/// [AssetLayout.materialPlan] says which and where. Each source is parsed,
/// emitted as GLSL by `flutter3d_core`'s emitter, resolved against the
/// engine's own headers in `flutter3d_shaders`, and packed into one
/// [ShaderBundle] with three sections: `impellerc`'s output for Impeller,
/// GLSL ES 3.00 for WebGL2, and WGSL with its reflection for WebGPU. The
/// software backend needs no section; it evaluates the same source on the
/// CPU. `GraphicsDevice.loadShaders` takes the result on any of the four.
///
/// **Ahead of time, and only ahead of time.** No backend gains a compiler at
/// run time (decision in §2 of the 0.9 roadmap): a material that does not
/// compile fails the build, on the author's machine, naming the file and the
/// line, rather than a draw on a player's.
///
/// **The WebGPU section is the one allowed to be missing**, for the reason
/// `flutter3d_webgpu/tool/pack_wgsl_section.dart` gives: it needs
/// glslangValidator and naga, which a machine may not have, and a backend's
/// tooling must not become a requirement for everybody else's build. Without
/// them the bundle carries two sections, the log says so, and the WebGPU
/// backend refuses that bundle by name. `impellerc` is never missing in a
/// real build — it ships in the Flutter SDK that runs the hook — so its
/// absence is an error.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_hardware/shader_bundle.dart';
import 'package:flutter3d_shaders/compile.dart';

import 'layout.dart';
import 'pipeline_version.dart';

/// A material that did not build, and where.
///
/// [line] and [column] are the material source's own when the failure is one
/// the parser can place — which is every mistake an author makes in the
/// language. A compiler refusing GLSL the language accepted names the source
/// too, and its own output names the line of the generated `.frag`, kept on
/// disk at the path the message gives.
final class MaterialBuildException implements Exception {
  const MaterialBuildException(
    this.message, {
    required this.source,
    this.line,
    this.column,
  });

  final String message;

  /// The material source, as a path; empty for a failure no one source
  /// caused, such as no `impellerc` to run.
  final String source;
  final int? line;
  final int? column;

  @override
  String toString() => switch ((source, line, column)) {
    ('', _, _) => message,
    (_, final int line, final int column) => '$source:$line:$column: $message',
    (_, final int line, null) => '$source:$line: $message',
    _ => '$source: $message',
  };
}

/// Compiles one prepared stage to WGSL and reports the offsets glslang gave
/// each uniform block member — `compileStage`'s answer, behind a seam a test
/// can replace on a machine with neither compiler.
typedef WgslStageCompiler =
    CompiledStage Function(
      PreparedStage stage, {
      required String name,
      required bool fragment,
    });

/// The programs a material build runs, and the SDK token it stamps.
///
/// A value rather than a lookup inside the build, so a test hands it a stub
/// `impellerc` the way `flutter3d_impeller`'s own tests do, and so a build
/// that needs none of them — a project without materials — never looks.
final class MaterialCompilers {
  const MaterialCompilers({
    required this.impellerc,
    required this.sdk,
    this.impellerIncludes = const <String>[],
    this.wgsl,
  });

  /// `impellerc`'s path.
  final String impellerc;

  /// Extra `--include` roots for `impellerc`: the SDK's `shader_lib`.
  final List<String> impellerIncludes;

  /// What [ShaderBundle.sdk] says — the Dart that ran `impellerc`'s SDK, which
  /// is the Dart running this build when the build runs as a hook.
  final String sdk;

  /// Null when glslangValidator or naga is not on `PATH`: the bundle then
  /// carries no WebGPU section.
  final WgslStageCompiler? wgsl;

  /// The compilers of the Flutter SDK this process runs under, and glslang
  /// and naga from `PATH` when both answer.
  ///
  /// Throws [MaterialBuildException] when there is no `impellerc` — this
  /// process is not a Flutter SDK's Dart, or the SDK's artifacts were never
  /// downloaded.
  static MaterialCompilers locate() {
    final sdkRoot = flutterSdkRootFrom(Platform.resolvedExecutable);
    final name = Platform.isWindows ? 'impellerc.exe' : 'impellerc';
    final artifacts = '$sdkRoot/bin/cache/artifacts/engine';
    // macOS ships one universal `darwin-x64` directory even on Apple silicon,
    // so the candidate that exists wins rather than a guess from the host.
    final platform = switch (Platform.operatingSystem) {
      'macos' => const <String>['darwin-x64', 'darwin-arm64'],
      'linux' => const <String>['linux-x64', 'linux-arm64'],
      'windows' => const <String>['windows-x64', 'windows-arm64'],
      _ => const <String>['darwin-x64', 'linux-x64', 'windows-x64'],
    }.where((p) => File('$artifacts/$p/$name').existsSync()).firstOrNull;
    if (platform == null) {
      throw MaterialBuildException(
        'no $name under $artifacts — run "flutter precache" for this host',
        source: '',
      );
    }
    return MaterialCompilers(
      impellerc: '$artifacts/$platform/$name',
      impellerIncludes: <String>['$artifacts/$platform/shader_lib'],
      sdk: Platform.version.split(' ').first,
      wgsl: _answers(kGlslang) && _answers(kNaga) ? _compileWgsl : null,
    );
  }
}

CompiledStage _compileWgsl(
  PreparedStage stage, {
  required String name,
  required bool fragment,
}) => compileStage(stage.glsl, name: name, fragment: fragment);

bool _answers(String program) {
  try {
    Process.runSync(program, const <String>['--version']);
    return true;
  } on ProcessException {
    return false;
  }
}

/// The Flutter SDK root under [executable]: the SDK's own Dart, or
/// `flutter_tester` under its engine artifacts.
///
/// The search `flutter3d_impeller`'s `shader_bundle_build.dart` makes, and
/// ported rather than shared: that package names Flutter, and this one is a
/// build hook that cannot resolve a package that does. Its doc comment holds
/// the measurements behind each shape — `$FLUTTER_ROOT` unset inside a hook,
/// `flutter_tester` under `flutter test`, backslashes and `.exe` on Windows.
String flutterSdkRootFrom(String executable) {
  final normalized = executable.replaceAll(r'\', '/');
  const dart = '/bin/cache/dart-sdk/bin/dart';
  for (final suffix in <String>[dart, '$dart.exe']) {
    if (normalized.endsWith(suffix)) {
      return executable.substring(0, executable.length - suffix.length);
    }
  }
  const artifacts = '/bin/cache/artifacts/engine/';
  final at = normalized.indexOf(artifacts);
  if (at >= 0 &&
      (normalized.endsWith('/flutter_tester') ||
          normalized.endsWith('/flutter_tester.exe'))) {
    return executable.substring(0, at);
  }
  throw MaterialBuildException(
    'cannot find the Flutter SDK from $executable, so there is no impellerc '
    'to compile materials with — build through `flutter`, whose Dart runs '
    'this hook',
    source: '',
  );
}

/// What one call to [runMaterialBuild] did.
final class MaterialBuildReport {
  const MaterialBuildReport({
    required this.built,
    required this.skipped,
    required this.dependencies,
  });

  /// Material sources this run compiled.
  final List<String> built;

  /// Material sources whose bundle was already current.
  final List<String> skipped;

  /// Every file the bundles were made from — each material source, and every
  /// engine header they can include — for a hook to declare, so an edit to
  /// any of them runs the hook again.
  final List<String> dependencies;
}

/// Compiles every material [AssetLayout.materialPlan] finds under
/// [projectRoot].
///
/// [compilers] defaults to [MaterialCompilers.locate] and [engine] to the
/// `flutter3d_shaders` the project resolves; both are looked up only when
/// there is a material to build, so a project without one needs neither a
/// Flutter SDK nor the engine's sources.
///
/// A bundle whose inputs have not changed — the source, every engine shader,
/// the SDK stamp and which sections the compilers can make — is left alone.
/// A bundle whose source is gone is deleted, because `flutter3d_generated/`
/// is bundled whole and would otherwise ship it.
///
/// Throws [MaterialBuildException] on the first material that does not build,
/// having written nothing for it.
MaterialBuildReport runMaterialBuild(
  Directory projectRoot, {
  IOSink? log,
  MaterialCompilers? compilers,
  ShaderSet? engine,
}) {
  final layout = AssetLayout(projectRoot: projectRoot);
  final plan = layout.materialPlan();
  final cachePath = '${layout.generatedDir.path}/.flutter3d_materials.json';
  final previous = _readCache(cachePath);
  final sink = log ?? stdout;

  // Bundles a previous build wrote for sources that are no longer planned.
  for (final stale in previous.keys) {
    if (plan.any((job) => job.destination == stale)) continue;
    final file = File(stale);
    if (file.existsSync()) file.deleteSync();
  }
  if (plan.isEmpty) {
    if (previous.isNotEmpty) File(cachePath).deleteSync();
    return const MaterialBuildReport(
      built: <String>[],
      skipped: <String>[],
      dependencies: <String>[],
    );
  }

  final ShaderSet shaders;
  try {
    shaders = engine ?? loadShaders(from: projectRoot.path);
  } on StateError catch (error) {
    throw MaterialBuildException(
      'the engine\'s shaders are not reachable from ${projectRoot.path}: '
      '${error.message}',
      source: plan.first.source,
    );
  }
  final tools = compilers ?? MaterialCompilers.locate();
  if (tools.wgsl == null) {
    sink.writeln(
      'flutter3d_build: $kGlslang or $kNaga is not on PATH, so material '
      'bundles get no "webgpu" section and the WebGPU backend will refuse '
      'them by name. glslangValidator comes with the Vulkan SDK or `brew '
      'install glslang`; naga from `cargo install naga-cli`.',
    );
  }

  final engineHash = sha256
      .convert(
        utf8.encode(
          (shaders.sources.keys.toList()..sort())
              .map((key) => '$key\n${shaders.sources[key]}')
              .join('\n'),
        ),
      )
      .toString();
  final stamp =
      '$engineHash ${tools.sdk} $kAssetPipelineVersion '
      '${tools.wgsl == null ? 'no-webgpu' : 'webgpu'}';

  final next = <String, String>{};
  final built = <String>[];
  final skipped = <String>[];
  for (final job in plan) {
    final text = File(job.source).readAsStringSync();
    final key = '${sha256.convert(utf8.encode(text))} $stamp';
    next[job.destination] = key;
    if (previous[job.destination] == key &&
        File(job.destination).existsSync()) {
      skipped.add(job.source);
      continue;
    }

    final bundle = compileMaterial(
      text,
      source: job.source,
      engine: shaders,
      compilers: tools,
      scratch: Directory(
        '${projectRoot.path}/.dart_tool/flutter3d_build/materials',
      ),
    );
    final bytes = bundle.encode();
    File(job.destination)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    sink.writeln(
      'flutter3d_build: ${job.destination} — "${bundle.name}", sections '
      '${bundle.sections.keys.join(', ')}',
    );
    built.add(job.source);
  }

  _writeCache(cachePath, next);
  return MaterialBuildReport(
    built: built,
    skipped: skipped,
    dependencies: <String>[
      for (final job in plan) job.source,
      for (final file in shaders.sources.keys) '${shaders.root}/$file',
    ],
  );
}

/// One material [text] as a bundle with a fragment stage named after the
/// material, compiled for every backend [compilers] can serve.
///
/// [source] is the path every failure names. [scratch] is where the
/// generated `.frag` is written for `impellerc`, and where it stays when
/// a compiler refuses it, so the line in that compiler's message is a line
/// somebody can open.
ShaderBundle compileMaterial(
  String text, {
  required String source,
  required ShaderSet engine,
  required MaterialCompilers compilers,
  required Directory scratch,
}) {
  final MaterialProgram program;
  try {
    program = parseMaterial(text);
  } on MaterialSyntaxError catch (error) {
    throw MaterialBuildException(
      error.message,
      source: source,
      line: error.line,
      column: error.column,
    );
  }
  // One entry point per source, at its declared defaults. A variant is a
  // second entry point with other constants folded in, and naming those is
  // the manifest's to grow when somebody needs one.
  final name = program.name;
  final glsl = emitMaterialFragment(
    specialiseMaterial(program, MaterialVariant(name)),
  );

  Never refused(String what, String message) =>
      throw MaterialBuildException('$what: $message', source: source);

  final generated = File('${scratch.path}/$name.frag')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(glsl);

  final impeller = _impeller(name, generated, engine, compilers, refused);

  final String webgl;
  final String resolved;
  try {
    webgl = translateGlsl(glsl, engine.sources, from: source, fragment: true);
    resolved = resolveIncludes(glsl, engine.sources, from: source);
  } on GlslTranslateError catch (error) {
    refused('the WebGL2 translation', error.message);
  }

  final webgpu = switch (compilers.wgsl) {
    null => null,
    final compile => _webgpu(
      name,
      source,
      resolved,
      engine,
      compile,
      generated,
      refused,
    ),
  };

  // Nothing went wrong, so nothing needs opening.
  generated.deleteSync();

  return ShaderBundle(
    name: name,
    sdk: compilers.sdk,
    stages: <ShaderBundleStage>[ShaderBundleStage(name, fragment: true)],
    sections: <String, ByteData>{
      ShaderBundle.impellerSection: impeller,
      ShaderBundle.webglSection: encodeWebGlSection(
        vertex: const <String, String>{},
        fragment: <String, String>{name: webgl},
      ),
      ShaderBundle.webgpuSection: ?webgpu,
      // The source itself, for the backend that compiles nothing and for a
      // runtime that builds the material's lighting model from it — `P8`.
      ShaderBundle.materialSection: encodeMaterialSection(<String, String>{
        name: text,
      }),
    },
  );
}

ByteData _impeller(
  String name,
  File generated,
  ShaderSet engine,
  MaterialCompilers compilers,
  Never Function(String, String) refused,
) {
  final out = File('${generated.parent.path}/$name.shaderbundle');
  final ProcessResult result;
  try {
    result = Process.runSync(compilers.impellerc, <String>[
      '--shader-bundle=${jsonEncode(<String, Object>{
        name: <String, String>{'type': 'fragment', 'file': generated.path},
      })}',
      '--sl=${out.path}',
      // The tree the other two sections are translated against, read off
      // the set rather than found again, so the three cannot disagree.
      '--include=${engine.root}',
      for (final include in compilers.impellerIncludes) '--include=$include',
    ], workingDirectory: generated.parent.path);
  } on ProcessException catch (error) {
    refused(
      'impellerc',
      'could not run ${compilers.impellerc}: ${error.message}',
    );
  }
  if (result.exitCode != 0 || !out.existsSync()) {
    refused(
      'impellerc',
      'refused the GLSL generated from it, kept at ${generated.path} '
          '(exit ${result.exitCode}):\n${result.stdout}${result.stderr}',
    );
  }
  final bytes = out.readAsBytesSync();
  out.deleteSync();
  return bytes.buffer.asByteData();
}

ByteData _webgpu(
  String name,
  String source,
  String resolved,
  ShaderSet engine,
  WgslStageCompiler compile,
  File generated,
  Never Function(String, String) refused,
) {
  try {
    final prepared = prepareStage(
      resolved,
      from: source,
      fragment: true,
      varyingLocations: bundleVaryingLocations(engine, <BundleStageSource>[
        (file: source, fragment: true, resolved: resolved),
      ]),
    );
    final compiled = compile(prepared, name: name, fragment: true);
    checkStd140Offsets(name, prepared, compiled.offsets);
    final document = wgslSectionDocument(
      vertex: const <String, PackedStage>{},
      fragment: <String, PackedStage>{
        name: (wgsl: compiled.wgsl, prepared: prepared),
      },
    );
    return Uint8List.fromList(utf8.encode(document)).buffer.asByteData();
  } on WgslPrepareError catch (error) {
    refused('the WebGPU preparation', error.message);
  } on WgslCompileError catch (error) {
    refused(
      'the WebGPU compile',
      '${error.message}\n(the GLSL it was generated from is kept at '
          '${generated.path})',
    );
  } on WgslSectionError catch (error) {
    refused('the WebGPU section', error.message);
  }
}

Map<String, String> _readCache(String path) {
  final file = File(path);
  if (!file.existsSync()) return const <String, String>{};
  try {
    return (jsonDecode(file.readAsStringSync()) as Map<String, Object?>).map(
      (key, value) => MapEntry(key, value! as String),
    );
  } on FormatException {
    return const <String, String>{};
  } on TypeError {
    return const <String, String>{};
  }
}

void _writeCache(String path, Map<String, String> cache) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(cache));
}
