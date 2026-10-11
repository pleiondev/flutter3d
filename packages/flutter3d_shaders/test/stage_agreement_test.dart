/// The section writers refuse a bundle whose stages disagree, naming both
/// (amendment 5): a vertex stage is held to the fragment stage its name
/// pairs it with before the WebGL or the WebGPU section is written.
///
///     dart test test/stage_agreement_test.dart
///
/// Mutation: drop `requireBundleAgreement` from `encodeWebGlSection` and the
/// WebGL refusal test writes the section; pair `<F>VertexSkinned` with
/// nothing in `pairedFragmentStage` and the skinned half goes unchecked.
library;

import 'package:flutter3d_shaders/translate.dart';
import 'package:test/test.dart';

const String _vertex = '''
#version 300 es
in vec3 position;
uniform FrameInfo {
  mat4 view_projection;
};
out vec2 v_texcoord;
out vec3 v_world;
void main() {}
''';

const String _fragment = '''
#version 300 es
precision highp float;
in vec2 v_texcoord;
in vec3 v_world;
uniform FrameInfo {
  mat4 view_projection;
};
out vec4 frag_color;
void main() {}
''';

void main() {
  group('pairedFragmentStage', () {
    const fragments = <String>{'Hair', 'Particle', 'Pbr'};

    test('pairs a vertex stage and its halves with the fragment stage', () {
      expect(pairedFragmentStage('HairVertex', fragments), 'Hair');
      expect(pairedFragmentStage('HairVertexSkinned', fragments), 'Hair');
      expect(pairedFragmentStage('HairVertexInstanced', fragments), 'Hair');
      expect(pairedFragmentStage('HairVertexLightmapped', fragments), 'Hair');
      expect(pairedFragmentStage('ParticleVertex', fragments), 'Particle');
    });

    test('leaves a shared vertex stage unpaired', () {
      expect(pairedFragmentStage('MeshVertex', fragments), isNull);
      expect(pairedFragmentStage('MeshSkinnedVertex', fragments), isNull);
      expect(pairedFragmentStage('Vertex', fragments), isNull);
      expect(pairedFragmentStage('Pbr', fragments), isNull);
    });
  });

  group('the WebGL section', () {
    test('is written when the paired stages agree', () {
      final section = encodeWebGlSection(
        vertex: const <String, String>{
          'GlowVertex': _vertex,
          'MeshVertex': 'in vec4 unrelated; out float v_other;',
        },
        fragment: const <String, String>{'Glow': _fragment},
      );
      expect(decodeWebGlSection(section).fragment.keys, <String>['Glow']);
    });

    test('is refused with both names when a varying disagrees', () {
      expect(
        () => encodeWebGlSection(
          vertex: <String, String>{
            'GlowVertexSkinned': _vertex.replaceFirst(
              'out vec3 v_world;',
              'out vec4 v_world;',
            ),
          },
          fragment: const <String, String>{'Glow': _fragment},
        ),
        throwsA(
          isA<StageAgreementException>()
              .having((e) => e.mismatches.single.name, 'name', 'v_world')
              .having(
                (e) => e.message,
                'message',
                allOf(
                  contains('"GlowVertexSkinned"'),
                  contains('"Glow"'),
                  contains('vec4 v_world'),
                  contains('vec3 v_world'),
                ),
              ),
        ),
      );
    });

    test('is refused when a block is declared two ways', () {
      final found = checkBundleAgreement(
        vertex: <String, String>{
          'GlowVertex': _vertex.replaceFirst(
            'mat4 view_projection;',
            'mat4 view_projection;\n  vec4 camera;',
          ),
        },
        fragment: const <String, String>{'Glow': _fragment},
      );
      expect(found.single.kind, StageMismatchKind.block);
      expect(found.single.name, 'FrameInfo');
    });
  });

  test('the WebGPU section is refused when a varying is never written', () {
    PackedStage packed(String glsl) => (
      wgsl: '',
      prepared: PreparedStage(
        glsl: glsl,
        attributes: const <PreparedAttribute>[],
        blocks: const <PreparedBlock>[],
        samplers: const <PreparedSampler>[],
      ),
    );
    expect(
      () => wgslSectionDocument(
        vertex: <String, PackedStage>{
          'GlowVertex': packed(_vertex.replaceFirst('out vec3 v_world;', '')),
        },
        fragment: <String, PackedStage>{'Glow': packed(_fragment)},
      ),
      throwsA(
        isA<StageAgreementException>().having(
          (e) => e.message,
          'message',
          contains('"Glow" reads the varying v_world'),
        ),
      ),
    );
    expect(
      wgslSectionDocument(
        vertex: <String, PackedStage>{'GlowVertex': packed(_vertex)},
        fragment: <String, PackedStage>{'Glow': packed(_fragment)},
      ),
      contains('"Glow"'),
    );
  });
}
