/// One material, compiled ahead of time into a shader bundle every GPU
/// backend loads: what a build hook runs for a package's own materials.
///
/// A material source is parsed, emitted as GLSL by `flutter3d_core`'s
/// emitter, resolved against the engine's own headers in `flutter3d_shaders`,
/// and packed into one [ShaderBundle] with three sections: `impellerc`'s
/// output for Impeller, GLSL ES 3.00 for WebGL2, and WGSL with its reflection
/// for WebGPU. The software backend needs no section; it evaluates the same
/// source on the CPU.
///
/// **Ahead of time, and only ahead of time.** No backend gains a compiler at
/// run time: a material that does not compile fails the build, on the
/// author's machine, naming the file and the line, rather than a draw on a
/// player's.
///
/// **A backend's own compiler is asked too** (D26). [MaterialCompilers.registry]
/// holds the `MaterialCompiler`s of the backends a build serves; each is
/// handed the stages as GLSL, the engine's headers and the WebGPU stages
/// already written, and its section goes into the bundle, a fifth backend's
/// beside the three above or in place of one of them. A compiler whose
/// section the build writes with a tool of its own
/// (`MaterialCompiler.isSectionWrittenByBuild`) and that refuses leaves that
/// section as the build wrote it, which is what Impeller's does, since
/// `impellerc` runs here; any other refusal fails the build with its
/// sentence.
///
/// **The WebGPU section is the one allowed to be missing**: it needs
/// glslangValidator and naga, which a machine may not have, and a backend's
/// tooling must not become a requirement for everybody else's build. Without
/// them the bundle carries two sections and the WebGPU backend refuses that
/// bundle by name; WebGPU's own compiler, which packs the WGSL they write,
/// is not asked. `impellerc` is never missing in a real build — it ships in
/// the Flutter SDK that runs the hook — so its absence is an error.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Flutter3dFormatException;
import 'package:flutter3d_hardware/shader_bundle.dart';
import 'package:flutter3d_shaders/backend.dart'
    show
        MaterialCompileException,
        MaterialCompileRequest,
        MaterialCompilerRegistry,
        MaterialStageBudget,
        MaterialStageSource;
import 'package:flutter3d_shaders/compile.dart';
import 'package:flutter3d_shaders/kernel.dart' show ComputeKernel, kernelBundle;

/// A material that did not build, and where.
///
/// [line] and [column] are the material source's own when the failure is one
/// the parser can place — which is every mistake an author makes in the
/// language. A compiler refusing GLSL the language accepted names the source
/// too, and its own output names the line of the generated `.frag`, kept on
/// disk at the path the message gives.
final class MaterialBuildException extends Flutter3dFormatException {
  const MaterialBuildException(
    this.message, {
    required this.source,
    this.line,
    this.column,
  });

  @override
  final String message;

  /// The material source, as a path; empty for a failure no one source
  /// caused, such as no `impellerc` to run.
  @override
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
    this.registry,
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

  /// The backends' own material compilers, each asked for its section after
  /// the three this build writes itself; null for none.
  final MaterialCompilerRegistry? registry;

  /// The compilers of the Flutter SDK this process runs under, glslang and
  /// naga from `PATH` when both answer, and [registry]'s.
  ///
  /// Throws [MaterialBuildException] when there is no `impellerc` — this
  /// process is not a Flutter SDK's Dart, or the SDK's artifacts were never
  /// downloaded.
  static MaterialCompilers locate({MaterialCompilerRegistry? registry}) {
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
      wgsl: _answers(glslangExecutable) && _answers(nagaExecutable)
          ? _compileWgsl
          : null,
      registry: registry,
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

/// One material [text] as a bundle with a fragment stage named after the
/// material, compiled for every backend [compilers] can serve; a `compute`
/// stage as a bundle of its kernel, lowered to the kernel language
/// (`lowerMaterialCompute`), which every device with compute loads.
///
/// [source] is the path every failure names. [scratch] is where the
/// generated `.frag` is written for `impellerc`, and where it stays when
/// a compiler refuses it, so the line in that compiler's message is a line
/// somebody can open.
///
/// [namespace] is the plugin's that ships the source, for a plugin's
/// material: the bare name the file writes (`material Hair`) compiles as
/// `<namespace>__Hair` (`materialStageIn`), every stage of it and the
/// source the bundle carries renamed to match, so the plugin's lighting
/// model (`acme_hair.Hair`) finds it. A name in another plugin's namespace
/// is refused. Null compiles the name as written: the engine's own
/// materials, and an application's.
ShaderBundle compileMaterial(
  String text, {
  required String source,
  required ShaderSet engine,
  required MaterialCompilers compilers,
  required Directory scratch,
  String? namespace,
}) {
  final MaterialProgram program;
  // [text], in the plugin's namespace: what every stage is emitted from
  // and the bundle's material section carries.
  final String named;
  try {
    final parsed = parseMaterial(text);
    final stage = namespace == null
        ? parsed.name
        : materialStageIn(namespace, parsed.name);
    if (stage == null) {
      throw MaterialBuildException(
        'the material "${parsed.name}" is named in another plugin\'s '
        'namespace; a plugin of "$namespace" writes the bare name, which '
        'compiles as "${namespace}__<Name>"',
        source: source,
      );
    }
    named = stage == parsed.name ? text : renameMaterialSource(text, stage);
    program = stage == parsed.name ? parsed : parseMaterial(named);
  } on MaterialSyntaxException catch (error) {
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
  if (program.kind == MaterialStageKind.compute) {
    // Lowered to the kernel language and carried in the kernel section,
    // which WebGPU, the wgpu sidecar and the software backend load as it
    // is. Impeller and WebGL2 have no compute: there the engine refuses the
    // stage naming `DeviceFeature.compute`, and the texture is baked on the
    // CPU at load (`MaterialComputeKernel.bake`).
    try {
      return kernelBundle(name, <ComputeKernel>[
        lowerMaterialCompute(program).kernel,
      ]);
    } on MaterialSyntaxException catch (error) {
      throw MaterialBuildException(error.message, source: source);
    }
  }
  final specialised = specializeMaterial(program, MaterialVariant(name));

  // The stages the source becomes: the fragment stage under the material's
  // name, and with a `vertex` block its vertex stages — the plain and the
  // skinned from version 2, the instanced and the lightmapped from 3.
  final stages = <_Stage>[
    (name: name, fragment: true, glsl: emitMaterialFragment(specialised)),
    for (final MapEntry(key: stage, value: glsl) in emitMaterialVertexStages(
      specialised,
    ).entries)
      (name: stage, fragment: false, glsl: glsl),
  ];

  Never refused(String what, String message) =>
      throw MaterialBuildException('$what: $message', source: source);

  final generated = <String, File>{
    for (final stage in stages)
      stage.name:
          File(
              '${scratch.path}/${stage.name}.${stage.fragment ? 'frag' : 'vert'}',
            )
            ..parent.createSync(recursive: true)
            ..writeAsStringSync(stage.glsl),
  };

  final impeller = _impeller(
    name,
    stages,
    generated,
    engine,
    compilers,
    refused,
  );

  final webglVertex = <String, String>{};
  final webglFragment = <String, String>{};
  final resolved = <String, String>{};
  for (final stage in stages) {
    try {
      (stage.fragment
          ? webglFragment
          : webglVertex)[stage.name] = translateGlsl(
        stage.glsl,
        engine.sources,
        from: source,
        fragment: stage.fragment,
      );
      resolved[stage.name] = resolveIncludes(
        stage.glsl,
        engine.sources,
        from: source,
      );
    } on GlslTranslateException catch (error) {
      refused('the WebGL2 translation of ${stage.name}', error.message);
    }
  }
  // The budget, counted from the GLSL every backend's path has: before,
  // only the WebGPU section counted, and only where its compilers were
  // installed, so a stage over WebGL2's sixteen units shipped and failed to
  // link on a phone's browser. Mutation: skip this and
  // `material_budget_test.dart`'s stage of seventeen textures builds.
  for (final MapEntry(key: stage, value: glsl) in resolved.entries) {
    if (MaterialStageBudget.problemOfGlsl(stage, glsl) case final problem?) {
      refused('the binding budget', problem);
    }
  }

  final ByteData webgl;
  try {
    webgl = encodeWebGlSection(vertex: webglVertex, fragment: webglFragment);
  } on StageAgreementException catch (error) {
    refused('the WebGL2 section', error.message);
  }

  // D21: the material's own blocks and textures, numbered after the
  // engine's on WebGPU in the order its slot table lists them.
  final table = MaterialSlotTable.of(program);
  final webgpu = switch (compilers.wgsl) {
    null => null,
    final compile => _webgpu(
      stages,
      source,
      resolved,
      engine,
      compile,
      generated,
      refused,
      ownBindings: <String>[
        for (final block in table.blocks) block.name,
        for (final texture in table.textures) texture.binding,
      ],
    ),
  };

  final sections = <String, ByteData>{
    ShaderBundle.impellerSection: impeller,
    ShaderBundle.webglSection: webgl,
    ShaderBundle.webgpuSection: ?webgpu?.section,
    // The source itself, for the backend that compiles nothing and for a
    // runtime that builds the material's lighting model from it — `P8`.
    // Under every stage's name, so the software backend can answer each.
    ShaderBundle.materialSection: encodeMaterialSection(<String, String>{
      for (final stage in stages) stage.name: named,
    }),
  };

  // D26: every backend the registry holds a compiler for, after the three
  // above, so its section is the one the bundle carries.
  if (compilers.registry case final registry?) {
    final request = MaterialCompileRequest(
      name: name,
      from: source,
      source: named,
      stages: <MaterialStageSource>[
        for (final stage in stages)
          MaterialStageSource(
            name: stage.name,
            fragment: stage.fragment,
            glsl: stage.glsl,
          ),
      ],
      engineSources: engine.sources,
      options: <String, Object?>{
        // What WebGPU's compiler packs: the stages this build wrote as WGSL.
        MaterialCompileRequest.webGpuStagesOption: ?webgpu?.stages,
      },
    );
    for (final backend in registry.backends) {
      final compiler = registry.forBackend(backend)!;
      // No glslang or naga, so no WGSL for WebGPU's compiler to pack: the
      // bundle goes without the section, as it does with no registry.
      if (compiler.bundleSection == ShaderBundle.webgpuSection &&
          webgpu == null) {
        continue;
      }
      try {
        sections[compiler.bundleSection] = compiler.compile(request).section;
      } on MaterialCompileException catch (error) {
        // The section of a compiler whose section the build writes with a
        // tool of its own stays as written: Impeller's refuses because
        // `impellerc`, which it names, ran above. Any other refusal is the
        // build's failure, whatever this build wrote under the section.
        if (compiler.isSectionWrittenByBuild &&
            sections.containsKey(compiler.bundleSection)) {
          continue;
        }
        refused('the $backend compiler', error.message);
      } on StageAgreementException catch (error) {
        refused('the $backend compiler', error.message);
      }
    }
  }

  // Nothing went wrong, so nothing needs opening.
  for (final file in generated.values) {
    file.deleteSync();
  }

  return ShaderBundle(
    name: name,
    sdk: compilers.sdk,
    stages: <ShaderBundleStage>[
      for (final stage in stages)
        ShaderBundleStage(stage.name, fragment: stage.fragment),
    ],
    sections: sections,
  );
}

/// One stage a source becomes.
typedef _Stage = ({String name, bool fragment, String glsl});

ByteData _impeller(
  String name,
  List<_Stage> stages,
  Map<String, File> generated,
  ShaderSet engine,
  MaterialCompilers compilers,
  Never Function(String, String) refused,
) {
  final directory = generated.values.first.parent;
  final out = File('${directory.path}/$name.shaderbundle');
  final ProcessResult result;
  try {
    result = Process.runSync(compilers.impellerc, <String>[
      '--shader-bundle=${jsonEncode(<String, Object>{
        for (final stage in stages) stage.name: <String, String>{'type': stage.fragment ? 'fragment' : 'vertex', 'file': generated[stage.name]!.path},
      })}',
      '--sl=${out.path}',
      // The tree the other two sections are translated against, read off
      // the set rather than found again, so the three cannot disagree.
      '--include=${engine.root}',
      for (final include in compilers.impellerIncludes) '--include=$include',
    ], workingDirectory: directory.path);
  } on ProcessException catch (error) {
    refused(
      'impellerc',
      'could not run ${compilers.impellerc}: ${error.message}',
    );
  }
  if (result.exitCode != 0 || !out.existsSync()) {
    refused(
      'impellerc',
      'refused the GLSL generated from it, kept at '
          '${generated.values.map((f) => f.path).join(', ')} '
          '(exit ${result.exitCode}):\n${result.stdout}${result.stderr}',
    );
  }
  final bytes = out.readAsBytesSync();
  out.deleteSync();
  return bytes.buffer.asByteData();
}

/// The WebGPU section, and the stages it packs by name.
({ByteData section, Map<String, PackedStage> stages}) _webgpu(
  List<_Stage> stages,
  String source,
  Map<String, String> resolved,
  ShaderSet engine,
  WgslStageCompiler compile,
  Map<String, File> generated,
  Never Function(String, String) refused, {
  required List<String> ownBindings,
}) {
  var current = stages.first.name;
  try {
    // Every stage of the source numbered together, and held to the
    // engine's numbering, so a vertex stage of the material's and the
    // engine's own fragment stages meet at the same locations.
    final locations = bundleVaryingLocations(engine, <BundleStageSource>[
      for (final stage in stages)
        (
          file: '$source#${stage.name}',
          fragment: stage.fragment,
          resolved: resolved[stage.name]!,
        ),
    ]);
    final vertex = <String, PackedStage>{};
    final fragment = <String, PackedStage>{};
    for (final stage in stages) {
      current = stage.name;
      final prepared = prepareStage(
        resolved[stage.name]!,
        from: source,
        fragment: stage.fragment,
        varyingLocations: locations,
        ownBindings: ownBindings,
      );
      final compiled = compile(
        prepared,
        name: stage.name,
        fragment: stage.fragment,
      );
      checkStd140Offsets(stage.name, prepared, compiled.offsets);
      (stage.fragment ? fragment : vertex)[stage.name] = (
        wgsl: compiled.wgsl,
        prepared: prepared,
      );
    }
    final document = wgslSectionDocument(vertex: vertex, fragment: fragment);
    return (
      section: Uint8List.fromList(utf8.encode(document)).buffer.asByteData(),
      stages: <String, PackedStage>{...vertex, ...fragment},
    );
  } on StageAgreementException catch (error) {
    refused('the WebGPU section', error.message);
  } on WgslPrepareException catch (error) {
    refused('the WebGPU preparation of $current', error.message);
  } on WgslCompileException catch (error) {
    refused(
      'the WebGPU compile of $current',
      '${error.message}\n(the GLSL it was generated from is kept at '
          '${generated[current]?.path})',
    );
  } on WgslSectionException catch (error) {
    refused('the WebGPU section', error.message);
  }
}
