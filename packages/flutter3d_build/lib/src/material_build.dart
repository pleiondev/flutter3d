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
///
/// **The compiler of one material is `flutter3d_build_hooks`'**
/// ([compileMaterial], [MaterialCompilers], [MaterialBuildException], and
/// [generateMaterialAccessors] for the typed accessors), exported here: a package's own build hook compiles its materials through
/// that light package, without this one's converters and servers.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter3d_build_hooks/flutter3d_build_hooks.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_hardware/shader_bundle.dart';
import 'package:flutter3d_shaders/compile.dart';

import 'layout.dart';
import 'pipeline_version.dart';

/// What one call to [runMaterialBuild] did.
final class MaterialBuildReport {
  const MaterialBuildReport({
    required this.built,
    required this.skipped,
    required this.dependencies,
  });

  /// RenderMaterial sources this run compiled.
  final List<String> built;

  /// RenderMaterial sources whose bundle was already current.
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
      'flutter3d_build: $glslangExecutable or $nagaExecutable is not on PATH, so material '
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
  // **Every version a bundle's reader checks is in the stamp**, so a flutter3d
  // update that moves the container, the WebGPU section or the material
  // section rebuilds every bundle here instead of shipping one the runtime
  // refuses as stale (decision 8 of `tasks/1.0-stability.md`). Mutation: drop
  // `ShaderBundle.formatVersion` and a bumped container ships the old bytes.
  final stamp =
      '$engineHash ${tools.sdk} $assetPipelineVersion '
      'f3sb${ShaderBundle.formatVersion} wgsl$sectionVersion '
      'mat$materialSectionVersion lang$materialLanguageVersion '
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
  _writeAccessors(projectRoot, plan, sink);
  return MaterialBuildReport(
    built: built,
    skipped: skipped,
    dependencies: <String>[
      for (final job in plan) job.source,
      for (final file in shaders.sources.keys) '${shaders.root}/$file',
    ],
  );
}

/// Item 22: the project's typed accessors, `lib/materials.g.dart` — a class
/// per material with a `uniform` ([generateMaterialAccessors]) — written
/// beside `lib/plugins.g.dart` the way that file is, and only when it
/// changed, so an editor watching `lib/` does not reanalyse on every build.
///
/// Only in a package whose pubspec names `vector_math`, which the accessors
/// import for their vector members; elsewhere the log says why there is
/// none. Removed again when no material has a uniform left.
void _writeAccessors(Directory projectRoot, List<AssetPlan> plan, IOSink sink) {
  final pubspec = File('${projectRoot.path}/pubspec.yaml');
  if (!pubspec.existsSync()) return;
  final file = File('${projectRoot.path}/lib/materials.g.dart');
  final programs = <MaterialProgram>[];
  final from = <String, String>{};
  for (final job in plan) {
    final MaterialProgram program;
    try {
      program = parseMaterial(File(job.source).readAsStringSync());
    } on MaterialSyntaxException {
      // The bundle build above already refused it, naming the line.
      continue;
    }
    programs.add(program);
    from[program.name] = job.source.substring(projectRoot.path.length + 1);
  }
  final anyUniform = programs.any((p) => p.parameters.any((q) => q.uniform));
  if (!anyUniform) {
    if (file.existsSync()) file.deleteSync();
    return;
  }
  if (!RegExp(
    r'^\s+vector_math:',
    multiLine: true,
  ).hasMatch(pubspec.readAsStringSync())) {
    sink.writeln(
      'flutter3d_build: no lib/materials.g.dart — the typed material '
      'accessors import vector_math, which pubspec.yaml does not name',
    );
    return;
  }
  final text = generateMaterialAccessors(programs, from: from);
  if (file.existsSync() && file.readAsStringSync() == text) return;
  file
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);
}

/// The material cache's envelope. A cache written by another layout — the
/// bare map before 1.0, or a later build's — reads as empty and every
/// material builds again once: for a stamp, the conservative answer, which
/// is why the layout is matched exactly.
const String _cacheFormat = 'f3d.materialCache';
const int _cacheLayout = 1;

Map<String, String> _readCache(String path) {
  final file = File(path);
  if (!file.existsSync()) return const <String, String>{};
  try {
    return switch (jsonDecode(file.readAsStringSync())) {
      {
        'format': _cacheFormat,
        'version': _cacheLayout,
        'entries': final Map<String, Object?> entries,
      } =>
        entries.map((key, value) => MapEntry(key, value! as String)),
      _ => const <String, String>{},
    };
  } on FormatException {
    return const <String, String>{};
  } on TypeError {
    return const <String, String>{};
  }
}

void _writeCache(String path, Map<String, String> cache) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode(<String, Object?>{
        'format': _cacheFormat,
        'version': _cacheLayout,
        'requires': const <String>[],
        'generator': 'flutter3d',
        'entries': cache,
      }),
    );
}
