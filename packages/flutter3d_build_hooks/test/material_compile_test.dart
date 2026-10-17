/// A material build asks the backends' own compilers (D26), refuses stages
/// that disagree with the build's own exception, and numbers a material's
/// own blocks and textures after the engine's on WebGPU (D21).
///
///     dart test test/material_compile_test.dart
///
/// **`impellerc` is a stub**, as in `flutter3d_build`'s
/// `material_build_test.dart`: a shell script that writes known bytes where
/// `--sl=` points. The WGSL compile is a stand-in too, reporting the offsets
/// the reflection already holds; what the WebGPU section is checked for is
/// the numbering, which the reflection carries.
@TestOn('mac-os || linux')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_build_hooks/flutter3d_build_hooks.dart';
import 'package:flutter3d_hardware/shader_bundle.dart';
import 'package:flutter3d_shaders/backend.dart';
import 'package:flutter3d_shaders/compile.dart';
import 'package:test/test.dart';

const String _hair = '''
f3dmat 2
material acme_sample_Hair {
  uniform float gloss = 0.5;
  uniform(Strands) vec3 tint = vec3(0.4, 0.3, 0.2);
  uniform(Strands) float shift = 0.1;
  texture fur;

  light { return albedo * tint * nDotL; }
  fragment {
    let strands = sample(fur, uv).rgb;
    return vec4(lit * strands * (gloss + shift), alpha);
  }
}
''';

CompiledStage _fakeWgsl(
  PreparedStage stage, {
  required String name,
  required bool fragment,
}) => CompiledStage(
  spirv: Uint8List(0),
  target: ShaderTarget.wgsl,
  text: '// WGSL for $name\n@fragment fn main() {}\n',
  offsets: <String, Map<String, int>>{
    for (final block in stage.blocks)
      block.name: <String, int>{
        for (final member in block.members) member.name: member.offsetInBytes,
      },
  },
);

/// A fifth backend's compiler: writes the stage names into a section of its
/// own, or refuses as [refusal] says.
final class _Fifth extends MaterialCompiler {
  _Fifth({this.section = 'fifth', this.refusal, this.buildWrites = false});

  final String section;
  final Exception? refusal;
  final bool buildWrites;
  final List<MaterialCompileRequest> asked = <MaterialCompileRequest>[];

  @override
  String get backend => 'fifth';

  @override
  String get bundleSection => section;

  @override
  bool get isSectionWrittenByBuild => buildWrites;

  @override
  MaterialCompileResult compile(MaterialCompileRequest request) {
    asked.add(request);
    if (refusal case final refusal?) throw refusal;
    return MaterialCompileResult(
      section: Uint8List.fromList(
        utf8.encode(request.stages.map((s) => s.name).join(',')),
      ).buffer.asByteData(),
    );
  }
}

String _text(ByteData bytes) => utf8.decode(
  bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
);

void main() {
  final engine = loadShaders();
  late Directory scratch;
  late File impellerc;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('f3d_hooks_');
    impellerc = File('${scratch.path}/sdk/impellerc')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(r'''
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in
    --sl=*) printf '%s' 'stub impellerc output' > "${arg#--sl=}" ;;
  esac
done
''');
    Process.runSync('chmod', <String>['+x', impellerc.path]);
  });
  tearDown(() => scratch.deleteSync(recursive: true));

  ShaderBundle build({MaterialCompilerRegistry? registry, bool wgsl = true}) =>
      compileMaterial(
        _hair,
        source: 'assets_src/hair.f3dmat',
        engine: engine,
        compilers: MaterialCompilers(
          impellerc: impellerc.path,
          sdk: '3.13.0',
          wgsl: wgsl ? _fakeWgsl : null,
          registry: registry,
        ),
        scratch: Directory('${scratch.path}/out'),
      );

  test('a registered compiler writes its own section', () {
    // Mutation: drop the registry loop from `compileMaterial` and the bundle
    // carries no "fifth" section and the compiler is never asked.
    final fifth = _Fifth();
    final bundle = build(
      registry: MaterialCompilerRegistry(<MaterialCompiler>[fifth]),
    );
    expect(_text(bundle.section('fifth')!), 'acme_sample_Hair');
    final request = fifth.asked.single;
    expect(request.from, 'assets_src/hair.f3dmat');
    expect(request.atRunTime, isFalse);
    expect(request.stages.single.glsl, contains('f3d_block_Strands'));
    expect(request.engineSources, isNotEmpty);
    // The stages this build wrote as WGSL, for WebGPU's own compiler.
    expect(
      request.options[MaterialCompileRequest.webGpuStagesOption],
      isA<Map<String, PackedStage>>().having((m) => m.keys, 'keys', <String>[
        'acme_sample_Hair',
      ]),
    );
    // The three this build writes are still there.
    expect(
      bundle.sections.keys,
      containsAll(<String>[
        ShaderBundle.impellerSection,
        ShaderBundle.webglSection,
        ShaderBundle.webgpuSection,
        ShaderBundle.materialSection,
      ]),
    );
  });

  test('a refusal from a compiler whose section the build writes keeps '
      'the build\'s', () {
    final bundle = build(
      registry: MaterialCompilerRegistry(<MaterialCompiler>[
        _Fifth(
          section: ShaderBundle.impellerSection,
          buildWrites: true,
          refusal: const MaterialCompileException(
            'impellerc runs in the build',
          ),
        ),
      ]),
    );
    expect(
      _text(bundle.section(ShaderBundle.impellerSection)!),
      'stub impellerc output',
    );
  });

  test('any other refusal fails the build, whatever it wrote', () {
    // Mutation: skip a refusal whenever the build wrote the section, as
    // the build once did, and a WebGL compiler that refuses the material
    // ships the build's own section as if it had agreed.
    expect(
      () => build(
        registry: MaterialCompilerRegistry(<MaterialCompiler>[
          _Fifth(
            section: ShaderBundle.webglSection,
            refusal: const MaterialCompileException('not this material'),
          ),
        ]),
      ),
      throwsA(
        isA<MaterialBuildException>().having(
          (e) => e.message,
          'message',
          contains('not this material'),
        ),
      ),
    );
  });

  test('without glslang and naga WebGPU gets no section, and no error', () {
    // Mutation: ask WebGPU's compiler with no stages, and its refusal
    // fails a build the file promises goes on without the section.
    final webgpu = _Fifth(
      section: ShaderBundle.webgpuSection,
      refusal: const MaterialCompileException('no WGSL to pack'),
    );
    final bundle = build(
      wgsl: false,
      registry: MaterialCompilerRegistry(<MaterialCompiler>[webgpu]),
    );
    expect(webgpu.asked, isEmpty);
    expect(bundle.section(ShaderBundle.webgpuSection), isNull);
    expect(
      bundle.sections.keys,
      containsAll(<String>[
        ShaderBundle.impellerSection,
        ShaderBundle.webglSection,
        ShaderBundle.materialSection,
      ]),
    );
  });

  test('a refusal of a section of its own fails the build', () {
    expect(
      () => build(
        registry: MaterialCompilerRegistry(<MaterialCompiler>[
          _Fifth(refusal: const MaterialCompileException('no toolchain here')),
        ]),
      ),
      throwsA(
        isA<MaterialBuildException>()
            .having((e) => e.source, 'source', 'assets_src/hair.f3dmat')
            .having((e) => e.message, 'message', contains('no toolchain here')),
      ),
    );
  });

  test('stages that disagree are a MaterialBuildException naming both', () {
    // Mutation: let `StageAgreementException` through `compileMaterial`
    // and it arrives as itself, with no source to name.
    final disagreement = StageAgreementException(<StageMismatch>[
      checkStageAgreement(
        vertex: const StageInterface(
          name: 'acme_sample_HairVertex',
          fragment: false,
          outputs: <StageVariable>[StageVariable('v_uv', 'vec2')],
        ),
        fragment: const StageInterface(
          name: 'acme_sample_Hair',
          fragment: true,
          inputs: <StageVariable>[StageVariable('v_uv', 'vec3')],
        ),
      ).single,
    ]);
    expect(
      () => build(
        registry: MaterialCompilerRegistry(<MaterialCompiler>[
          _Fifth(refusal: disagreement),
        ]),
      ),
      throwsA(
        isA<MaterialBuildException>()
            .having((e) => e.source, 'source', 'assets_src/hair.f3dmat')
            .having(
              (e) => e.message,
              'message',
              allOf(contains('acme_sample_HairVertex'), contains('v_uv')),
            ),
      ),
    );
  });

  test('WebGPU numbers the material\'s own after the engine\'s', () {
    // Mutation: drop `ownBindings` from the build's `prepareStage` and
    // `Strands` and `material_fur` are numbered among the engine's by name.
    final bundle = build();
    final document =
        jsonDecode(_text(bundle.section(ShaderBundle.webgpuSection)!))
            as Map<String, dynamic>;
    final stage =
        (document['fragment'] as Map<String, dynamic>)['acme_sample_Hair']
            as Map<String, dynamic>;
    final numbers = <String, int>{
      for (final block in stage['blocks'] as List<dynamic>)
        (block as Map<String, dynamic>)['name'] as String:
            block['binding'] as int,
      for (final sampler in stage['samplers'] as List<dynamic>)
        (sampler as Map<String, dynamic>)['name'] as String:
            sampler['texture'] as int,
    };
    const own = <String>['MaterialParams', 'Strands', 'material_fur'];
    final engineLast = numbers.entries
        .where((e) => !own.contains(e.key))
        .map((e) => e.value)
        .reduce((a, b) => a > b ? a : b);
    expect(
      <int>[for (final name in own) numbers[name]!],
      <int>[engineLast + 2, engineLast + 3, engineLast + 4],
    );
  });

  test('a compute stage is built as its kernel, lowered', () {
    // Mutation: refuse it as before, and a texture computed by a material
    // never reaches a device that computes.
    final bundle = compileMaterial(
      '''
f3dmat 2
compute Ripples {
  uniform float time = 0.0;
  kernel { return vec4(vec3(0.5 + 0.5 * sin(time)), 1.0); }
}
''',
      source: 'assets_src/ripples.f3dmat',
      engine: engine,
      compilers: MaterialCompilers(impellerc: impellerc.path, sdk: '3.13.0'),
      scratch: Directory('${scratch.path}/out'),
    );
    expect(bundle.stages.single.name, 'Ripples');
    expect(bundle.stages.single.kind, ShaderStageKind.compute);
    expect(bundle.section(ShaderBundle.impellerSection), isNull);
    final source = decodeKernelSection(bundle)['Ripples']!;
    expect(source, startsWith('kernel 1\n'));
    expect(source, contains('image target: rgba8;'));
  });
}
