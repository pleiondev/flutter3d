/// A material as WGSL at run time: its body spliced into a host stage.
///
///     dart test test/material_wgsl_test.dart
///
/// The host here is a stand-in shaped as naga writes the engine's `Unlit`
/// stage — the names, the private varyings, `main_1` — so this package's
/// tests need no Flutter. `flutter3d_webgpu`'s `runtime_material_test.dart`
/// splices into the real one and has naga validate the result.
library;

import 'dart:convert';

import 'package:flutter3d_core/flutter3d_core.dart'
    show MaterialVariant, parseMaterial, specializeMaterial;
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_plugin_runtime/flutter3d_plugin_runtime.dart';
import 'package:flutter3d_shaders/translate.dart';
import 'package:test/test.dart';

const String _hostWgsl = r'''
struct Surface {
    albedo: vec3<f32>,
    alpha: f32,
    n: vec3<f32>,
    v: vec3<f32>,
    n_dot_v: f32,
    metallic: f32,
    roughness: f32,
    occlusion: f32,
    emissive: vec3<f32>,
    ambient: vec3<f32>,
    exposure: f32,
}

struct FragInfo {
    base_color: vec4<f32>,
}

var<private> g_albedo: vec3<f32>;
var<private> g_premultiply: bool;
@group(1) @binding(0)
var<uniform> frag_info: FragInfo;
var<private> v_world_position_1: vec3<f32>;
var<private> frag_color: vec4<f32>;
@group(1) @binding(1)
var base_color_texture_tex: texture_2d<f32>;
@group(1) @binding(2)
var base_color_texture_smp: sampler;
var<private> v_texcoord_1: vec2<f32>;

fn ReadSurface_u0028_() -> Surface {
    var s_1: Surface;
    s_1.albedo = frag_info.base_color.xyz;
    return s_1;
}

fn WriteSurface_u0028_vf3_u003b_f1_u003b_f1_u003b(c: ptr<function, vec3<f32>>, a: ptr<function, f32>, r: ptr<function, f32>) {
    frag_color = vec4<f32>((*c), (*a));
    return;
}

fn WriteSurface_u0028_vf3_u003b_f1_u003b(c_1: ptr<function, vec3<f32>>, a_1: ptr<function, f32>) {
    var r_1: f32 = 1f;
    WriteSurface_u0028_vf3_u003b_f1_u003b_f1_u003b(c_1, a_1, (&r_1));
    return;
}

fn main_1() {
    var s_2: Surface;
    var param: vec3<f32>;

    g_albedo = vec3<f32>(0f, 0f, 0f);
    g_premultiply = false;
    let _e94 = ReadSurface_u0028_();
    s_2 = _e94;
    if true {
        return;
    }
    return;
}

@fragment
fn main(@location(5) v_texcoord: vec2<f32>, @location(7) v_world_position: vec3<f32>) -> @location(0) vec4<f32> {
    v_texcoord_1 = v_texcoord;
    v_world_position_1 = v_world_position;
    main_1();
    let _e3 = frag_color;
    return _e3;
}
''';

final PackedStage _host = (
  wgsl: _hostWgsl,
  prepared: const PreparedStage(
    glsl: '',
    attributes: <PreparedAttribute>[],
    blocks: <PreparedBlock>[
      (
        name: 'FragInfo',
        group: 1,
        binding: 0,
        sizeInBytes: 16,
        members: <PreparedMember>[
          (name: 'base_color', offsetInBytes: 0, sizeInBytes: 16),
        ],
      ),
    ],
    samplers: <PreparedSampler>[
      (
        name: 'base_color_texture',
        group: 1,
        textureBinding: 1,
        samplerBinding: 2,
        dimension: twoDimensional,
      ),
    ],
  ),
);

const String _glow = '''
material Glow {
  param vec3 tint = vec3(1.0, 0.6, 0.2);
  uniform float pulse = 0.5;
  uniform vec3 rim = vec3(0.1, 0.2, 0.3);
  texture base = base_color_texture;
  fragment {
    let t = sample(base, uv);
    let f = pow(1.0 - clamp(nDotV, 0.0, 1.0), 3.0);
    let c = mix(albedo * tint, rim, f) * pulse + t.rgb * 0.5;
    return vec4(clamp(c + vec3(world.x, 0.0, -1.5), 0.0, 4.0), alpha);
  }
}
''';

PackedStage _splice(String source) => spliceMaterialWgsl(
  specializeMaterial(parseMaterial(source), MaterialVariant('M')),
  _host,
  from: 'm.f3dmat',
);

Matcher _refusal(String saying) => throwsA(
  isA<RuntimeShadersException>().having(
    (e) => e.message,
    'message',
    contains(saying),
  ),
);

void main() {
  test('the body replaces main_1, and everything else is the host\'s', () {
    // Mutation: append the body beside the host's main_1, or drop the
    // global initialisers naga moved into it. The first leaves two main_1s;
    // the second leaves g_premultiply unset where the host's WriteSurface
    // reads it.
    final wgsl = _splice(_glow).wgsl;
    expect(RegExp(r'fn main_1\(\)').allMatches(wgsl), hasLength(1));
    expect(wgsl, contains('g_premultiply = false;'));
    expect(wgsl, contains('var f3d_s: Surface = ReadSurface_u0028_();'));
    expect(
      wgsl,
      isNot(contains('if true')),
      reason: 'the host\'s main is gone',
    );
    expect(wgsl, contains('fn ReadSurface_u0028_() -> Surface {'));
    expect(
      wgsl,
      contains(
        'WriteSurface_u0028_vf3_u003b_f1_u003b((&f3d_rgb), (&f3d_alpha));',
      ),
    );
    expect(wgsl, contains('@fragment'), reason: 'the entry point is kept');
  });

  test('every input, builtin and texture reads what the host has', () {
    final wgsl = _splice(_glow).wgsl;
    expect(
      wgsl,
      contains(
        'textureSample(base_color_texture_tex, base_color_texture_smp, '
        'v_texcoord_1)',
      ),
    );
    expect(wgsl, contains('f3d_s.n_dot_v'));
    expect(wgsl, contains('v_world_position_1.x'));
    // The parameter folded; a float spread beside a vector, as WGSL needs.
    expect(wgsl, contains('vec3<f32>(1.0, 0.6, 0.2)'));
    expect(wgsl, contains('clamp(f3d_s.n_dot_v, 0.0, 1.0)'));
    expect(wgsl, contains('vec3<f32>(0.0), vec3<f32>(4.0)'));
    expect(wgsl, isNot(contains('--')), reason: 'WGSL reads that as decrement');
  });

  test('uniforms are a block at the next binding, laid out as std140', () {
    // Mutation: number the block from the host's blocks alone. It would take
    // binding 1, which is the host's texture.
    final stage = _splice(_glow);
    final block = stage.prepared.blocks.last;
    expect(block.name, 'MaterialParams');
    expect((block.group, block.binding), (1, 3));
    expect(
      block.members.map((m) => (m.name, m.offsetInBytes, m.sizeInBytes)),
      <(String, int, int)>[('pulse', 0, 4), ('rim', 16, 12)],
    );
    expect(block.sizeInBytes, 32);
    expect(stage.wgsl, contains('@group(1) @binding(3)'));
    expect(stage.wgsl, contains('var<uniform> f3d_material_params'));
    expect(stage.wgsl, contains('f3d_material_params.m_pulse'));
    expect(stage.prepared.samplers, _host.prepared.samplers);
  });

  test('a material past the limits is refused, saying which', () {
    expect(
      () => _splice('''
material Toon {
  light {
    return albedo * floor(nDotL * 3.0) / 3.0;
  }
  fragment {
    return vec4(lit, alpha);
  }
}
'''),
      _refusal('light block'),
    );
    expect(
      () => _splice('''
material Tinted {
  fragment {
    return vec4(instance.rgb, 1.0);
  }
}
'''),
      _refusal('instance'),
    );
    expect(
      () => _splice('''
material Bumpy {
  texture bump = normal_texture;
  fragment {
    return vec4(sample(bump, uv).rgb, 1.0);
  }
}
'''),
      _refusal('normal_texture'),
    );
  });

  test(
    'RuntimeShaders hands WebGPU a section with the material in it',
    () async {
      // Mutation: put the WGSL in the WebGL2 section, or leave the material
      // section out. The WebGPU device reads `webgpu`; the lighting model is
      // built from `material`.
      final bundle = runtimeMaterialBundle(
        _glow,
        backend: 'WebGPU',
        from: 'glow.f3dmat',
        webGpuHost: _host,
      );
      expect(bundle.sections.keys, <String>[
        ShaderBundle.webgpuSection,
        ShaderBundle.materialSection,
      ]);
      final section = bundle.sections[ShaderBundle.webgpuSection]!;
      final document =
          jsonDecode(
                utf8.decode(
                  section.buffer.asUint8List(
                    section.offsetInBytes,
                    section.lengthInBytes,
                  ),
                ),
              )
              as Map<String, Object?>;
      expect(document['version'], sectionVersion);
      final glow = (document['fragment']! as Map<String, Object?>)['Glow']!;
      expect(
        (glow as Map<String, Object?>)['wgsl'],
        contains('f3d_material_params'),
      );

      final shaders = RuntimeShaders(
        backend: RuntimeBackends.webgpu,
        loadShaders: (bytes) async => throw StateError('no device here'),
        addMaterials: (_) => Registration(() {}),
      );
      shaders.addMaterial(_glow, from: 'glow.f3dmat');
      expect(shaders.statuses['Glow'], contains('webGpuHost'));
    },
  );
}
