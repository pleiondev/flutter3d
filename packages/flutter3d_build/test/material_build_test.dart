/// P8: a material source compiles, at build time, into a bundle every GPU
/// backend loads.
///
///     dart test test/material_build_test.dart
///
/// **`impellerc` is a stub here**, a shell script that writes known bytes
/// where `--sl=` points — `flutter3d_impeller`'s `build_shaders_test.dart`
/// does the same, for the same reason: the real binary lives in a Flutter
/// SDK's artifact cache, and what this file checks is what the build does
/// with its answer. The WGSL compile has the same seam, and one test runs the
/// real glslang and naga where a machine has them. The WebGL2 translation has
/// no seam: it is pure Dart and always runs for real.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:flutter3d_build_hooks/flutter3d_build_hooks.dart';
import 'package:flutter3d_hardware/shader_bundle.dart';
import 'package:flutter3d_shaders/compile.dart';
import 'package:test/test.dart';

const String _rim = '''
material RimLight {
  param float rimPower = 2.0;
  texture base = base_color_texture;

  fragment {
    let facing = clamp(nDotV, 0.0, 1.0);
    let rim = pow(1.0 - facing, rimPower);
    let texel = sample(base, uv);
    return vec4(albedo * texel.rgb + vec3(rim), alpha * texel.a);
  }
}
''';

/// What the stub writes, so a test can tell its bytes in the bundle.
const String _impellerBytes = 'stub impellerc output';

/// glslang's offsets read straight off the reflection, which is what a
/// compiler that agrees with the std140 arithmetic would report.
CompiledStage _fakeWgsl(
  PreparedStage stage, {
  required String name,
  required bool fragment,
}) => (
  wgsl: '// WGSL for $name\n@fragment fn main() {}\n',
  offsets: <String, Map<String, int>>{
    for (final block in stage.blocks)
      block.name: <String, int>{
        for (final member in block.members) member.name: member.offsetInBytes,
      },
  },
);

void main() {
  // The engine's real tree, found from this package the way a hook finds it
  // from a project.
  final engine = loadShaders();

  late Directory project;
  late _Log log;

  setUp(() {
    project = Directory.systemTemp.createTempSync('f3d_material_');
    log = _Log();
  });
  tearDown(() => project.deleteSync(recursive: true));

  File source(String relative, String text) =>
      File('${project.path}/assets_src/$relative')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(text);

  /// A stub `impellerc` that writes [_impellerBytes] to `--sl=`, or exits
  /// non-zero with [refusal] on stderr; it records its arguments beside it.
  MaterialCompilers stub({String? refusal, WgslStageCompiler? wgsl}) {
    final script = File('${project.path}/sdk/impellerc')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('''
#!/usr/bin/env bash
printf '%s\\n' "\$@" > "\$(dirname "\$0")/arguments.txt"
${refusal == null ? '' : 'echo "$refusal" >&2; exit 1'}
for arg in "\$@"; do
  case "\$arg" in
    --sl=*) printf '%s' '$_impellerBytes' > "\${arg#--sl=}" ;;
  esac
done
''');
    final chmod = Process.runSync('chmod', <String>['+x', script.path]);
    expect(chmod.exitCode, 0, reason: '${chmod.stderr}');
    return MaterialCompilers(
      impellerc: script.path,
      sdk: '3.13.0',
      wgsl: wgsl ?? _fakeWgsl,
    );
  }

  ShaderBundle readBundle(String relative) {
    final bytes = File(
      '${project.path}/flutter3d_generated/$relative',
    ).readAsBytesSync();
    return ShaderBundle.decode(bytes.buffer.asByteData());
  }

  String text(ByteData bytes) => utf8.decode(
    bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
  );

  group('with a stub impellerc', () {
    test('one source becomes one bundle carrying all three sections', () {
      // Mutation: drop `ShaderBundle.webgpuSection` from the map
      // `compileMaterial` returns — the bundle still decodes and still loads
      // on Impeller and WebGL2, and this fails on the section list.
      source('fx/rim.f3dmat', _rim);

      final report = runMaterialBuild(
        project,
        log: log,
        compilers: stub(),
        engine: engine,
      );

      expect(report.built, <String>[
        '${project.path}/assets_src/fx/rim.f3dmat',
      ]);
      final bundle = readBundle('fx/rim.f3dshaders');
      expect(bundle.name, 'RimLight');
      expect(bundle.sdk, '3.13.0');
      expect(bundle.stages.single.name, 'RimLight');
      expect(bundle.stages.single.fragment, isTrue);
      expect(bundle.sections.keys, <String>[
        ShaderBundle.impellerSection,
        ShaderBundle.webglSection,
        ShaderBundle.webgpuSection,
        ShaderBundle.materialSection,
      ]);

      // `P8`: the source itself, which the software backend compiles and a
      // runtime reads the lighting model out of.
      expect(
        decodeMaterialSection(bundle)['RimLight'],
        contains('material RimLight'),
      );

      // Impeller's is impellerc's answer, as it is.
      expect(
        text(bundle.section(ShaderBundle.impellerSection)!),
        _impellerBytes,
      );

      // WebGL2's is the translation, which is real here: GLSL ES 3.00 with
      // the engine's headers inlined and the material's body in it.
      final webgl = decodeWebGlSection(
        bundle.section(ShaderBundle.webglSection)!,
      );
      expect(webgl.vertex, isEmpty);
      expect(webgl.fragment['RimLight'], startsWith('#version 300 es'));
      expect(webgl.fragment['RimLight'], contains('struct Surface'));
      expect(
        webgl.fragment['RimLight'],
        contains('texture(base_color_texture'),
      );

      // WebGPU's carries the WGSL and the reflection the browser cannot be
      // asked for: the sampler the material reads has a group and binding.
      final webgpu =
          jsonDecode(text(bundle.section(ShaderBundle.webgpuSection)!))
              as Map<String, Object?>;
      expect(webgpu['version'], sectionVersion);
      final stage =
          (webgpu['fragment']! as Map<String, Object?>)['RimLight']!
              as Map<String, Object?>;
      expect(stage['wgsl'], contains('@fragment'));
      expect(
        (stage['samplers']! as List<Object?>).map(
          (s) => (s! as Map<String, Object?>)['name'],
        ),
        contains('base_color_texture'),
      );
    });

    test('impellerc is asked for one fragment stage, against the engine\'s '
        'headers', () {
      // Mutation: drop the `--include=${engine.root}` argument — the real
      // impellerc then fails on `#include <lib/surface.glsl>`, which the stub
      // cannot, so the argument itself is what is held.
      source('rim.f3dmat', _rim);
      runMaterialBuild(project, log: log, compilers: stub(), engine: engine);

      final arguments = File(
        '${project.path}/sdk/arguments.txt',
      ).readAsLinesSync();
      final manifest =
          jsonDecode(
                arguments
                    .firstWhere((a) => a.startsWith('--shader-bundle='))
                    .substring('--shader-bundle='.length),
              )
              as Map<String, Object?>;
      expect(manifest.keys, <String>['RimLight']);
      expect(
        (manifest['RimLight']! as Map<String, Object?>)['type'],
        'fragment',
      );
      expect(arguments, contains('--include=${engine.root}'));
    });

    test('every source and every engine header is a dependency', () {
      // Mutation: return only the material sources from
      // `MaterialBuildReport.dependencies` — an edit to `surface.glsl`, which
      // every material includes, then leaves every bundle stale until some
      // other file changes.
      source('rim.f3dmat', _rim);
      final report = runMaterialBuild(
        project,
        log: log,
        compilers: stub(),
        engine: engine,
      );
      expect(
        report.dependencies,
        containsAll(<String>[
          '${project.path}/assets_src/rim.f3dmat',
          '${engine.root}/lib/surface.glsl',
        ]),
      );
    });

    test('an unchanged source is not compiled again, and a removed one takes '
        'its bundle with it', () {
      // Mutation: skip the stale sweep at the top of `runMaterialBuild` —
      // the deleted material's bundle stays in `flutter3d_generated/`, which
      // is bundled whole, and ships.
      final rim = source('rim.f3dmat', _rim);
      runMaterialBuild(project, log: log, compilers: stub(), engine: engine);

      final again = runMaterialBuild(
        project,
        log: log,
        compilers: stub(),
        engine: engine,
      );
      expect(again.built, isEmpty);
      expect(again.skipped, <String>[rim.path]);

      rim.deleteSync();
      runMaterialBuild(project, log: log, compilers: stub(), engine: engine);
      expect(
        File('${project.path}/flutter3d_generated/rim.f3dshaders').existsSync(),
        isFalse,
      );
    });

    test('a bundle built by a flutter3d with another container version is '
        'rebuilt rather than shipped stale', () {
      // Bundles are build artifacts (decision 8 of `tasks/1.0-stability.md`):
      // the runtime refuses a container version it does not read, so the
      // build must never keep one. The cache is rewritten here to say the
      // bundle was made at container version 0. Mutation: leave
      // `ShaderBundle.formatVersion` out of the stamp and the rewrite changes
      // nothing, so the old bundle is skipped.
      final rim = source('rim.f3dmat', _rim);
      runMaterialBuild(project, log: log, compilers: stub(), engine: engine);
      final cache = File(
        '${project.path}/flutter3d_generated/.flutter3d_materials.json',
      );
      cache.writeAsStringSync(
        cache.readAsStringSync().replaceAll(
          'f3sb${ShaderBundle.formatVersion}',
          'f3sb0',
        ),
      );

      final again = runMaterialBuild(
        project,
        log: log,
        compilers: stub(),
        engine: engine,
      );
      expect(again.built, <String>[rim.path]);
    });

    test('a source with a mistake in it names its file, line and column, '
        'and writes nothing', () {
      // Mutation: rethrow the parser's `MaterialSyntaxException` unwrapped — the
      // message keeps its line but loses the file, and with two materials in
      // a project the author is left to guess which.
      final bad = source('fx/bad.f3dmat', '''
material Bad {
  fragment {
    let x = nope(1.0);
    return vec4(x);
  }
}
''');

      expect(
        () => runMaterialBuild(
          project,
          log: log,
          compilers: stub(),
          engine: engine,
        ),
        throwsA(
          isA<MaterialBuildException>()
              .having((e) => e.source, 'source', bad.path)
              .having((e) => e.line, 'line', 3)
              .having(
                (e) => e.toString(),
                'text',
                startsWith('${bad.path}:3:'),
              ),
        ),
      );
      expect(
        File(
          '${project.path}/flutter3d_generated/fx/bad.f3dshaders',
        ).existsSync(),
        isFalse,
      );
    });

    test('a compiler refusing the generated GLSL names the source and keeps '
        'the GLSL where its line can be opened', () {
      // Mutation: delete the generated `.frag` before calling impellerc's
      // result an error — the message then points at a file that is gone,
      // and the line impellerc named is a line nobody can read.
      final rim = source('rim.f3dmat', _rim);

      expect(
        () => runMaterialBuild(
          project,
          log: log,
          compilers: stub(refusal: 'RimLight.frag:12: syntax error'),
          engine: engine,
        ),
        throwsA(
          isA<MaterialBuildException>()
              .having((e) => e.source, 'source', rim.path)
              .having(
                (e) => e.message,
                'message',
                allOf(
                  contains('impellerc'),
                  contains('RimLight.frag:12: syntax error'),
                ),
              ),
        ),
      );
      expect(
        File(
          '${project.path}/.dart_tool/flutter3d_build/materials/RimLight.frag',
        ).existsSync(),
        isTrue,
      );
    });

    test('without glslang and naga the bundle carries the other two sections, '
        'and says so', () {
      // Mutation: make a null `wgsl` an error — every machine without the
      // Vulkan SDK, CI among them, then fails the whole build over one
      // backend's tooling.
      source('rim.f3dmat', _rim);
      final compilers = stub();
      runMaterialBuild(
        project,
        log: log,
        compilers: MaterialCompilers(
          impellerc: compilers.impellerc,
          sdk: compilers.sdk,
        ),
        engine: engine,
      );
      expect(readBundle('rim.f3dshaders').sections.keys, <String>[
        ShaderBundle.impellerSection,
        ShaderBundle.webglSection,
        ShaderBundle.materialSection,
      ]);
      expect(log.text, contains('no "webgpu" section'));
    });
  }, skip: Platform.isWindows ? 'the stub impellerc is a bash script' : null);

  test('a project with no materials looks for no compiler and no engine', () {
    // Mutation: call `MaterialCompilers.locate()` before checking the plan —
    // this process is not always a Flutter SDK's Dart, and a project with
    // only models in it would then fail to build for want of impellerc.
    source('hero.obj', 'v 0 0 0\n');
    final report = runMaterialBuild(project, log: log);
    expect(report.built, isEmpty);
    expect(report.dependencies, isEmpty);
  });

  test('the real glslang and naga carry a material into WGSL', () {
    // The fake above agrees with the reflection by construction; this is the
    // one place the two compilers get to disagree with it.
    source('rim.f3dmat', _rim);
    final script = File('${project.path}/impellerc')
      ..writeAsStringSync(
        '#!/usr/bin/env bash\n'
        'for a in "\$@"; do case "\$a" in --sl=*) : > "\${a#--sl=}";; esac; '
        'done\n',
      );
    Process.runSync('chmod', <String>['+x', script.path]);
    runMaterialBuild(
      project,
      log: log,
      compilers: MaterialCompilers(
        impellerc: script.path,
        sdk: '3.13.0',
        wgsl: (stage, {required name, required fragment}) =>
            compileStage(stage.glsl, name: name, fragment: fragment),
      ),
      engine: engine,
    );
    final bundle = readBundle('rim.f3dshaders');
    final document =
        jsonDecode(text(bundle.section(ShaderBundle.webgpuSection)!))
            as Map<String, Object?>;
    final wgsl =
        ((document['fragment']! as Map<String, Object?>)['RimLight']!
                as Map<String, Object?>)['wgsl']!
            as String;
    expect(wgsl, contains('@fragment'));
    expect(wgsl, contains('base_color_texture'));
  }, skip: _missing() ?? (Platform.isWindows ? 'bash stub' : null));
}

/// Why the real-compiler test cannot run here, or null when it can.
String? _missing() {
  for (final program in <String>[glslangExecutable, nagaExecutable]) {
    try {
      Process.runSync(program, const <String>['--version']);
    } on ProcessException {
      return '$program is not on PATH';
    }
  }
  return null;
}

/// An [IOSink] that keeps what it was told.
final class _Log implements IOSink {
  final StringBuffer _buffer = StringBuffer();

  String get text => _buffer.toString();

  @override
  Encoding encoding = utf8;

  @override
  void write(Object? object) => _buffer.write(object);

  @override
  void writeln([Object? object = '']) => _buffer.writeln(object);

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _buffer.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _buffer.writeCharCode(charCode);

  @override
  void add(List<int> data) => _buffer.write(utf8.decode(data));

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> get done async {}
}
