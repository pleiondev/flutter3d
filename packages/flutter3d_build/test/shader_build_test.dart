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

import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:flutter3d_build_hooks/flutter3d_build_hooks.dart';
import 'package:flutter3d_hardware/shader_bundle.dart';
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
  }) => runShaderBuild(
    project,
    plugins: plugins,
    log: log,
    full: full,
    target: target,
    compilers: stub(),
    engine: engine,
    engineRevision: 'abc123',
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
    expect(report.materials, <String>['AcmeGlow']);
    final material = File(
      '${project.path}/${EngineBundleStamp.projectMaterialAsset('AcmeGlow')}',
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
      () => AssetManifest.parse('format: 1\nshaders: [toon, sparkle]\n'),
      throwsA(
        isA<ManifestFormatException>()
            .having((e) => e.line, 'line', 2)
            .having((e) => e.message, 'message', contains('"sparkle"')),
      ),
    );
    expect(
      AssetManifest.parse('shaders: [toon, acme.glow]\n').shaders.needs,
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

final class _Log implements IOSink {
  final StringBuffer _buffer = StringBuffer();

  String get text => _buffer.toString();

  @override
  void writeln([Object? object = '']) => _buffer.writeln(object);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
