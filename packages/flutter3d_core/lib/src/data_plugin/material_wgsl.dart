/// A material written in the material language, as WGSL, while the game
/// runs in a browser — item 4 of `tasks/1.0-scope-additions.md`.
///
/// ## Why a splice, and not the build's road
///
/// The build makes WGSL from GLSL with two programs, glslang and naga
/// (`flutter3d_shaders`' `glsl_to_wgsl.dart` prepares the GLSL, they compile
/// it), and a game ships neither: there is no `Process` in a browser and no
/// SPIR-V a `GPUDevice` would take. What a game does ship is the engine's own
/// stages, already compiled by that road — `flutter3d_webgpu`'s
/// `webGpuEngineShaders` — and the material language's body is small: lets and a
/// return, over the surface the engine already read, through sixteen
/// builtins that WGSL has under the same names.
///
/// So a material without a `light` block is the engine's `Unlit` stage with
/// its `main` replaced. `unlit.frag` and the GLSL `emitMaterialFragment`
/// writes for such a material include the same header with the same two
/// switches and differ only in `main`, which is `ReadSurface`, the body, and
/// `WriteSurface`. The surface, the fog, the transparency weights, the
/// G-buffer writes and every binding stay what naga compiled; only the body
/// is written here, from the same tree the GLSL emitter and the software
/// backend's evaluator read.
///
/// ## The limits, each refused with its reason
///
/// * **A `light` block.** A lit material is `ShadeLight` and the light loop
///   around it, which is the engine's lit stage rewritten rather than a
///   `main` replaced. It draws on WebGL2 and the software backend at run
///   time and on WebGPU from a bundle the build made.
/// * **The `instance` input.** The varying is declared only by a stage that
///   reads it, at a location the engine's vertex stages number; the host
///   stage has no slot for it.
/// * **A texture slot the host does not bind.** `Unlit` binds
///   `base_color_texture` alone; the normal, occlusion, emissive and
///   metallic-roughness maps are a lit stage's.
///
/// Uniform parameters (`uniform` in the source) become a `MaterialParams`
/// block at the next free binding of the host's group, laid out as std140
/// lays the GLSL block out — which is how WGSL's uniform address space lays
/// out the four types the language has.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_shaders/translate.dart'
    show
        PackedStage,
        PreparedAttribute,
        PreparedBlock,
        PreparedMember,
        PreparedSampler,
        PreparedStage;

import 'runtime_shaders.dart' show RuntimeShadersException;

/// [program], already specialised, spliced into [host]'s `main` — see the
/// library comment. [from] names the source in every refusal.
///
/// Throws a [RuntimeShadersException] for a material past the limits above, and
/// for a host that is not shaped as the engine's `Unlit` stage is.
PackedStage spliceMaterialWgsl(
  MaterialProgram program,
  PackedStage host, {
  required String from,
}) {
  Never refuse(String why) => throw RuntimeShadersException('$from: $why');

  if (program.light != null) {
    refuse(
      'a material with a light block is compiled for WebGPU by the build '
      '(assets_src/), not while the game runs: at run time WebGPU takes a '
      'material that returns the light its surface emits',
    );
  }
  if (program.inputsUsed.contains('instance')) {
    refuse(
      'a material reading "instance" is compiled for WebGPU by the build '
      '(assets_src/): the stage it runs in at run time has no instance '
      'varying',
    );
  }
  // Version 2, refused for the reason the light block is: each is a stage
  // of another shape than the one spliced into.
  if (program.kind != MaterialStageKind.surface) {
    refuse(
      'a ${program.kind} stage is not spliced into a material\'s host; '
      '${program.kind == MaterialStageKind.fullscreen ? 'build it with fullscreenMaterialWgsl' : 'no GPU backend runs a compute kernel written in the language'}',
    );
  }
  if (program.vertex != null) {
    refuse(
      'a material with a vertex block is compiled for WebGPU by the build '
      '(assets_src/): at run time WebGPU has no vertex stage to splice one '
      'into, and the engine\'s mesh stages stay what they are',
    );
  }
  if (program.readsSceneDepth) {
    refuse(
      'a material reading the scene behind it is compiled for WebGPU by the '
      'build (assets_src/): the stage it runs in at run time binds no scene '
      'depth',
    );
  }

  final wgsl = host.wgsl;
  String found(RegExp pattern, String what) =>
      pattern.firstMatch(wgsl)?.group(1) ??
      refuse(
        'the WebGPU host stage has no $what; hand RuntimeShaders the '
        'engine\'s own (webGpuMaterialHost)',
      );

  final readSurface = found(
    RegExp(r'fn (ReadSurface\w*)\(\) -> Surface'),
    'ReadSurface',
  );
  final writeSurface = found(
    RegExp(
      r'fn (WriteSurface\w*)\(\w+: ptr<function, vec3<f32>>, '
      r'\w+: ptr<function, f32>\)',
    ),
    'two-argument WriteSurface',
  );
  final privates = <String>{
    for (final match in RegExp(
      r'^var<private> (\w+):',
      multiLine: true,
    ).allMatches(wgsl))
      match.group(1)!,
  };
  String varying(String glsl) {
    // Version 2's `viewDepth`, read into a local of the spliced `main`.
    if (glsl == 'f3d_view_depth') return glsl;
    final type = switch (glsl) {
      'v_texcoord' => 'vec2<f32>',
      'v_world_position' => 'vec3<f32>',
      _ => refuse('the input "$glsl" has no place in the WebGPU host stage'),
    };
    return found(
      RegExp('var<private> (${glsl}_\\d+): ${RegExp.escape(type)};'),
      'varying $glsl',
    );
  }

  // `main_1` is the GLSL `main` naga wrote; the entry point calls it.
  final start = wgsl.indexOf('fn main_1() {');
  if (start < 0) refuse('the WebGPU host stage has no main_1');
  var depth = 0;
  var end = -1;
  for (var i = wgsl.indexOf('{', start); i < wgsl.length; i++) {
    if (wgsl[i] == '{') depth++;
    if (wgsl[i] == '}' && --depth == 0) {
      end = i + 1;
      break;
    }
  }
  if (end < 0) refuse('the WebGPU host stage\'s main_1 is never closed');

  // What the GLSL's global initialisers became: naga writes them as the
  // first assignments of `main_1`, before the surface is read. Only those
  // to the module's own private variables, so nothing local is carried over.
  final prologue = <String>[
    for (final line
        in wgsl
            .substring(start, end)
            .split('\n')
            .skip(1)
            .takeWhile((l) => !l.contains(readSurface)))
      if (RegExp(r'^\s*(\w+) = [^;]*;$').firstMatch(line) case final m?
          when privates.contains(m.group(1)))
        line,
  ];

  // The texture slots, held to what the host binds.
  final bound = <String>{for (final s in host.prepared.samplers) s.name};
  for (final slot in program.textures) {
    if (!bound.contains(slot.bindingName) ||
        !wgsl.contains('var ${slot.bindingName}_tex:')) {
      refuse(
        'the texture "${slot.name}" reads ${slot.bindingName}, and the stage '
        'a material runs in on WebGPU at run time binds '
        '${bound.join(', ')}; a material sampling the others is compiled by '
        'the build (assets_src/)',
      );
    }
  }

  // The uniforms, as the block the engine binds `RenderMaterial.parameters` to.
  final uniforms = <MaterialParameter>[
    for (final parameter in program.parameters)
      if (parameter.uniform) parameter,
  ];
  final binding =
      <int>[
        for (final block in host.prepared.blocks) block.binding,
        for (final sampler in host.prepared.samplers) ...<int>[
          sampler.textureBinding,
          sampler.samplerBinding,
        ],
      ].fold(-1, (int a, int b) => a > b ? a : b) +
      1;
  final group = host.prepared.blocks.isEmpty
      ? 1
      : host.prepared.blocks.first.group;
  final params = uniforms.isEmpty
      ? null
      : _paramsBlock(uniforms, group, binding);

  final writer = _WgslWriter(
    surface: 'f3d_s',
    varying: varying,
    params: 'f3d_material_params',
  );
  final body = StringBuffer();
  for (final statement in program.body) {
    switch (statement) {
      case MaterialLet(:final name, :final value):
        body.writeln(
          '    let m_$name: ${_type(value.type)} = ${writer.expression(value)};',
        );
      case MaterialOutput():
        // Refused above: only a vertex block writes outputs.
        refuse('a vertex block has no place in a fragment stage');
      case MaterialReturn(:final value):
        body
          ..writeln(
            '    let f3d_result: vec4<f32> = ${writer.expression(value)};',
          )
          ..writeln('    var f3d_rgb: vec3<f32> = f3d_result.xyz;')
          ..writeln('    var f3d_alpha: f32 = f3d_result.w;')
          ..writeln('    $writeSurface((&f3d_rgb), (&f3d_alpha));')
          ..writeln('    return;');
    }
  }

  // Version 2: what `main` sets before the body — the blend that leaves
  // the colour as returned, and this fragment's depth along the view axis.
  final prelude = StringBuffer();
  if (program.state.blend == MaterialBlend.premultiplied) {
    final premultiply = found(
      RegExp(r'^var<private> (g_premultiply\w*): bool', multiLine: true),
      'g_premultiply',
    );
    prelude.writeln('    $premultiply = false;');
  }
  if (program.inputsUsed.contains('viewDepth')) {
    final viewDepth = found(
      RegExp(r'fn (ViewDepth\w*)\(\) -> f32'),
      'ViewDepth',
    );
    prelude.writeln('    let f3d_view_depth: f32 = $viewDepth();');
  }

  final declarations = StringBuffer();
  if (params != null) {
    declarations
      ..writeln('struct F3dMaterialParams {')
      ..writeAll(<String>[
        for (final p in uniforms) '    m_${p.name}: ${_type(p.type)},\n',
      ])
      ..writeln('}')
      ..writeln()
      ..writeln('@group($group) @binding($binding) ')
      ..writeln('var<uniform> f3d_material_params: F3dMaterialParams;')
      ..writeln();
  }
  final main = StringBuffer()
    ..writeln('// The material "${program.name}", spliced in at run time.')
    ..writeln('fn main_1() {')
    ..writeAll(<String>[for (final line in prologue) '$line\n'])
    ..writeln('    var f3d_s: Surface = $readSurface();')
    ..write(prelude)
    ..write(body)
    ..write('}');

  return (
    wgsl: '${wgsl.substring(0, start)}$declarations$main${wgsl.substring(end)}',
    prepared: PreparedStage(
      glsl: emitMaterialFragment(program),
      attributes: host.prepared.attributes,
      blocks: <PreparedBlock>[...host.prepared.blocks, ?params],
      samplers: host.prepared.samplers,
    ),
  );
}

/// A full-screen stage written in the language — version 2 — as WGSL, for a
/// plugin's render step on WebGPU while the game runs.
///
/// **Written whole rather than spliced**: a full-screen stage is the picture
/// in, its colour out, through the shared `FullscreenVertex`, with nothing of
/// the engine's surface header in it, so there is no host stage to keep.
/// What it has to agree with the engine on is the one varying, `v_uv`, at
/// [uvLocation] — the location the engine's own full-screen stages read it
/// at, `webGpuFullscreenUvLocation()` from `flutter3d_webgpu` — and the
/// fragment stage's bind group, numbered as the build numbers it: blocks by
/// name, then samplers by name, a texture and a sampler each.
///
/// [program] must be specialised. Throws a [RuntimeShadersException] for a
/// source that is not a full-screen stage.
PackedStage fullscreenMaterialWgsl(
  MaterialProgram program, {
  required int uvLocation,
  required String from,
}) {
  if (program.kind != MaterialStageKind.fullscreen) {
    throw RuntimeShadersException(
      '$from: "${program.name}" is a ${program.kind} stage, not a full-screen '
      'one',
    );
  }
  const group = 1;
  final uniforms = <MaterialParameter>[
    for (final parameter in program.parameters)
      if (parameter.uniform) parameter,
  ];
  final readsDepth = program.inputsUsed.contains('sceneDepth');
  final params = uniforms.isEmpty ? null : _paramsBlock(uniforms, group, 0);
  var binding = params == null ? 0 : 1;
  final samplers = <PreparedSampler>[
    for (final name in <String>[
      for (final slot in program.textures) slot.bindingName,
      if (readsDepth) 'surface_texture',
    ]..sort())
      (
        name: name,
        group: group,
        textureBinding: binding++,
        samplerBinding: binding++,
        dimension: 'twoDimensional',
      ),
  ];

  final out = StringBuffer()
    ..writeln(
      '// The full-screen stage "${program.name}", written at run time.',
    );
  if (params != null) {
    out
      ..writeln('struct F3dMaterialParams {')
      ..writeAll(<String>[
        for (final p in uniforms) '    m_${p.name}: ${_type(p.type)},\n',
      ])
      ..writeln('}')
      ..writeln()
      ..writeln('@group($group) @binding(0) ')
      ..writeln('var<uniform> f3d_material_params: F3dMaterialParams;');
  }
  for (final sampler in samplers) {
    out
      ..writeln('@group($group) @binding(${sampler.textureBinding}) ')
      ..writeln('var ${sampler.name}_tex: texture_2d<f32>;')
      ..writeln('@group($group) @binding(${sampler.samplerBinding}) ')
      ..writeln('var ${sampler.name}_smp: sampler;');
  }
  final writer = _WgslWriter(
    surface: 'f3d_s',
    varying: (glsl) => glsl,
    params: 'f3d_material_params',
  );
  out
    ..writeln()
    ..writeln('@fragment ')
    ..writeln(
      'fn main(@location($uvLocation) v_uv: vec2<f32>) -> '
      '@location(0) vec4<f32> {',
    );
  if (readsDepth) {
    out
      ..writeln(
        '    let f3d_stored: f32 = textureSampleLevel(surface_texture_tex, '
        'surface_texture_smp, v_uv, 0.0).w;',
      )
      ..writeln(
        '    let f3d_scene_depth: f32 = select(1000000.0, f3d_stored, '
        'f3d_stored > 0.0);',
      );
  }
  for (final statement in program.body) {
    switch (statement) {
      case MaterialLet(:final name, :final value):
        out.writeln(
          '    let m_$name: ${_type(value.type)} = ${writer.expression(value)};',
        );
      case MaterialReturn(:final value):
        out.writeln('    return ${writer.expression(value)};');
      case MaterialOutput():
        throw RuntimeShadersException(
          '$from: a full-screen stage has no outputs',
        );
    }
  }
  out.writeln('}');
  return (
    wgsl: out.toString(),
    prepared: PreparedStage(
      glsl: emitMaterialFragment(program),
      attributes: const <PreparedAttribute>[],
      blocks: <PreparedBlock>[?params],
      samplers: samplers,
    ),
  );
}

/// `MaterialParams` as std140 lays out the GLSL block the emitter writes.
PreparedBlock _paramsBlock(
  List<MaterialParameter> uniforms,
  int group,
  int binding,
) {
  final members = <PreparedMember>[];
  var offset = 0;
  for (final parameter in uniforms) {
    final (align, size) = switch (parameter.type.components) {
      1 => (4, 4),
      2 => (8, 8),
      3 => (16, 12),
      _ => (16, 16),
    };
    offset = (offset + align - 1) ~/ align * align;
    members.add((
      name: parameter.name,
      offsetInBytes: offset,
      sizeInBytes: size,
    ));
    offset += size;
  }
  return (
    name: 'MaterialParams',
    group: group,
    binding: binding,
    sizeInBytes: (offset + 15) ~/ 16 * 16,
    members: members,
  );
}

String _type(MaterialType type) => switch (type.components) {
  1 => 'f32',
  2 => 'vec2<f32>',
  3 => 'vec3<f32>',
  4 => 'vec4<f32>',
  _ => throw StateError('a ${type.name} is not a value WGSL can hold'),
};

/// One expression of the material language as WGSL.
final class _WgslWriter {
  _WgslWriter({
    required this.surface,
    required this.varying,
    required this.params,
  });

  /// The local the surface is read into.
  final String surface;

  /// The private variable the host keeps a varying in, by its GLSL name.
  final String Function(String glsl) varying;

  /// The uniform the parameters are bound to.
  final String params;

  String expression(MaterialExpression expression) {
    switch (expression) {
      case MaterialConstant(:final value, :final type):
        if (type.components == 1) return _number(value.single);
        return '${_type(type)}(${value.map(_number).join(', ')})';
      case MaterialInputRef(:final input):
        final glsl = input.glsl;
        // The surface's own fields keep their names in the WGSL struct.
        if (glsl.startsWith('s.')) return '$surface.${glsl.substring(2)}';
        return varying(glsl);
      case MaterialLocalRef(:final name):
        return 'm_$name';
      case MaterialParamRef(:final parameter) when parameter.uniform:
        return '$params.m_${parameter.name}';
      case MaterialParamRef(:final parameter):
        throw StateError(
          'The parameter "${parameter.name}" has no value. Call '
          'specialiseMaterial before splicing.',
        );
      case MaterialConstruct(:final arguments, :final type):
        return '${_type(type)}(${arguments.map(this.expression).join(', ')})';
      case MaterialSwizzle(:final target, :final components):
        const letters = 'xyzw';
        return '${this.expression(target)}.'
            '${components.map((i) => letters[i]).join()}';
      case MaterialNegate(:final operand):
        return '(-(${this.expression(operand)}))';
      case MaterialBinary(:final op, :final left, :final right):
        return '(${this.expression(left)} $op ${this.expression(right)})';
      case MaterialCall(:final builtin, :final arguments):
        // Spread a float beside a vector for the component-wise builtins, as
        // the GLSL emitter does: WGSL's `clamp`, `min`, `max`, `pow`,
        // `smoothstep` and `step` take no mixed overloads at all.
        final width = arguments.fold(
          1,
          (int w, a) => a.type.components > w ? a.type.components : w,
        );
        String spread(MaterialExpression argument) {
          final text = this.expression(argument);
          return builtin.componentWise &&
                  width > 1 &&
                  argument.type.components == 1
              ? '${_type(MaterialType.numeric[width]!)}($text)'
              : text;
        }

        // The sixteen builtins are named in WGSL as they are in GLSL.
        return '${builtin.glsl}(${arguments.map(spread).join(', ')})';
      case MaterialSample(:final slot, :final uv):
        final name = slot.bindingName;
        return 'textureSample(${name}_tex, ${name}_smp, '
            '${this.expression(uv)})';
    }
  }
}

/// A WGSL float literal: always with a point or an exponent, and a negative
/// one in brackets so it never follows another minus.
String _number(double value) {
  if (!value.isFinite) {
    throw ArgumentError('$value cannot be written as a WGSL literal.');
  }
  final text = value.abs().toString();
  final literal = text.contains('.') || text.contains('e') ? text : '$text.0';
  return value < 0 ? '(-$literal)' : literal;
}
