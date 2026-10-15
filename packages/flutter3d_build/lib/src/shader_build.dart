/// D15 and D19: the engine's shader stages a project needs, and every
/// installed plugin's materials, compiled into the project's own bundles for
/// the SDK the build runs on.
///
/// **One bundle for everybody was 8.5 MB in every binary**, two thirds of it
/// lighting models most games never draw with. This step writes
/// [EngineBundleStamp.projectAsset] with the stages the project's needs
/// bring and nothing else: [ShaderStageNeed.base], always; what the
/// manifest's `shaders:` lists, for what its code chooses; the lighting the
/// models it converted name; impostors when a rule bakes them; what each
/// installed plugin's pubspec declares. `shaders: full`, or `fullShaders:
/// true` among the hook's user defines, writes every stage. A stage left out
/// and asked for at run time is a `MissingShaderStageException` that names
/// the need, so what to add is never a guess.
///
/// **Compiled here, with the application's own `impellerc`**, so the bundle
/// is for the SDK that builds the application (amendment 4 of the field
/// review): the header carries its Dart and the [EngineBundleStamp] its
/// engine revision, and the bundle written before stays beside it as
/// [EngineBundleStamp.previousProjectAsset] for an application hot-reloading
/// across the rebuild. Anything older is removed.
///
/// **Every registered backend's compiler too** (D26). A backend from
/// outside the engine registers its `MaterialCompiler` in the
/// [MaterialCompilerRegistry] a build is handed, and the build asks it for
/// its section of the engine's bundle and of every plugin material's, as it
/// asks `impellerc`, the WebGL2 translator and naga for the engine's three.
/// A project whose only GPU backend is such a one gets its bundle.
///
/// **Found among the project's dependencies.** A backend package names its
/// compiler under `flutter3d_backend:` in its pubspec ([backendMarkerKey]);
/// discovery reads it ([PluginDiscovery.backendCompilers]) and this runs it
/// as a process ([ProcessMaterialCompiler]), so the build hook, `flutter3d
/// shaders` and the project's materials compile for every backend the
/// project depends on with nothing registered by hand. A registry handed in
/// is used instead.
///
/// **A plugin's materials too** (D19). A package that marks plugins and keeps
/// `.f3dmat` sources under its own `assets_src/` has each compiled into
/// [EngineBundleStamp.projectMaterialAsset], so a plugin's material reaches
/// Impeller for this SDK whatever SDK the plugin's author built with. A
/// bundle the plugin ships itself stays a documented option; the device
/// refuses it by name when its SDK is another.
///
/// **In the plugin's namespace.** A package from outside the engine writes
/// `material Hair`, and its material compiles as `<package>__Hair`, the
/// stage of its lighting model `<package>.Hair` (`materialStageIn`): the
/// namespace comes from the package shipping the source, never from the
/// source. A shader need a package or the manifest names after a plugin
/// (`acme.hair`) is the stage `acme__hair` one of those materials compiled
/// to, and a need no installed package compiles is refused, naming who
/// declared it.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter3d_build_hooks/flutter3d_build_hooks.dart';
import 'package:flutter3d_core/flutter3d_core.dart' show F3dDocument;
import 'package:flutter3d_hardware/shader_bundle.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show PluginManifest;
import 'package:flutter3d_shaders/backend.dart'
    show
        MaterialCompileException,
        MaterialCompileRequest,
        MaterialCompiler,
        MaterialCompilerRegistry,
        MaterialStageSource;
import 'package:flutter3d_shaders/compile.dart';
import 'package:flutter3d_shaders/flutter3d_shaders.dart'
    show EngineBundleStamp, ShaderStageNeed;

import 'backend_compilers.dart';
import 'layout.dart';
import 'plugin_discovery.dart';

/// The packages whose presence means the application loads the engine's
/// bundle: the engine's GPU backends. A backend from outside is known by the
/// compiler it registers instead.
const Set<String> _backendPackages = <String>{
  'flutter3d_impeller',
  'flutter3d_webgl',
  'flutter3d_webgpu',
};

/// The sections the engine writes itself, with tools of its own or none at
/// all: a registered compiler for one of them is not asked here. The stamp
/// among them, which holds the revision a device checks the bundle by.
const Set<String> _engineSections = <String>{
  EngineBundleStamp.section,
  ShaderBundle.impellerSection,
  ShaderBundle.webglSection,
  ShaderBundle.webgpuSection,
  ShaderBundle.materialSection,
  ShaderBundle.kernelSection,
};

/// The compilers [registry] holds for backends outside the engine, by
/// backend id in order: each writes a section of its own.
List<MaterialCompiler> _outsideCompilers(MaterialCompilerRegistry? registry) =>
    <MaterialCompiler>[
      for (final backend in registry?.backends.toList() ?? const <String>[])
        if (registry!.forBackend(backend) case final compiler?
            when !_engineSections.contains(compiler.bundleSection))
          compiler,
    ]..sort((a, b) => a.backend.compareTo(b.backend));

/// What one call to [runShaderBuild] did.
final class ShaderBuildReport {
  const ShaderBuildReport({
    required this.ran,
    this.stages = const <String>[],
    this.totalStages = 0,
    this.bytes = 0,
    this.written = false,
    this.needs = const <String>[],
    this.full = false,
    this.materials = const <String>[],
    this.dependencies = const <String>[],
  });

  /// Whether the application loads the engine's bundle at all: false for a
  /// project with no GPU backend, neither one of the engine's among its
  /// dependencies nor one from outside with a compiler registered, which
  /// this step leaves alone.
  final bool ran;

  /// The stages the project's engine bundle holds, in the manifest's order.
  final List<String> stages;

  /// How many the engine has.
  final int totalStages;

  /// The engine bundle's size on disk.
  final int bytes;

  /// Whether this run wrote it, rather than finding it current.
  final bool written;

  /// The needs it was written for, by name, the base aside.
  final List<String> needs;

  /// Whether it holds every stage.
  final bool full;

  /// The plugin materials compiled into the project, by stage name.
  final List<String> materials;

  /// The files the bundles were made from, for the hook to declare.
  final List<String> dependencies;

  /// The line a build log prints.
  String get summary => !ran
      ? 'no GPU backend among the dependencies, so no shader bundle'
      : 'shader bundle ${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB, '
            '${stages.length} of $totalStages stages'
            '${full
                ? ' (every one)'
                : needs.isEmpty
                ? ''
                : ' for ${needs.join(', ')}'}'
            '${materials.isEmpty ? '' : ', ${materials.length} plugin material${materials.length == 1 ? '' : 's'}'}';
}

/// Which of the engine's backends' sections a build writes: Impeller's for a
/// native target, the web's two for a browser, all three when the build
/// cannot tell. A registered backend from outside gets its section for
/// every target.
///
/// An open set like every other: a minor may add a target.
final class ShaderBuildTarget {
  const ShaderBuildTarget._(
    this.name, {
    required this.impeller,
    required this.webGl,
    required this.webGpu,
  });

  /// A native target: `impellerc`'s output.
  static const ShaderBuildTarget native = ShaderBuildTarget._(
    'native',
    impeller: true,
    webGl: false,
    webGpu: false,
  );

  /// A browser: the WebGL2 sources and the WebGPU stages.
  static const ShaderBuildTarget web = ShaderBuildTarget._(
    'web',
    impeller: false,
    webGl: true,
    webGpu: true,
  );

  /// A build that names no target.
  static const ShaderBuildTarget any = ShaderBuildTarget._(
    'any',
    impeller: true,
    webGl: true,
    webGpu: true,
  );

  /// The target's name, as a log says it.
  final String name;

  /// Whether the bundle carries `impellerc`'s section.
  final bool impeller;

  /// Whether the bundle carries the WebGL2 section.
  final bool webGl;

  /// Whether the bundle carries the WebGPU section: the stages in WGSL with
  /// their reflection, made by glslang and naga. A machine without either
  /// writes the bundle without it, and the WebGPU device falls back to the
  /// stages it was compiled with.
  final bool webGpu;

  @override
  String toString() => 'ShaderBuildTarget.$name';
}

/// The needs [projectRoot] declares, the base aside: its manifest's, its
/// models', its rules', and [plugins]'.
List<String> declaredShaderNeeds(
  Directory projectRoot, {
  PluginDiscovery? plugins,
}) {
  final layout = AssetLayout(projectRoot: projectRoot);
  final manifest = layout.manifest;
  return <String>{
    ...manifest.shaders.needs,
    // A rule that bakes impostors draws them.
    if (manifest.rules.any((rule) => rule.impostor))
      ShaderStageNeed.impostor.name,
    ..._modelNeeds(layout),
    for (final package in plugins?.packages ?? const <PluginPackage>[])
      ...package.shaderNeeds,
  }.toList()..sort();
}

/// The lighting the converted models name, as needs: what a material
/// declares by the model it lights. A file this build cannot read declares
/// nothing; the converter that wrote it has said why.
Iterable<String> _modelNeeds(AssetLayout layout) sync* {
  final generated = layout.generatedDir;
  if (!generated.existsSync()) return;
  for (final file in generated.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.f3d')) continue;
    final F3dDocument document;
    try {
      document = F3dDocument.parse(file.readAsBytesSync());
    } on Exception {
      continue;
    }
    for (final material in document.materials) {
      final model = material.lightingModel;
      if (model == null) continue;
      for (final stage in <String?>[model.shaderName, model.vertexShaderName]) {
        if (stage == null) continue;
        final need = ShaderStageNeed.bringing(stage);
        if (need != null && need != ShaderStageNeed.base) yield need.name;
      }
    }
  }
}

/// Writes the project's engine bundle and its plugins' material bundles
/// under `flutter3d_generated/shaders/`, when a GPU backend is among
/// [plugins]' dependencies or [registry] holds a compiler for one from
/// outside the engine.
///
/// [full] writes every stage whatever is declared, as `--full-shaders` asks;
/// the manifest's `shaders: full` does the same. [compilers] defaults to the
/// Flutter SDK running the build, [engine] to the `flutter3d_shaders` the
/// project resolves; both are looked up only when there is something to
/// write. [engineRevision] defaults to the SDK's own.
///
/// [registry] is the backends' compilers (D26): [compilers]' own when it
/// has one, and otherwise the compilers [plugins] found among the project's
/// dependencies ([discoveredCompilers]). Each compiler of a backend outside
/// the engine is handed the
/// engine's stages as GLSL, with the engine's sources to resolve their
/// includes and an empty `.f3dmat` source, and writes its section of the
/// engine's bundle; and it is asked for its section of every plugin
/// material, as the engine's are.
///
/// Throws [MaterialBuildException] when a stage or a material does not
/// compile, or a registered compiler refuses one, having replaced nothing.
ShaderBuildReport runShaderBuild(
  Directory projectRoot, {
  required PluginDiscovery plugins,
  IOSink? log,
  bool full = false,
  ShaderBuildTarget target = ShaderBuildTarget.any,
  MaterialCompilers? compilers,
  ShaderSet? engine,
  String? engineRevision,
  MaterialCompilerRegistry? registry,
}) {
  final compilerRegistry =
      registry ?? compilers?.registry ?? discoveredCompilers(plugins);
  final outside = _outsideCompilers(compilerRegistry);
  // The engine's own sections only for an application that has one of the
  // engine's GPU backends; one whose only backend is from outside gets that
  // backend's section and nothing it cannot load.
  final engineBackends = plugins.dependencies.any(_backendPackages.contains);
  if (!engineBackends && outside.isEmpty) {
    return const ShaderBuildReport(ran: false);
  }
  final impeller = engineBackends && target.impeller;
  final webGl = engineBackends && target.webGl;
  final sink = log ?? stdout;
  final layout = AssetLayout(projectRoot: projectRoot);
  final ShaderSet shaders;
  try {
    shaders = engine ?? loadShaders(from: projectRoot.path);
  } on StateError catch (error) {
    throw MaterialBuildException(
      'the engine\'s shaders are not reachable from ${projectRoot.path}: '
      '${error.message}',
      source: '',
    );
  }
  final tools = switch (compilers) {
    null => MaterialCompilers.locate(registry: compilerRegistry),
    final given when given.registry == compilerRegistry => given,
    final given => MaterialCompilers(
      impellerc: given.impellerc,
      sdk: given.sdk,
      impellerIncludes: given.impellerIncludes,
      wgsl: given.wgsl,
      registry: compilerRegistry,
    ),
  };
  final revision =
      engineRevision ??
      engineRevisionAt(flutterSdkRootFrom(Platform.resolvedExecutable));

  final everything = full || layout.manifest.shaders.full;
  final needs = everything
      ? const <String>[]
      : declaredShaderNeeds(projectRoot, plugins: plugins);
  final wanted = everything
      ? shaders.stages.keys.toSet()
      : ShaderStageNeed.stagesFor(<ShaderStageNeed>[
          for (final name in needs) ?ShaderStageNeed.byName(name),
        ]).toSet();
  final stages = <String>[
    for (final name in shaders.stages.keys)
      if (wanted.contains(name)) name,
  ];

  final directory = layout.reservedShaderDir..createSync(recursive: true);
  final out = File('${directory.path}/flutter3d.f3dshaders');
  final previous = File('${directory.path}/flutter3d.previous.f3dshaders');
  final cachePath = '${directory.path}/.flutter3d_shaders.json';
  final cache = _readCache(cachePath);

  final engineHash = _hashOf(shaders.sources);
  final webGpu = engineBackends && target.webGpu;
  final wgsl = webGpu ? tools.wgsl : null;
  if (webGpu && wgsl == null) {
    sink.writeln(
      'flutter3d_build: no glslangValidator or naga on PATH, so the shader '
      'bundle carries no WebGPU section; a WebGPU device draws with the '
      'stages it was compiled with',
    );
  }
  final stamp = <String>[
    engineHash,
    tools.sdk,
    revision,
    'f3sb${ShaderBundle.formatVersion}',
    if (impeller) 'impeller',
    if (webGl) 'webgl',
    // The WGSL document's own version, which `compile.dart` names.
    if (wgsl != null) 'webgpu$sectionVersion',
    for (final compiler in outside)
      '${compiler.backend}:${compiler.bundleSection}',
    ...stages,
  ].join(' ');

  var written = false;
  if (cache['engine'] != stamp || !out.existsSync()) {
    final bundle =
        EngineBundleStamp(
          dart: tools.sdk,
          engine: revision,
          needs: needs,
          full: everything,
          stages: stages.length,
        ).bundle(
          stages: <ShaderBundleStage>[
            for (final name in stages)
              ShaderBundleStage(name, fragment: shaders.stages[name]!.fragment),
          ],
          sections: <String, ByteData>{
            if (impeller)
              ShaderBundle.impellerSection: _impeller(
                stages,
                shaders,
                tools,
                Directory(
                  '${projectRoot.path}/.dart_tool/flutter3d_build/shaders',
                ),
              ),
            if (webGl) ShaderBundle.webglSection: _webgl(stages, shaders),
            if (wgsl != null)
              ShaderBundle.webgpuSection: _webgpu(stages, shaders, wgsl),
            for (final compiler in outside)
              compiler.bundleSection: _outside(compiler, stages, shaders),
          },
        );
    final bytes = bundle.encode();
    // One previous bundle stays, for an application that reloads across the
    // rebuild; anything older goes.
    if (out.existsSync()) {
      if (previous.existsSync()) previous.deleteSync();
      out.renameSync(previous.path);
    }
    out.writeAsBytesSync(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    written = true;
  }
  for (final stale in directory.listSync().whereType<File>()) {
    final name = stale.path.split('/').last;
    if (name.startsWith('flutter3d.') &&
        name.endsWith('.f3dshaders') &&
        stale.path != out.path &&
        stale.path != previous.path) {
      stale.deleteSync();
    }
  }

  final materials = _pluginMaterials(
    plugins,
    directory,
    shaders,
    tools,
    cache,
    projectRoot,
    sink,
  );
  _resolvePluginNeeds(
    plugins,
    layout.manifest.shaders.needs,
    materials.names,
    projectRoot,
  );

  _writeCache(cachePath, <String, Object?>{
    'engine': stamp,
    'materials': materials.cache,
  });

  final report = ShaderBuildReport(
    ran: true,
    stages: stages,
    totalStages: shaders.stages.length,
    bytes: out.lengthSync(),
    written: written,
    needs: needs,
    full: everything,
    materials: materials.names,
    dependencies: <String>[
      for (final file in shaders.sources.keys) '${shaders.root}/$file',
      '${shaders.root}/flutter3d.shaderbundle.json',
      ...materials.sources,
    ],
  );
  sink.writeln('flutter3d_build: ${report.summary}');
  return report;
}

/// [compiler]'s section of the engine's bundle of [stages]: the stages as
/// the engine's GLSL, their includes left for the engine's sources to
/// resolve, as a material's stages are handed to it.
ByteData _outside(
  MaterialCompiler compiler,
  List<String> stages,
  ShaderSet shaders,
) {
  try {
    return compiler
        .compile(
          MaterialCompileRequest(
            name: 'flutter3d',
            from: '${shaders.root}/flutter3d.shaderbundle.json',
            source: '',
            stages: <MaterialStageSource>[
              for (final name in stages)
                MaterialStageSource(
                  name: name,
                  fragment: shaders.stages[name]!.fragment,
                  glsl: shaders.sources[shaders.stages[name]!.file]!,
                ),
            ],
            engineSources: shaders.sources,
          ),
        )
        .section;
  } on MaterialCompileException catch (error) {
    throw MaterialBuildException(
      'the ${compiler.backend} compiler refused the engine\'s stages: '
      '${error.message}',
      source: '${shaders.root}/flutter3d.shaderbundle.json',
    );
  }
}

/// `impellerc`'s bundle of [stages].
ByteData _impeller(
  List<String> stages,
  ShaderSet shaders,
  MaterialCompilers tools,
  Directory scratch,
) {
  scratch.createSync(recursive: true);
  final out = File('${scratch.path}/flutter3d.shaderbundle');
  final manifest = <String, Object>{
    for (final name in stages)
      name: <String, String>{
        'type': shaders.stages[name]!.fragment ? 'fragment' : 'vertex',
        'file': '${shaders.root}/${shaders.stages[name]!.file}',
      },
  };
  final ProcessResult result;
  try {
    result = Process.runSync(tools.impellerc, <String>[
      '--shader-bundle=${jsonEncode(manifest)}',
      '--sl=${out.path}',
      '--include=${shaders.root}',
      for (final include in tools.impellerIncludes) '--include=$include',
    ], workingDirectory: shaders.root);
  } on ProcessException catch (error) {
    throw MaterialBuildException(
      'could not run ${tools.impellerc}: ${error.message}',
      source: '',
    );
  }
  if (result.exitCode != 0 || !out.existsSync()) {
    throw MaterialBuildException(
      'impellerc refused the engine\'s stages (exit ${result.exitCode}):\n'
      '${result.stdout}${result.stderr}',
      source: '${shaders.root}/flutter3d.shaderbundle.json',
    );
  }
  final bytes = out.readAsBytesSync();
  out.deleteSync();
  return bytes.buffer.asByteData();
}

/// The WebGL2 sources of [stages], translated as the WebGL backend's own
/// table is.
ByteData _webgl(List<String> stages, ShaderSet shaders) {
  final vertex = <String, String>{};
  final fragment = <String, String>{};
  for (final name in stages) {
    final stage = shaders.stages[name]!;
    try {
      (stage.fragment ? fragment : vertex)[name] = translateGlsl(
        shaders.sources[stage.file]!,
        shaders.sources,
        from: stage.file,
        fragment: stage.fragment,
      );
    } on GlslTranslateException catch (error) {
      throw MaterialBuildException(error.message, source: stage.file);
    }
  }
  try {
    return encodeWebGlSection(vertex: vertex, fragment: fragment);
  } on StageAgreementException catch (error) {
    throw MaterialBuildException(error.message, source: '');
  }
}

/// The WebGPU section of [stages]: each in WGSL with the reflection a
/// `GPUShaderModule` cannot be asked for, made as `flutter3d_webgpu`'s own
/// table is.
///
/// **The varyings are numbered over the engine's whole manifest**, not over
/// the stages this project keeps, because that is how the table the device
/// was compiled with numbers them: a stage of this section is paired with
/// whichever of the others the frame asks for, and WebGPU joins two modules
/// by `@location` alone. So a stage here is the table's stage, byte for byte
/// on the same glslang and naga, and a project's section is the table cut to
/// what the project draws.
ByteData _webgpu(
  List<String> stages,
  ShaderSet shaders,
  WgslStageCompiler compile,
) {
  var current = '';
  try {
    final locations = bundleVaryingLocations(
      shaders,
      const <BundleStageSource>[],
    );
    final vertex = <String, PackedStage>{};
    final fragment = <String, PackedStage>{};
    for (final name in stages) {
      current = name;
      final stage = shaders.stages[name]!;
      final prepared = prepareStage(
        resolveIncludes(
          shaders.sources[stage.file]!,
          shaders.sources,
          from: stage.file,
        ),
        from: stage.file,
        fragment: stage.fragment,
        varyingLocations: locations,
      );
      final compiled = compile(prepared, name: name, fragment: stage.fragment);
      checkStd140Offsets(name, prepared, compiled.offsets);
      (stage.fragment ? fragment : vertex)[name] = (
        wgsl: compiled.wgsl,
        prepared: prepared,
      );
    }
    return Uint8List.fromList(
      utf8.encode(wgslSectionDocument(vertex: vertex, fragment: fragment)),
    ).buffer.asByteData();
  } on GlslTranslateException catch (error) {
    throw MaterialBuildException(error.message, source: current);
  } on WgslPrepareException catch (error) {
    throw MaterialBuildException(
      'the WebGPU preparation of $current: ${error.message}',
      source: current,
    );
  } on WgslCompileException catch (error) {
    throw MaterialBuildException(
      'the WebGPU compile of $current: ${error.message}',
      source: current,
    );
  } on WgslSectionException catch (error) {
    throw MaterialBuildException(error.message, source: current);
  }
}

/// Every installed plugin package's `assets_src/**/*.f3dmat`, compiled into
/// [directory] under the material's own stage name: what was compiled, the
/// cache entries, and the sources read.
({List<String> names, Map<String, String> cache, List<String> sources})
_pluginMaterials(
  PluginDiscovery plugins,
  Directory directory,
  ShaderSet shaders,
  MaterialCompilers tools,
  Map<String, Object?> previous,
  Directory projectRoot,
  IOSink sink,
) {
  final before = switch (previous['materials']) {
    final Map<String, Object?> map => <String, String>{
      for (final MapEntry(:key, :value) in map.entries)
        if (value is String) key: value,
    },
    _ => const <String, String>{},
  };
  final stamp =
      '${_hashOf(shaders.sources)} ${tools.sdk} f3sb${ShaderBundle.formatVersion}';
  final next = <String, String>{};
  final names = <String>[];
  final sources = <String>[];
  for (final package in plugins.packages) {
    final root = Directory('${package.root}/assets_src');
    if (!root.existsSync()) continue;
    final files =
        root
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.f3dmat'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    // The plugin's namespace, from the package that ships the source: the
    // engine's own packages name their stages as the engine does.
    final namespace = PluginManifest.engineNamespaces.contains(package.name)
        ? null
        : package.name;
    for (final file in files) {
      final text = file.readAsStringSync();
      sources.add(file.path);
      final key =
          '${sha256.convert(utf8.encode(text))} $stamp ${namespace ?? ''}';
      final known = before.entries
          .where((entry) => entry.value == key)
          .map((entry) => entry.key)
          .firstOrNull;
      if (known != null &&
          File('${directory.path}/${known.split('/').last}').existsSync()) {
        next[known] = key;
        names.add(known.split('/').last.replaceAll('.f3dshaders', ''));
        continue;
      }
      final bundle = compileMaterial(
        text,
        source: file.path,
        engine: shaders,
        compilers: tools,
        scratch: Directory(
          '${projectRoot.path}/.dart_tool/flutter3d_build/plugin_materials',
        ),
        namespace: namespace,
      );
      if (bundle.name == 'flutter3d' || bundle.name == 'flutter3d.previous') {
        throw MaterialBuildException(
          '"${bundle.name}" is the name of the engine\'s own bundle; a '
          'material needs another',
          source: file.path,
        );
      }
      final target = EngineBundleStamp.projectMaterialAsset(bundle.name);
      final bytes = bundle.encode();
      File('${projectRoot.path}/$target').writeAsBytesSync(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      sink.writeln(
        'flutter3d_build: ${package.name}\'s "${bundle.name}" compiled into '
        '$target',
      );
      next[target] = key;
      names.add(bundle.name);
    }
  }
  // A material whose plugin is gone, or whose source is: `flutter3d_generated`
  // is bundled whole and would carry it.
  for (final stale in before.keys) {
    if (next.containsKey(stale)) continue;
    final file = File('${projectRoot.path}/$stale');
    if (file.existsSync()) file.deleteSync();
  }
  return (names: names, cache: next, sources: sources);
}

/// Resolves every shader need named after a plugin (`acme.hair`), that a
/// package of [plugins] declares under `flutter3d_plugins: shaders:` or the
/// project's [manifestNeeds] lists, to the plugin material compiled as its
/// stage (`acme__hair`, matched in any case, among [compiled]); a need none
/// of them compiled is a [MaterialBuildException] naming who declared it
/// and what the installed plugins do compile.
///
/// **Refused rather than dropped.** A need the engine does not know used to
/// bring nothing, and a stage left out was then missing at run time with no
/// plugin to name; now the build says which package asked for what.
void _resolvePluginNeeds(
  PluginDiscovery plugins,
  List<String> manifestNeeds,
  List<String> compiled,
  Directory projectRoot,
) {
  final stages = <String>{for (final name in compiled) name.toLowerCase()};
  final declared = <(String, String, String)>[
    for (final package in plugins.packages)
      for (final need in package.shaderNeeds)
        (need, package.name, '${package.root}/pubspec.yaml'),
    for (final need in manifestNeeds)
      (need, 'the project', '${projectRoot.path}/flutter3d_assets.yaml'),
  ];
  for (final (need, owner, source) in declared) {
    if (!need.contains('.') || ShaderStageNeed.byName(need) != null) continue;
    final stage = need.replaceAll('.', '__');
    if (stages.contains(stage.toLowerCase())) continue;
    throw MaterialBuildException(
      '$owner needs the shader stages "$need", the plugin material compiled '
      'as "$stage", and no installed plugin package compiles one'
      '${compiled.isEmpty ? '' : ' (they compile ${compiled.join(', ')})'}: '
      'add the package that ships it, or take the need out',
      source: source,
    );
  }
}

String _hashOf(Map<String, String> sources) => sha256
    .convert(
      utf8.encode(
        (sources.keys.toList()..sort())
            .map((key) => '$key\n${sources[key]}')
            .join('\n'),
      ),
    )
    .toString();

/// The shader cache's envelope. A cache written by another layout reads as
/// empty, and everything is compiled once more.
const String _cacheFormat = 'f3d.shaderCache';
const int _cacheLayout = 1;

Map<String, Object?> _readCache(String path) {
  final file = File(path);
  if (!file.existsSync()) return const <String, Object?>{};
  try {
    return switch (jsonDecode(file.readAsStringSync())) {
      {
        'format': _cacheFormat,
        'version': _cacheLayout,
        'entries': final Map<String, Object?> entries,
      } =>
        entries,
      _ => const <String, Object?>{},
    };
  } on FormatException {
    return const <String, Object?>{};
  }
}

void _writeCache(String path, Map<String, Object?> entries) {
  File(path).writeAsStringSync(
    jsonEncode(<String, Object?>{
      'format': _cacheFormat,
      'version': _cacheLayout,
      'requires': const <String>[],
      'generator': 'flutter3d',
      'entries': entries,
    }),
  );
}
