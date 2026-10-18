/// D15 and D19: the project's engine bundle holds the stages its needs
/// bring, and its plugins' materials are compiled into the project.
///
///     dart test test/shader_build_test.dart
///
/// **`impellerc` is a stub**, as in `material_build_test.dart`: it records
/// the manifest it was handed and writes known bytes, because what this
/// checks is which stages the build asks for and what it does with the
/// answer. The WebGL2 section is translated for real.
///
/// Mutation: drop `ShaderStageNeed.base` from `stagesFor`, and the bundle
/// loses the stages every renderer opens with.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter3d_backend_null/flutter3d_backend_null.dart';
import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:flutter3d_build_hooks/flutter3d_build_hooks.dart';
import 'package:flutter3d_hardware/shader_bundle.dart';
import 'package:flutter3d_shaders/backend.dart';
import 'package:flutter3d_shaders/compile.dart';
import 'package:flutter3d_shaders/flutter3d_shaders.dart';
import 'package:test/test.dart';

const String _impellerBytes = 'stub impellerc output';

const String _glow = '''
material AcmeGlow {
  param float strength = 1.0;
  fragment {
    return vec4(albedo * strength, alpha);
  }
}
''';

void main() {
  final engine = loadShaders();
  late Directory project;
  late _Log log;

  setUp(() {
    project = Directory.systemTemp.createTempSync('f3d_shaders_');
    File('${project.path}/pubspec.yaml').writeAsStringSync('name: game\n');
    log = _Log();
  });
  tearDown(() => project.deleteSync(recursive: true));

  /// A stub `impellerc` that writes [_impellerBytes] to `--sl=` and keeps the
  /// manifest it was handed beside it.
  MaterialCompilers stub() {
    final script = File('${project.path}/sdk/impellerc')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('''
#!/usr/bin/env bash
for arg in "\$@"; do
  case "\$arg" in
    --shader-bundle=*) printf '%s' "\${arg#--shader-bundle=}" > "\$(dirname "\$0")/manifest.json" ;;
    --sl=*) printf '%s' '$_impellerBytes' > "\${arg#--sl=}" ;;
  esac
done
''');
    expect(Process.runSync('chmod', <String>['+x', script.path]).exitCode, 0);
    return MaterialCompilers(impellerc: script.path, sdk: '3.13.0');
  }

  Map<String, Object?> asked() =>
      jsonDecode(File('${project.path}/sdk/manifest.json').readAsStringSync())
          as Map<String, Object?>;

  ShaderBundle bundle() => ShaderBundle.decode(
    File(
      '${project.path}/${EngineBundleStamp.projectAsset}',
    ).readAsBytesSync().buffer.asByteData(),
  );

  ShaderBuildReport build({
    PluginDiscovery plugins = const PluginDiscovery(
      plugins: <DiscoveredPlugin>[],
      readFiles: <String>[],
      dependencies: <String>{'flutter3d_impeller'},
    ),
    bool full = false,
    ShaderBuildTarget target = ShaderBuildTarget.any,
    WgslStageCompiler? wgsl,
    MaterialCompilerRegistry? registry,
  }) => runShaderBuild(
    project,
    plugins: plugins,
    log: log,
    full: full,
    target: target,
    compilers: switch (stub()) {
      final tools when wgsl != null => MaterialCompilers(
        impellerc: tools.impellerc,
        sdk: tools.sdk,
        wgsl: wgsl,
      ),
      final tools => tools,
    },
    engine: engine,
    engineRevision: 'abc123',
    registry: registry,
  );

  void manifest(String text) =>
      File('${project.path}/flutter3d_assets.yaml').writeAsStringSync(text);

  test('a project no GPU backend is a dependency of gets no bundle', () {
    final report = build(
      plugins: const PluginDiscovery(
        plugins: <DiscoveredPlugin>[],
        readFiles: <String>[],
        dependencies: <String>{'flutter3d_cpu'},
      ),
    );
    expect(report.ran, isFalse);
    expect(
      File('${project.path}/${EngineBundleStamp.projectAsset}').existsSync(),
      isFalse,
    );
  });

  test('a project that declares nothing carries the base alone', () {
    final report = build();
    expect(report.written, isTrue);
    expect(report.stages.toSet(), ShaderStageNeed.base.stages.toSet());
    expect(asked().keys.toSet(), ShaderStageNeed.base.stages.toSet());
    expect(asked().keys, isNot(contains('Toon')));
    expect(asked().keys, isNot(contains('PbrLayered')));

    final written = bundle();
    expect(written.name, 'flutter3d');
    expect(written.sdk, '3.13.0');
    expect(written.names.toSet(), report.stages.toSet());
    expect(
      utf8.decode(
        written.section(ShaderBundle.impellerSection)!.buffer.asUint8List(),
      ),
      _impellerBytes,
    );
    expect(written.section(ShaderBundle.webglSection), isNotNull);
    final stamp = EngineBundleStamp.decode(
      written.section(EngineBundleStamp.section),
    )!;
    expect(stamp.engine, 'abc123');
    expect(stamp.full, isFalse);
    expect(stamp.stages, report.stages.length);
    expect(log.text, contains('of ${engine.stages.length} stages'));
  });

  test('a native build carries Impeller\'s section and not the web\'s', () {
    build(target: ShaderBuildTarget.native);
    expect(bundle().sections.keys, <String>[
      ShaderBundle.impellerSection,
      EngineBundleStamp.section,
    ]);
  });

  Map<String, Object?> webGpuDocument() =>
      jsonDecode(
            utf8.decode(
              bundle()
                  .section(ShaderBundle.webgpuSection)!
                  .buffer
                  .asUint8List(),
            ),
          )
          as Map<String, Object?>;

  Set<String> webGpuStages() => <String>{
    ...(webGpuDocument()['vertex']! as Map<String, Object?>).keys,
    ...(webGpuDocument()['fragment']! as Map<String, Object?>).keys,
  };

  test('a web build carries the WebGPU section beside the WebGL2 one, with '
      'the stages the project keeps', () {
    // Mutation: leave `webGpu` off `ShaderBuildTarget.web`, and the section
    // is not written; hand `_webgpu` every stage of the engine, and the
    // section holds the stages the project left out.
    final report = build(target: ShaderBuildTarget.web, wgsl: _stubWgsl);
    expect(bundle().sections.keys, <String>[
      ShaderBundle.webglSection,
      ShaderBundle.webgpuSection,
      EngineBundleStamp.section,
    ]);
    expect(webGpuStages(), report.stages.toSet());
    final fragment = webGpuDocument()['fragment']! as Map<String, Object?>;
    expect(
      (fragment['PbrOpaque']! as Map<String, Object?>)['wgsl'],
      '// PbrOpaque',
    );
    expect(engine.stages['PbrOpaque']!.fragment, isTrue);
  });

  test('without glslang and naga a web build writes no WebGPU section, says '
      'so, and writes one once they are there', () {
    build(target: ShaderBuildTarget.web);
    expect(bundle().section(ShaderBundle.webgpuSection), isNull);
    expect(log.text, contains('no glslangValidator or naga'));

    final later = build(target: ShaderBuildTarget.web, wgsl: _stubWgsl);
    expect(later.written, isTrue, reason: 'the cache key names the section');
    expect(bundle().section(ShaderBundle.webgpuSection), isNotNull);
  });

  test('a native build asks no WGSL compiler', () {
    build(
      target: ShaderBuildTarget.native,
      wgsl: (stage, {required name, required fragment}) =>
          fail('$name was compiled to WGSL for a native build'),
    );
    expect(bundle().section(ShaderBundle.webgpuSection), isNull);
  });

  test('each WebGPU stage is the stage of the table the device was compiled '
      'with', () {
    // Mutation: number each stage's varyings on its own rather than over the
    // engine's manifest, and its `@location`s move away from the table's,
    // whose stages the frame pairs it with.
    manifest('shaders: [toon]\n');
    build(
      target: ShaderBuildTarget.web,
      wgsl: (stage, {required name, required fragment}) =>
          compileStage(stage.glsl, name: name, fragment: fragment),
    );
    final table = File(
      '../flutter3d_webgpu/lib/engine_shaders.dart',
    ).readAsStringSync();
    final document = webGpuDocument();
    for (final kind in const <String>['vertex', 'fragment']) {
      for (final MapEntry(key: name, value: stage)
          in (document[kind]! as Map<String, Object?>).entries) {
        final wgsl = (stage! as Map<String, Object?>)['wgsl']! as String;
        expect(table, contains("r'''\n$wgsl'''"), reason: name);
      }
    }
  }, skip: _noWgslCompilers());

  test('the manifest\'s needs bring their stages', () {
    manifest('shaders: [toon]\n');
    final report = build();
    expect(report.needs, <String>['toon']);
    expect(asked().keys, containsAll(<String>['Toon', 'ToonOpaque']));
    expect(asked().keys, isNot(contains('Lambert')));
  });

  test('full writes every stage, from the manifest or the flag', () {
    manifest('shaders: full\n');
    expect(build().stages, hasLength(engine.stages.length));
    manifest('rules: []\n');
    final report = build(full: true);
    expect(report.full, isTrue);
    expect(asked().keys, hasLength(engine.stages.length));
  });

  test('a rule that bakes impostors brings the impostor stages', () {
    manifest('rules:\n  - glob: "**/*.glb"\n    impostor: true\n');
    expect(build().needs, contains('impostor'));
    expect(asked().keys, contains('ImpostorVertex'));
  });

  test('a plugin\'s needs and materials come into the project', () {
    final plugin = Directory('${project.path}/acme')..createSync();
    File('${plugin.path}/assets_src/glow.f3dmat')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(_glow);
    final report = build(
      plugins: PluginDiscovery(
        plugins: const <DiscoveredPlugin>[],
        readFiles: const <String>[],
        dependencies: const <String>{'flutter3d_impeller', 'acme'},
        packages: <PluginPackage>[
          PluginPackage(
            name: 'acme',
            root: plugin.path,
            shaderNeeds: const <String>['pbrLayered'],
          ),
        ],
      ),
    );
    expect(report.needs, <String>['pbrLayered']);
    // The stub's last manifest is the material's, so the bundle is asked.
    expect(bundle().names, contains('PbrLayered'));
    // In the namespace of the package that ships it.
    expect(report.materials, <String>['acme__AcmeGlow']);
    final material = File(
      '${project.path}/${EngineBundleStamp.projectMaterialAsset('acme__AcmeGlow')}',
    );
    expect(material.existsSync(), isTrue);
    expect(
      ShaderBundle.decode(material.readAsBytesSync().buffer.asByteData()).sdk,
      '3.13.0',
    );
    expect(report.dependencies, contains(endsWith('glow.f3dmat')));

    // The plugin gone, its material goes with it.
    build();
    expect(material.existsSync(), isFalse);
  });

  group('a backend from outside', () {
    // The null backend's compiler writes the stage names it was handed, as
    // JSON, under its own section: what a build asked it for is readable.
    List<Object?> namesIn(ShaderBundle bundle) =>
        jsonDecode(
              utf8.decode(bundle.section(nullSection)!.buffer.asUint8List()),
            )
            as List<Object?>;

    test('is asked for its section when it is the only GPU backend', () {
      // Mutation: decide `ran` from the engine's backend packages alone, and
      // a project whose one GPU backend is from outside gets no bundle.
      final report = build(
        plugins: const PluginDiscovery(
          plugins: <DiscoveredPlugin>[],
          readFiles: <String>[],
          dependencies: <String>{'flutter3d_backend_null'},
        ),
        registry: MaterialCompilerRegistry(<MaterialCompiler>[
          const NullMaterialCompiler(),
        ]),
      );
      expect(report.ran, isTrue);
      final written = bundle();
      expect(namesIn(written).toSet(), report.stages.toSet());
      // The engine's own sections are for the engine's backends.
      expect(written.section(ShaderBundle.impellerSection), isNull);
      expect(written.section(ShaderBundle.webglSection), isNull);
    });

    test('writes its section beside the engine\'s, and a plugin\'s', () {
      final plugin = Directory('${project.path}/acme')..createSync();
      File('${plugin.path}/assets_src/glow.f3dmat')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(_glow);
      build(
        plugins: PluginDiscovery(
          plugins: const <DiscoveredPlugin>[],
          readFiles: const <String>[],
          dependencies: const <String>{'flutter3d_impeller', 'acme'},
          packages: <PluginPackage>[
            PluginPackage(name: 'acme', root: plugin.path),
          ],
        ),
        registry: MaterialCompilerRegistry(<MaterialCompiler>[
          const NullMaterialCompiler(),
        ]),
      );
      final written = bundle();
      expect(written.section(ShaderBundle.impellerSection), isNotNull);
      expect(namesIn(written), contains('MeshVertex'));

      final material = ShaderBundle.decode(
        File(
          '${project.path}/${EngineBundleStamp.projectMaterialAsset('acme__AcmeGlow')}',
        ).readAsBytesSync().buffer.asByteData(),
      );
      expect(namesIn(material), contains('acme__AcmeGlow'));
    });

    test(
      'is found among the dependencies and run as its package says',
      () async {
        // The null backend's own pubspec names `bin/material_compiler.dart`;
        // discovery reads it, and the build runs it against this test's
        // package config, which resolves the example.
        // Mutation: hand the build no compiler when none is registered, and
        // the project whose one GPU backend is the null one gets no bundle.
        final lib = await Isolate.resolvePackageUri(
          Uri.parse('package:flutter3d_backend_null/'),
        );
        final config = await Isolate.packageConfig;
        final root = Directory.fromUri(lib!).parent.path;
        final marker = backendCompilerOf(
          'flutter3d_backend_null',
          <Object?, Object?>{
            'flutter3d_backend': <Object?, Object?>{
              'backend': 'null',
              'section': 'null',
              'compiler': 'bin/material_compiler.dart',
            },
          },
          root: root,
          packageConfig: config!.toFilePath(),
        )!;
        final report = build(
          plugins: PluginDiscovery(
            plugins: const <DiscoveredPlugin>[],
            readFiles: const <String>[],
            dependencies: const <String>{'flutter3d_backend_null'},
            backendCompilers: <BackendCompilerPackage>[marker],
          ),
        );
        expect(report.ran, isTrue);
        expect(namesIn(bundle()).toSet(), report.stages.toSet());
        expect(
          () => backendCompilerOf(
            'half',
            <Object?, Object?>{
              'flutter3d_backend': <Object?, Object?>{'backend': 'half'},
            },
            root: root,
            packageConfig: config.toFilePath(),
          ),
          throwsA(isA<PluginDiscoveryException>()),
        );
      },
    );

    test('is never asked for the engine\'s stamp section', () {
      // Mutation: drop the stamp from the engine's sections, and the build
      // asks a compiler for the section that holds the revision the bundle
      // is checked by (this one throws when asked).
      build(
        registry: MaterialCompilerRegistry(<MaterialCompiler>[
          const _StampCompiler(),
        ]),
      );
      expect(bundle().section(EngineBundleStamp.section), isNotNull);
    });
  });

  group('a plugin\'s material', () {
    Directory plugin(String name, String source) {
      final root = Directory('${project.path}/$name')..createSync();
      File('${root.path}/assets_src/hair.f3dmat')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(source);
      return root;
    }

    PluginDiscovery shipping(Directory root, {List<String> needs = const []}) =>
        PluginDiscovery(
          plugins: const <DiscoveredPlugin>[],
          readFiles: const <String>[],
          dependencies: <String>{
            'flutter3d_impeller',
            root.uri.pathSegments.where((s) => s.isNotEmpty).last,
          },
          packages: <PluginPackage>[
            PluginPackage(
              name: root.uri.pathSegments.where((s) => s.isNotEmpty).last,
              root: root.path,
              shaderNeeds: needs,
            ),
          ],
        );

    test('is named in the namespace of the package shipping it', () {
      // Mutation: compile the name the source writes. `material Hair` of
      // two packages would be one stage, and the plugin's model
      // `acme_hair.Hair` would find neither.
      final report = build(
        plugins: shipping(
          plugin('acme_hair', _glow.replaceAll('AcmeGlow', 'Hair')),
        ),
      );
      expect(report.materials, <String>['acme_hair__Hair']);
      final material = ShaderBundle.decode(
        File(
          '${project.path}/${EngineBundleStamp.projectMaterialAsset('acme_hair__Hair')}',
        ).readAsBytesSync().buffer.asByteData(),
      );
      expect(material.names, contains('acme_hair__Hair'));
      // The source the bundle carries names the stage too, so a backend
      // that compiles it again reads the same name.
      expect(
        decodeMaterialSection(material)['acme_hair__Hair'],
        contains('material acme_hair__Hair'),
      );
    });

    test('in another plugin\'s namespace is refused', () {
      expect(
        () => build(
          plugins: shipping(
            plugin('acme_hair', _glow.replaceAll('AcmeGlow', 'other__Hair')),
          ),
        ),
        throwsA(
          isA<MaterialBuildException>().having(
            (e) => e.message,
            'message',
            contains('another plugin\'s namespace'),
          ),
        ),
      );
    });

    test('is what a need named after its plugin resolves to', () {
      final root = plugin('acme_hair', _glow.replaceAll('AcmeGlow', 'Hair'));
      expect(
        build(
          plugins: shipping(root, needs: const <String>['acme_hair.hair']),
        ).materials,
        <String>['acme_hair__Hair'],
      );
      // Mutation: drop a need nobody compiles, as the build did before.
      expect(
        () => build(
          plugins: shipping(root, needs: const <String>['acme_hair.fur']),
        ),
        throwsA(
          isA<MaterialBuildException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('acme_hair needs'),
              contains('"acme_hair.fur"'),
              contains('acme_hair__Hair'),
            ),
          ),
        ),
      );
    });
  });

  test('an unchanged build writes nothing, and one previous bundle stays', () {
    build();
    expect(build().written, isFalse);

    final previous = File(
      '${project.path}/${EngineBundleStamp.previousProjectAsset}',
    );
    final older = File(
      '${project.path}/flutter3d_generated/shaders/flutter3d.old.f3dshaders',
    )..writeAsStringSync('from long ago');
    manifest('shaders: [lambert]\n');
    expect(build().written, isTrue);
    expect(previous.existsSync(), isTrue);
    expect(older.existsSync(), isFalse);
    expect(
      ShaderBundle.decode(previous.readAsBytesSync().buffer.asByteData()).names,
      isNot(contains('Lambert')),
    );
    expect(bundle().names, contains('Lambert'));
  });

  test('the manifest refuses a need that is nobody\'s, on its line', () {
    expect(
      () => AssetBuildManifest.parse('format: 1\nshaders: [toon, sparkle]\n'),
      throwsA(
        isA<ManifestFormatException>()
            .having((e) => e.line, 'line', 2)
            .having((e) => e.message, 'message', contains('"sparkle"')),
      ),
    );
    expect(
      AssetBuildManifest.parse('shaders: [toon, acme.glow]\n').shaders.needs,
      <String>['toon', 'acme.glow'],
    );
  });

  test('a plugin package\'s needs count for the libraries installed', () {
    final pubspec = <Object?, Object?>{
      'flutter3d_plugins': <Object?, Object?>{
        'shaders': <Object?, Object?>{
          'style.dart': <Object?>['toon'],
          'light.dart': <Object?>['pbrLayered'],
        },
      },
    };
    expect(
      shaderNeedsOf(
        'flutter3d_post',
        pubspec,
        libraries: const <String>{'light.dart'},
      ),
      <String>['pbrLayered'],
    );
    expect(
      () => shaderNeedsOf('acme', <Object?, Object?>{
        'flutter3d_plugins': <Object?, Object?>{
          'shaders': <Object?>['sparkle'],
        },
      }),
      throwsA(isA<PluginDiscoveryException>()),
    );
  });
}

/// A WGSL compiler that compiles nothing: it names the stage it was handed,
/// and answers the offsets the reflection already holds.
CompiledStage _stubWgsl(
  PreparedStage stage, {
  required String name,
  required bool fragment,
}) => CompiledStage(
  spirv: Uint8List(0),
  target: ShaderTarget.wgsl,
  text: '// $name',
  offsets: <String, Map<String, int>>{
    for (final block in stage.blocks)
      block.name: <String, int>{
        for (final member in block.members) member.name: member.offsetInBytes,
      },
  },
);

/// Why the real compilers cannot run here, or null when they can.
String? _noWgslCompilers() {
  for (final program in <String>[glslangExecutable, nagaExecutable]) {
    try {
      Process.runSync(program, const <String>['--version']);
    } on ProcessException {
      return '$program is not on PATH';
    }
  }
  return null;
}

/// A compiler from outside that names the engine's stamp section.
final class _StampCompiler extends MaterialCompiler {
  const _StampCompiler();

  @override
  String get backend => 'stamp';

  @override
  String get bundleSection => EngineBundleStamp.section;

  @override
  MaterialCompileResult compile(MaterialCompileRequest request) =>
      throw StateError('the stamp section was asked of an outside compiler');
}

final class _Log implements IOSink {
  final StringBuffer _buffer = StringBuffer();

  String get text => _buffer.toString();

  @override
  void writeln([Object? object = '']) => _buffer.writeln(object);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
