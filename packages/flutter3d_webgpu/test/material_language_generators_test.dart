/// A material written as source goes through the generators the backends
/// already use — `gfx-84n`.
///
///     flutter test test/material_language_generators_test.dart
///
/// **This is the half of the row's acceptance that cannot be checked in the
/// package the language lives in.** `flutter3d_core` can say the emitter wrote
/// the text it meant to; only the backends can say that text is something they
/// can compile. So this file emits a material, resolves its headers against
/// the real `flutter3d_shaders` tree, and puts the result through both pure
/// generators: `translateGlsl` — WebGL2's, GLSL ES 3.00 — and `prepareStage` —
/// WebGPU's, the edits glslang needs before naga sees it. A construct the
/// language allowed and a generator cannot carry fails here rather than in a
/// browser.
///
/// **Here rather than in `flutter3d_webgl`** because this is the one package
/// that already has both: its own generator, and the other backend's as a dev
/// dependency, for exactly the reason its `prepareStage` gives — two answers
/// to "which headers does this shader pull in" would drift where neither side
/// could see it.
///
/// **Impeller is the one not exercised.** `impellerc` is a binary out of the
/// Flutter SDK's artifact cache, and `build_shaders_test.dart` next door stubs
/// it rather than depending on a machine having it. What this file can say is
/// that the emitted text is the same shape as every `.frag` that binary
/// already compiles — the same `#version`, the same one header, the same
/// prototypes — and that is stated rather than proved.
library;

import 'package:flutter3d_core/formats.dart';
// The include resolver, and only the include resolver — the same
// `implementation_imports` `tool/generate_shaders.dart` takes, for the same
// reason.
// ignore: implementation_imports
import 'package:flutter3d_webgl/src/glsl_translate.dart';
import 'package:flutter3d_webgpu/src/glsl_to_wgsl.dart';
import 'package:flutter3d_webgpu/src/source_package.dart';
import 'package:flutter_test/flutter_test.dart';

/// Everything the language has: a texture, a parameter of each shape, a
/// swizzle, a call, arithmetic that broadcasts a float across a vector.
///
/// One material rather than several, on purpose — a generator that chokes does
/// so on a construct, and a material using all of them is the shortest thing
/// that reaches every construct.
const String _source = '''
material RimLight {
  param float rimPower = 2.0;
  param vec3 rimColor = vec3(0.2, 0.6, 1.0);
  texture base = base_color_texture;

  fragment {
    let facing = clamp(nDotV, 0.0, 1.0);
    let rim = pow(1.0 - facing, rimPower);
    let texel = sample(base, uv);
    let tinted = albedo * texel.rgb * (1.0 - rim);
    let scrolled = fract(uv.x + world.y);
    return vec4(tinted + rimColor * rim * scrolled, alpha * texel.a);
  }
}
''';

void main() {
  final shaders = loadShaders();
  final glsl = emitMaterialFragment(
    specialiseMaterial(
      parseMaterial(_source),
      const MaterialVariant('RimLight'),
    ),
  );
  // The name a generated material would be written under, which is what the
  // include resolver reports a bad `#include` against.
  const from = 'lighting/rim_light.frag';
  final resolved = resolveIncludes(glsl, shaders.sources, from: from);

  test('the emitted shader is the shape the build already compiles', () {
    expect(glsl, startsWith('#version 460 core'));
    expect(glsl, contains('#include <lib/surface.glsl>'));
    // A material must not reach for either of these: the engine's uniform
    // blocks are frozen by offset agreement across four backends, and
    // `surface.glsl` already declares the samplers the engine binds.
    expect(glsl, isNot(contains('uniform ')));
    expect(glsl, contains('Surface s = ReadSurface();'));
    expect(glsl, contains('WriteSurface(result.rgb, result.a);'));
  });

  test('its headers resolve against the real shader tree', () {
    // Which is the first thing that would fail if the emitter named a header
    // that does not exist, or read a surface field under a name the struct
    // does not have.
    expect(resolved, contains('struct Surface'));
    expect(resolved, isNot(contains('#include')));
    for (final field in <String>['s.albedo', 's.n_dot_v', 'v_texcoord']) {
      expect(resolved, contains(field), reason: field);
    }
  });

  test('WebGL2\'s generator carries it', () {
    final translated = translateGlsl(
      glsl,
      shaders.sources,
      from: from,
      fragment: true,
    );
    expect(translated, startsWith('#version 300 es'));
    // The rules that file exists for, applied to a generated shader the same
    // way they are to a hand-written one.
    expect(translated, contains('layout(std140) uniform FragInfo'));
    expect(translated, isNot(contains('#version 460')));
    expect(translated, contains('texture(base_color_texture'));
  });

  test('WebGPU\'s generator carries it', () {
    final varyings = assignVaryingLocations(<Set<String>>[
      scanVaryings(resolved, from: from, fragment: true),
    ]);
    final prepared = prepareStage(
      resolved,
      from: from,
      fragment: true,
      varyingLocations: varyings,
    );

    // What that generator's whole job is: every block and sampler given a set
    // and a binding, and every varying a location, because glslang in Vulkan
    // mode will not infer any of them.
    expect(prepared.blocks, isNotEmpty);
    expect(
      prepared.samplers.map((s) => s.name),
      contains('base_color_texture'),
      reason: 'the material samples it and nothing gave it a binding',
    );
    expect(prepared.glsl, contains('layout(set = '));
  });

  test('a material that samples nothing still carries', () {
    // The other end of the range: the smallest legal material. A generator
    // that needed a sampler to exist, or a block, would fail here and nowhere
    // else.
    final plain = emitMaterialFragment(
      specialiseMaterial(
        parseMaterial(
          'material Flat { fragment { return vec4(albedo, alpha); } }',
        ),
        const MaterialVariant('Flat'),
      ),
    );
    expect(
      translateGlsl(plain, shaders.sources, from: from, fragment: true),
      startsWith('#version 300 es'),
    );
    final plainResolved = resolveIncludes(plain, shaders.sources, from: from);
    expect(
      prepareStage(
        plainResolved,
        from: from,
        fragment: true,
        varyingLocations: assignVaryingLocations(<Set<String>>[
          scanVaryings(plainResolved, from: from, fragment: true),
        ]),
      ).glsl,
      contains('layout(set = '),
    );
  });
}
