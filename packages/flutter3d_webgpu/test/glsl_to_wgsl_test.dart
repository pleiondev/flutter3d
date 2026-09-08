/// What the preparation does to a shader's declarations, and what it leaves
/// alone.
///
/// Pure text on both sides — neither compiler is run here. The half that runs
/// them is `wgsl_pipeline_test.dart`, which asks a different question: this
/// file asks whether the right edit was made, and that one asks whether the
/// edit compiles.
///
/// **On the VM only, and only to keep the browser run honest.** Nothing here
/// needs a browser and the translation is text either way, so a second
/// compilation of it buys nothing; what the browser run does have to compile is
/// the shipped table and the codec, and `engine_shaders_test.dart` and
/// `webgpu_bundle_section_test.dart` are on both platforms for exactly that.
@TestOn('vm')
library;

// ignore: implementation_imports
import 'package:flutter3d_webgl/src/glsl_translate.dart';
import 'package:flutter3d_webgpu/src/glsl_to_wgsl.dart';
import 'package:flutter_test/flutter_test.dart';

/// Includes resolved and then the stage prepared, the way
/// `tool/generate_shaders.dart` does it in two steps.
///
/// `prepareStage` takes text with the headers already in it, so that the file
/// it lives in imports nothing but Dart core — the resolver belongs to the
/// WebGL2 backend, which is a dev dependency here and may not be reached from
/// `lib/`.
PreparedStage prepare(
  String source, {
  Map<String, String> sources = const <String, String>{},
  required String from,
  required bool fragment,
  required Map<String, int> varyingLocations,
}) => prepareStage(
  resolveIncludes(source, sources, from: from),
  from: from,
  fragment: fragment,
  varyingLocations: varyingLocations,
);

void main() {
  // Most cases below have a varying or two and no pair for them to agree with,
  // so they share one numbering wide enough to name every varying this file
  // writes. The cases that are *about* the numbering build their own, over both
  // sides of the pair, the way `generate_shaders.dart` builds it over the
  // manifest.
  final locations = assignVaryingLocations(<Set<String>>[
    <String>{'v_texcoord'},
    <String>{'v_ray'},
    <String>{'v_a', 'v_z'},
  ]);

  group('the sampler split', () {
    test('rewrites the declaration and not the call', () {
      final prepared = prepare(
        '#version 460 core\n'
        'uniform sampler2D base_color_texture;\n'
        'in vec2 v_texcoord;\n'
        'out vec4 frag_color;\n'
        'void main() {\n'
        '  frag_color = texture(base_color_texture, v_texcoord);\n'
        '}\n',
        sources: const <String, String>{},
        from: 'a.frag',
        fragment: true,
        varyingLocations: locations,
      );

      expect(
        prepared.glsl,
        contains('uniform texture2D base_color_texture_tex;'),
      );
      expect(
        prepared.glsl,
        contains('uniform sampler base_color_texture_smp;'),
      );
      expect(
        prepared.glsl,
        contains(
          '#define base_color_texture '
          'sampler2D(base_color_texture_tex, base_color_texture_smp)',
        ),
      );
      // The whole reason the split is done by macro: the call site is the same
      // text it was. Fifty-nine of these survive the manifest untouched, and
      // none of them is at risk of being rewritten wrongly because none of
      // them is rewritten.
      expect(
        prepared.glsl,
        contains('texture(base_color_texture, v_texcoord)'),
      );
    });

    test('spells a cube sampler as a cube', () {
      final prepared = prepare(
        '#version 460 core\n'
        'uniform samplerCube sky_texture;\n'
        'in vec3 v_ray;\n'
        'out vec4 frag_color;\n'
        'void main() { frag_color = texture(sky_texture, v_ray); }\n',
        sources: const <String, String>{},
        from: 'a.frag',
        fragment: true,
        varyingLocations: locations,
      );

      expect(prepared.glsl, contains('uniform textureCube sky_texture_tex;'));
      expect(prepared.glsl, contains('#define sky_texture samplerCube('));
      expect(prepared.samplers.single.dimension, kCubeDimension);
    });

    test('takes two bindings, texture first', () {
      final prepared = prepare(
        '#version 460 core\n'
        'uniform sampler2D b_texture;\n'
        'uniform sampler2D a_texture;\n'
        'out vec4 frag_color;\n'
        'void main() { frag_color = vec4(0.0); }\n',
        sources: const <String, String>{},
        from: 'a.frag',
        fragment: true,
        varyingLocations: locations,
      );

      // Sorted by name, so the declaration order above is not the binding
      // order below.
      expect(prepared.samplers.map((s) => s.name), <String>[
        'a_texture',
        'b_texture',
      ]);
      expect(prepared.samplers[0].textureBinding, 0);
      expect(prepared.samplers[0].samplerBinding, 1);
      expect(prepared.samplers[1].textureBinding, 2);
      expect(prepared.samplers[1].samplerBinding, 3);
      expect(prepared.samplers.every((s) => s.group == kFragmentGroup), isTrue);
    });

    test('asks for the samplerless extension only when something needs it', () {
      const declarations =
          '#version 460 core\n'
          'uniform sampler2D probe_texture;\n'
          'out vec4 frag_color;\n';
      const extension =
          '#extension GL_EXT_samplerless_texture_functions : require';

      final sampled = prepare(
        '$declarations'
        'void main() { frag_color = texture(probe_texture, vec2(0.0)); }\n',
        sources: const <String, String>{},
        from: 'a.frag',
        fragment: true,
        varyingLocations: locations,
      );
      expect(sampled.glsl, isNot(contains(extension)));

      final fetched = prepare(
        '$declarations'
        'void main() { frag_color = texelFetch(probe_texture, ivec2(0), 0); }\n',
        sources: const <String, String>{},
        from: 'a.frag',
        fragment: true,
        varyingLocations: locations,
      );
      expect(fetched.glsl, contains(extension));
      // After the version line and before anything else, which is the only
      // place GLSL accepts one.
      expect(fetched.glsl.indexOf(extension), greaterThan(0));
      expect(
        fetched.glsl.indexOf(extension),
        lessThan(fetched.glsl.indexOf('uniform')),
      );
    });
  });

  group('uniform blocks', () {
    test('get a set, a binding and std140', () {
      final prepared = prepare(
        '#version 460 core\n'
        'uniform FrameInfo {\n'
        '  mat4 mvp;\n'
        '  vec4 tint;\n'
        '}\n'
        'frame_info;\n'
        'in vec3 position;\n'
        'void main() { gl_Position = frame_info.mvp * vec4(position, 1.0); }\n',
        sources: const <String, String>{},
        from: 'a.vert',
        fragment: false,
        varyingLocations: locations,
      );

      expect(
        prepared.glsl,
        contains('layout(set = 0, binding = 0, std140) uniform FrameInfo {'),
      );
      final block = prepared.blocks.single;
      expect(block.name, 'FrameInfo');
      expect(block.group, kVertexGroup);
      expect(block.binding, 0);
      expect(block.sizeInBytes, 80);
      expect(
        block.members.map((m) => (m.name, m.offsetInBytes, m.sizeInBytes)),
        <(String, int, int)>[('mvp', 0, 64), ('tint', 64, 16)],
      );
    });

    test('lay arrays out at a vec4 stride', () {
      final prepared = prepare(
        '#version 460 core\n'
        '#define kMaxLights 8\n'
        'const int kSlots = 6;\n'
        'uniform FragInfo {\n'
        '  vec4 light_position[kMaxLights];\n'
        '  mat4 faces[6 * kSlots];\n'
        '  vec4 params;\n'
        '}\n'
        'frag_info;\n'
        'out vec4 frag_color;\n'
        'void main() { frag_color = frag_info.params; }\n',
        sources: const <String, String>{},
        from: 'a.frag',
        fragment: true,
        varyingLocations: locations,
      );

      final block = prepared.blocks.single;
      expect(
        block.members.map((m) => (m.name, m.offsetInBytes, m.sizeInBytes)),
        <(String, int, int)>[
          ('light_position', 0, 128),
          ('faces', 128, 2304),
          ('params', 2432, 16),
        ],
      );
      expect(block.sizeInBytes, 2448);
    });

    test('refuse a member with no std140 rule', () {
      expect(
        () => prepare(
          '#version 460 core\n'
          'uniform Odd {\n'
          '  dmat4 wide;\n'
          '}\n'
          'odd;\n'
          'out vec4 frag_color;\n'
          'void main() { frag_color = vec4(0.0); }\n',
          sources: const <String, String>{},
          from: 'a.frag',
          fragment: true,
          varyingLocations: locations,
        ),
        throwsA(isA<WgslPrepareError>()),
      );
    });
  });

  group('varyings', () {
    // The trap this whole rule exists for. Both stages take `v_color` and
    // `v_normal` from one header; the fragment shader declares one of its own
    // before including it. Under declaration order that shifts the fragment
    // side by one and leaves the vertex side alone — and WebGPU does not link,
    // so nothing would say so. Under a name the numbering cannot move.
    const header = 'in_out vec4 v_color;\nin_out vec3 v_normal;\n';
    final sources = <String, String>{
      'lib/varyings.glsl': header.replaceAll('in_out', 'out'),
      'lib/varyings_in.glsl': header.replaceAll('in_out', 'in'),
    };
    const vertexSource =
        '#version 460 core\n'
        'in vec3 position;\n'
        '#include <lib/varyings.glsl>\n'
        'void main() { gl_Position = vec4(position, 1.0); }\n';
    // The one that declares something of its own before the include.
    const fragmentSource =
        '#version 460 core\n'
        'in vec2 v_after_all;\n'
        '#include <lib/varyings_in.glsl>\n'
        'out vec4 frag_color;\n'
        'void main() { frag_color = v_color; }\n';

    ({String vertex, String fragment}) pair() {
      final numbering = assignVaryingLocations(<Set<String>>[
        scanVaryings(
          resolveIncludes(vertexSource, sources, from: 'a.vert'),
          from: 'a.vert',
          fragment: false,
        ),
        scanVaryings(
          resolveIncludes(fragmentSource, sources, from: 'a.frag'),
          from: 'a.frag',
          fragment: true,
        ),
      ]);
      return (
        vertex: prepare(
          vertexSource,
          sources: sources,
          from: 'a.vert',
          fragment: false,
          varyingLocations: numbering,
        ).glsl,
        fragment: prepare(
          fragmentSource,
          sources: sources,
          from: 'a.frag',
          fragment: true,
          varyingLocations: numbering,
        ).glsl,
      );
    }

    test('get the same location on both sides of a pair', () {
      final both = pair();
      for (final name in <String>['v_color', 'v_normal']) {
        final inVertex = RegExp(
          '${r'layout\(location = (\d+)\) out \w+ '}$name;',
        ).firstMatch(both.vertex);
        final inFragment = RegExp(
          '${r'layout\(location = (\d+)\) in \w+ '}$name;',
        ).firstMatch(both.fragment);
        expect(inVertex, isNotNull, reason: '$name is not in the vertex stage');
        expect(
          inFragment,
          isNotNull,
          reason: '$name is not in the fragment stage',
        );
        expect(
          inFragment!.group(1),
          inVertex!.group(1),
          reason: '$name landed on two different locations',
        );
      }
    });

    test('are numbered by name and not by where they were written', () {
      final both = pair();
      // v_after_all sorts first and takes 0, which is exactly the shift that
      // would have gone unnoticed. v_color and v_normal take 1 and 2 — on both
      // sides, because the numbering is over the pair and not over one file's
      // declarations.
      expect(
        both.fragment,
        contains('layout(location = 0) in vec2 v_after_all;'),
      );
      expect(both.fragment, contains('layout(location = 1) in vec4 v_color;'));
      expect(both.vertex, contains('layout(location = 1) out vec4 v_color;'));
      expect(both.vertex, contains('layout(location = 2) out vec3 v_normal;'));
    });

    test('are numbered per family, so unrelated sets do not add up', () {
      // The reason the numbering is not one flat sorted list: seventeen
      // varyings in the manifest and sixteen locations in WebGPU. Two names
      // only have to agree when some stage declares both, so names that never
      // meet are numbered apart and neither family runs out.
      final numbering = assignVaryingLocations(<Set<String>>[
        <String>{'v_normal', 'v_texcoord'},
        <String>{'v_ray', 'v_zenith'},
      ]);
      expect(numbering, <String, int>{
        'v_normal': 0,
        'v_texcoord': 1,
        'v_ray': 0,
        'v_zenith': 1,
      });
    });

    test('join two families the moment one stage declares both', () {
      final numbering = assignVaryingLocations(<Set<String>>[
        <String>{'v_normal', 'v_texcoord'},
        <String>{'v_ray', 'v_zenith'},
        <String>{'v_texcoord', 'v_ray'},
      ]);
      expect(numbering.values.toSet().length, 4);
    });

    test('refuse a family wider than WebGPU has locations for', () {
      expect(
        () => assignVaryingLocations(<Set<String>>[
          <String>{for (var i = 0; i <= kMaxInterStageVariables; i++) 'v_$i'},
        ]),
        throwsA(isA<WgslPrepareError>()),
      );
    });

    test('refuse a varying the numbering never saw', () {
      expect(
        () => prepare(
          vertexSource,
          sources: sources,
          from: 'a.vert',
          fragment: false,
          varyingLocations: const <String, int>{},
        ),
        throwsA(isA<WgslPrepareError>()),
      );
    });
  });

  group('vertex inputs and fragment outputs', () {
    test('keep a location they already declare', () {
      final prepared = prepare(
        '#version 460 core\n'
        'layout(location = 3) in vec2 position;\n'
        'in vec3 corner_ray;\n'
        'void main() { gl_Position = vec4(position, 0.0, 1.0); }\n',
        sources: const <String, String>{},
        from: 'a.vert',
        fragment: false,
        varyingLocations: locations,
      );

      expect(
        prepared.attributes.map((a) => (a.name, a.location, a.format)),
        <(String, int, String)>[
          ('position', 3, 'float32x2'),
          ('corner_ray', 0, 'float32x3'),
        ],
      );
    });

    test(
      'put the unqualified output at the free slot beside a declared one',
      () {
        final prepared = prepare(
          '#version 460 core\n'
          'out vec4 frag_color;\n'
          'layout(location = 1) out vec4 frag_surface;\n'
          'void main() { frag_color = vec4(0.0); frag_surface = vec4(0.0); }\n',
          sources: const <String, String>{},
          from: 'a.frag',
          fragment: true,
          varyingLocations: locations,
        );

        expect(
          prepared.glsl,
          contains('layout(location = 0) out vec4 frag_color;'),
        );
        expect(
          prepared.glsl,
          contains('layout(location = 1) out vec4 frag_surface;'),
        );
      },
    );

    test('refuse an attribute type the contract has no format for', () {
      expect(
        () => prepare(
          '#version 460 core\n'
          'in mat4 transform;\n'
          'void main() { gl_Position = transform[0]; }\n',
          sources: const <String, String>{},
          from: 'a.vert',
          fragment: false,
          varyingLocations: locations,
        ),
        throwsA(isA<WgslPrepareError>()),
      );
    });
  });

  group('the preprocessor', () {
    // The failure this evaluation exists to stop: `lighting/unlit.frag` defines
    // `F3D_NO_POINT_SHADOW` before including `lib/surface.glsl`, and the block
    // and sampler behind that guard are not in the shader glslang compiles. A
    // reflection listing them would have the engine bind a slot that is not
    // there — a native crash inside Metal on one backend, and a draw discarded
    // with nothing logged on another. Both are written up in that header.
    const guarded =
        'uniform sampler2D shadow_texture;\n'
        '#ifndef NO_SHADOW\n'
        'uniform sampler2D point_shadow_texture;\n'
        'uniform PointShadow {\n'
        '  vec4 params;\n'
        '}\n'
        'point_shadow;\n'
        '#endif\n'
        'out vec4 frag_color;\n'
        'void main() { frag_color = vec4(0.0); }\n';

    test('keeps what a live branch declares', () {
      final prepared = prepare(
        '#version 460 core\n$guarded',
        sources: const <String, String>{},
        from: 'a.frag',
        fragment: true,
        varyingLocations: locations,
      );
      expect(prepared.blocks.map((b) => b.name), <String>['PointShadow']);
      expect(prepared.samplers.map((s) => s.name), <String>[
        'point_shadow_texture',
        'shadow_texture',
      ]);
    });

    test('drops what a dead branch declares', () {
      final prepared = prepare(
        '#version 460 core\n#define NO_SHADOW\n$guarded',
        sources: const <String, String>{},
        from: 'a.frag',
        fragment: true,
        varyingLocations: locations,
      );
      expect(prepared.blocks, isEmpty);
      expect(prepared.samplers.map((s) => s.name), <String>['shadow_texture']);
      // And the one that is left starts at binding zero, rather than at the
      // number it would have had if the dead branch had been counted.
      expect(prepared.samplers.single.textureBinding, 0);
    });

    test('takes the other half of an #else', () {
      final prepared = prepare(
        '#version 460 core\n'
        '#define NO_SHADOW\n'
        '#ifndef NO_SHADOW\n'
        'uniform sampler2D taken;\n'
        '#else\n'
        'uniform sampler2D instead;\n'
        '#endif\n'
        'out vec4 frag_color;\n'
        'void main() { frag_color = vec4(0.0); }\n',
        sources: const <String, String>{},
        from: 'a.frag',
        fragment: true,
        varyingLocations: locations,
      );
      expect(prepared.samplers.single.name, 'instead');
    });

    test('refuses a conditional it cannot evaluate', () {
      // An `#if` takes an expression, and an evaluator for it would be a second
      // GLSL preprocessor written on the assumption nobody will use it in
      // anger. Stopping is the honest answer.
      expect(
        () => prepare(
          '#version 460 core\n'
          '#if 1\n'
          'uniform sampler2D maybe;\n'
          '#endif\n'
          'out vec4 frag_color;\n'
          'void main() { frag_color = vec4(0.0); }\n',
          sources: const <String, String>{},
          from: 'a.frag',
          fragment: true,
          varyingLocations: locations,
        ),
        throwsA(isA<WgslPrepareError>()),
      );
    });

    test('refuses a conditional nobody closed', () {
      expect(
        () => prepare(
          '#version 460 core\n'
          '#ifndef SOMETHING\n'
          'out vec4 frag_color;\n'
          'void main() { frag_color = vec4(0.0); }\n',
          sources: const <String, String>{},
          from: 'a.frag',
          fragment: true,
          varyingLocations: locations,
        ),
        throwsA(isA<WgslPrepareError>()),
      );
    });
  });

  test('leaves exactly one version line, first', () {
    final prepared = prepare(
      '#version 460 core\n'
      '#include <lib/header.glsl>\n'
      'out vec4 frag_color;\n'
      'void main() { frag_color = vec4(0.0); }\n',
      sources: const <String, String>{
        'lib/header.glsl': '#version 460 core\nconst int k = 1;\n',
      },
      from: 'a.frag',
      fragment: true,
      varyingLocations: locations,
    );

    expect('#version'.allMatches(prepared.glsl).length, 1);
    expect(prepared.glsl.startsWith('#version 460 core\n'), isTrue);
  });

  test('is the same twice over one source', () {
    // The freshness step in `tool/ci.sh` regenerates the table and diffs it. A
    // numbering that depended on a hash seed or on map iteration would fail
    // that step on a day nothing had changed, and the failure would look like a
    // shader problem rather than like a build problem.
    const source =
        '#version 460 core\n'
        'uniform sampler2D z_texture;\n'
        'uniform sampler2D a_texture;\n'
        'uniform Zeta {\n  vec4 one;\n}\nzeta;\n'
        'uniform Alpha {\n  vec4 two;\n}\nalpha;\n'
        'in vec2 v_z;\n'
        'in vec2 v_a;\n'
        'out vec4 frag_color;\n'
        'void main() { frag_color = vec4(0.0); }\n';

    String once() => prepare(
      source,
      sources: const <String, String>{},
      from: 'a.frag',
      fragment: true,
      varyingLocations: locations,
    ).glsl;

    expect(once(), once());
    expect(
      once(),
      contains('layout(set = 1, binding = 0, std140) uniform Alpha {'),
    );
    expect(
      once(),
      contains('layout(set = 1, binding = 1, std140) uniform Zeta {'),
    );
    expect(once(), contains('layout(location = 0) in vec2 v_a;'));
  });
}
