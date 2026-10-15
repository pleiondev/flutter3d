/// The backend author's shader contract: the material compiler registry and
/// the check that a pipeline's stages agree (D26, D27, amendment 5).
///
///     dart test test/backend_contract_test.dart
///
/// Mutation: answer the first compiler registered in `forBackend` and the
/// replacement test fails; drop the type comparison from
/// `checkStageAgreement` and the varying test finds nothing.
library;

import 'dart:typed_data';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show NameTakenException;
import 'package:flutter3d_shaders/backend.dart';
import 'package:test/test.dart';

final class _Compiler extends MaterialCompiler {
  const _Compiler(this.backend, this.bundleSection, {this.tag = 0});

  @override
  final String backend;

  @override
  final String bundleSection;

  final int tag;

  @override
  bool get compilesAtRunTime => true;

  @override
  MaterialCompileResult compile(MaterialCompileRequest request) =>
      MaterialCompileResult(
        section: ByteData(4)..setUint32(0, tag),
        notes: <String>[for (final stage in request.stages) stage.name],
      );
}

const String _vertex = '''
#version 460 core
in vec3 position;
in vec2 texcoord;
uniform FrameInfo {
  mat4 view_projection;
  vec4 camera; // xyz, and the time
};
out vec2 v_texcoord;
layout(location = 3) out vec3 v_world;
/* out vec4 v_commented_out; */
void main() {
  v_texcoord = texcoord;
}
''';

const String _fragment = '''
#version 460 core
in vec2 v_texcoord;
layout(location = 3) in vec3 v_world;
uniform FrameInfo {
  mat4 view_projection;
  vec4 camera;
};
out vec4 frag_color;
void main() {}
''';

void main() {
  group('material compilers', () {
    test('a backend\'s compiler is found by its name, the latest first', () {
      final registry = MaterialCompilerRegistry(<MaterialCompiler>[
        const _Compiler('vulkan', 'vulkan'),
      ]);
      expect(registry.forBackend('vulkan'), isNotNull);
      expect(registry.forBackend('metal'), isNull);

      final replacing = registry.register(
        const _Compiler('vulkan', 'vulkan', tag: 2),
      );
      expect((registry.forBackend('vulkan')! as _Compiler).tag, 2);
      replacing.cancel();
      expect((registry.forBackend('vulkan')! as _Compiler).tag, 0);
      expect(registry.backends, <String>{'vulkan'});
    });

    test('two backends cannot write one bundle section', () {
      final registry = MaterialCompilerRegistry(<MaterialCompiler>[
        const _Compiler('vulkan', 'spirv'),
      ]);
      expect(
        () => registry.register(const _Compiler('metal', 'spirv')),
        throwsA(
          isA<NameTakenException>().having(
            (e) => e.message,
            'message',
            contains('vulkan'),
          ),
        ),
      );
    });

    test('a compiler is handed one request and answers its section', () {
      final result = const _Compiler('vulkan', 'vulkan', tag: 7).compile(
        const MaterialCompileRequest(
          name: 'Glow',
          from: 'glow.f3dmat',
          source: 'material Glow {}',
          stages: <MaterialStageSource>[
            MaterialStageSource(name: 'Glow', fragment: true, glsl: ''),
          ],
        ),
      );
      expect(result.section.getUint32(0), 7);
      expect(result.notes, <String>['Glow']);
    });
  });

  group('stage agreement', () {
    test('two stages that agree have nothing to say', () {
      final vertex = StageInterface.fromGlsl(
        _vertex,
        name: 'GlowVertex',
        fragment: false,
      );
      final fragment = StageInterface.fromGlsl(
        _fragment,
        name: 'Glow',
        fragment: true,
      );
      expect(vertex.inputs.map((v) => v.name), <String>[
        'position',
        'texcoord',
      ]);
      expect(vertex.outputs.map((v) => v.name), <String>[
        'v_texcoord',
        'v_world',
      ]);
      expect(vertex.outputs.last.location, 3);
      expect(vertex.blocks['FrameInfo'], hasLength(2));
      expect(
        checkStageAgreement(
          vertex: vertex,
          fragment: fragment,
          attributes: const <StageVariable>[
            StageVariable('position', 'vec3'),
            StageVariable('texcoord', 'vec2'),
          ],
        ),
        isEmpty,
      );
    });

    test('a varying, an attribute and a block that disagree are named', () {
      final vertex = StageInterface.fromGlsl(
        _vertex,
        name: 'GlowVertex',
        fragment: false,
      );
      final fragment = StageInterface.fromGlsl(
        _fragment
            .replaceFirst('in vec2 v_texcoord;', 'in vec3 v_texcoord;')
            .replaceFirst('out vec4 frag_color;', 'in float v_fade;')
            .replaceFirst('vec4 camera;', 'vec3 camera;'),
        name: 'Glow',
        fragment: true,
      );
      final found = checkStageAgreement(
        vertex: vertex,
        fragment: fragment,
        attributes: const <StageVariable>[StageVariable('position', 'vec4')],
      );
      String says(StageMismatchKind kind, String name) =>
          found.singleWhere((m) => m.kind == kind && m.name == name).says;

      expect(
        says(StageMismatchKind.varying, 'v_texcoord'),
        allOf(contains('vec2 v_texcoord'), contains('vec3 v_texcoord')),
      );
      expect(
        says(StageMismatchKind.varying, 'v_fade'),
        contains('does not write'),
      );
      expect(says(StageMismatchKind.attribute, 'position'), contains('vec4'));
      expect(
        says(StageMismatchKind.attribute, 'texcoord'),
        contains('does not give it'),
      );
      expect(says(StageMismatchKind.block, 'FrameInfo'), contains('vec3'));
    });
  });

  test('a shader target is read back by its name', () {
    for (final target in ShaderTarget.values) {
      expect(ShaderTarget.byName(target.name), same(target));
    }
    expect(ShaderTarget.byName('dxil'), isNull);
    expect(ShaderTarget.spirv.extension, isNull);
  });
}
