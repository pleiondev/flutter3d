/// The translation rules, checked without a browser.
///
/// Each of these is a rule that, got wrong, produces a shader that either fails
/// to compile with a message about a line the author did not write, or — worse
/// — compiles and renders subtly differently from the other backend. The std140
/// one is the second kind: without it the block still links and the members sit
/// at offsets nobody wrote to.
library;

import 'package:flutter3d_webgl/src/glsl_translate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('includes', () {
    test('a header is pulled in where it is named', () {
      const sources = <String, String>{'lib/color.glsl': 'float Half() { return 0.5; }'};
      final out = resolveIncludes(
        '#include <lib/color.glsl>\nvoid main() {}',
        sources,
        from: 'a.frag',
      );
      expect(out, contains('float Half()'));
      expect(out, contains('void main()'));
      expect(out, isNot(contains('#include')));
    });

    test('a header included twice appears once', () {
      // surface.glsl and material_maps.glsl both include color.glsl. Emitting
      // it twice redeclares every uniform in it, and the compile fails on the
      // duplicate rather than on anything the author did.
      const sources = <String, String>{
        'lib/color.glsl': 'uniform sampler2D tex;',
        'lib/surface.glsl': '#include <lib/color.glsl>\nfloat S() { return 1.0; }',
      };
      final out = resolveIncludes(
        '#include <lib/color.glsl>\n#include <lib/surface.glsl>',
        sources,
        from: 'a.frag',
      );
      expect('uniform sampler2D tex;'.allMatches(out).length, 1);
      expect(out, contains('float S()'));
    });

    test('a cycle names the path rather than hanging', () {
      const sources = <String, String>{
        'a.glsl': '#include <b.glsl>',
        'b.glsl': '#include <a.glsl>',
      };
      expect(
        () => resolveIncludes('#include <a.glsl>', sources, from: 'top.frag'),
        throwsA(isA<GlslTranslateError>()
            .having((e) => e.message, 'message', contains('cycle'))),
      );
    });

    test('a missing header names the file that wanted it', () {
      expect(
        () => resolveIncludes('#include <lib/gone.glsl>', const {}, from: 'a.frag'),
        throwsA(isA<GlslTranslateError>().having(
            (e) => e.message, 'message', allOf(contains('a.frag'), contains('gone')))),
      );
    });
  });

  group('dialect', () {
    test('exactly one version line, and it is first', () {
      const sources = <String, String>{
        'lib/color.glsl': '#version 460 core\nfloat C() { return 1.0; }',
      };
      final out = translateGlsl(
        '#version 460 core\n#include <lib/color.glsl>\nvoid main() {}',
        sources,
        from: 'a.frag',
        fragment: true,
      );
      expect(out.split('\n').first, '#version 300 es');
      expect('#version'.allMatches(out).length, 1,
          reason: 'a header carried its own, and ES allows one');
      expect(out, isNot(contains('460')));
    });

    test('a fragment stage declares float precision', () {
      // Not a nicety: ES has no default precision for float in a fragment
      // shader, so one without this does not compile at all.
      final out = translateGlsl('void main() {}', const {},
          from: 'a.frag', fragment: true);
      expect(out, contains('precision highp float;'));
    });

    test('a vertex stage does not', () {
      final out = translateGlsl('void main() {}', const {},
          from: 'a.vert', fragment: false);
      expect(out, isNot(contains('precision highp float;')));
    });

    test('uniform blocks are std140', () {
      final out = translateGlsl(
        'uniform FragInfo {\n  vec4 light;\n}\nfrag_info;',
        const {},
        from: 'a.frag',
        fragment: true,
      );
      expect(out, contains('layout(std140) uniform FragInfo {'));
    });

    test('a sampler is not mistaken for a block', () {
      // `uniform sampler2D base_color_texture;` is not a block, and wrapping it
      // in std140 is a compile error. The rule keys on the brace and on the
      // capitalised block name.
      final out = translateGlsl('uniform sampler2D base_color_texture;', const {},
          from: 'a.frag', fragment: true);
      expect(out, contains('uniform sampler2D base_color_texture;'));
      expect(out, isNot(contains('std140')));
    });

    test('the first fragment output gets a location', () {
      // The engine's second attachment already declares location 1. In ES an
      // unqualified output beside a qualified one is a link error.
      final out = translateGlsl(
        'out vec4 frag_color;\nlayout(location = 1) out vec4 frag_surface;',
        const {},
        from: 'a.frag',
        fragment: true,
      );
      expect(out, contains('layout(location = 0) out vec4 frag_color;'));
      expect(out, contains('layout(location = 1) out vec4 frag_surface;'));
      expect('location = 1'.allMatches(out).length, 1,
          reason: 'the already-qualified output must be left alone');
    });

    test('a vertex out is left alone', () {
      // `out` in a vertex stage is a varying, not an attachment, and giving it
      // a location number would mean something else entirely.
      final out = translateGlsl('out vec3 v_normal;', const {},
          from: 'a.vert', fragment: false);
      expect(out, contains('out vec3 v_normal;'));
      expect(out, isNot(contains('location = 0')));
    });
  });
}
