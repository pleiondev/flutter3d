/// A plugin's lit model with a block and a texture of its own, as this
/// backend binds it: by group and binding number, numbered when the build
/// packs the stage (D21).
///
///     flutter test test/material_slots_test.dart
///
/// The material goes the way the build takes it (`flutter3d_build_hooks`'
/// `compileMaterial`): emitted, its headers resolved against the real tree,
/// numbered by `prepareStage`, and, where glslang and naga answer, compiled
/// and packed into the section this backend loads. What is checked is the
/// contract in "The shader ABI" of `docs/CONTRACTS.md`: the material's own
/// blocks and textures take the bindings after the engine's, in the slot
/// table's order, and every name the renderer binds by reaches a binding of
/// its own.
///
/// **The VM only**, for the reason `material_language_generators_test.dart`
/// gives: the headers are read from disk.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_shaders/compile.dart';
import 'package:flutter3d_webgpu/engine_shaders.dart';
import 'package:flutter3d_webgpu/src/webgpu_bundle_section.dart';
import 'package:flutter3d_webgpu/src/webgpu_shaders.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sample plugin's hair model: a uniform in `MaterialParams`, two in a
/// block of its own, and a texture of its own.
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

bool _answers(String program) {
  try {
    Process.runSync(program, const <String>['--version']);
    return true;
  } on ProcessException {
    return false;
  }
}

void main() {
  final shaders = loadShaders();
  final program = parseMaterial(_hair);
  final table = MaterialSlotTable.of(program);
  final glsl = emitMaterialFragment(
    specializeMaterial(program, const MaterialVariant('acme_sample_Hair')),
  );
  const from = 'acme_sample/hair.f3dmat';
  final resolved = resolveIncludes(glsl, shaders.sources, from: from);
  final locations = bundleVaryingLocations(shaders, <BundleStageSource>[
    (file: '$from#acme_sample_Hair', fragment: true, resolved: resolved),
  ]);
  // What the material binds beyond the engine, in the table's order: its
  // blocks, then its textures.
  final own = <String>[
    for (final block in table.blocks) block.name,
    for (final texture in table.textures) texture.binding,
  ];
  final prepared = prepareStage(
    resolved,
    from: from,
    fragment: true,
    varyingLocations: locations,
    ownBindings: own,
  );

  test('the table names what the stage declares', () {
    expect(own, <String>['MaterialParams', 'Strands', 'material_fur']);
    expect(prepared.blocks.map((b) => b.name), containsAll(own.take(2)));
    expect(prepared.samplers.map((s) => s.name), contains('material_fur'));
  });

  test('every binding of the stage is its own', () {
    final taken = <(int, int)>[
      for (final block in prepared.blocks) (block.group, block.binding),
      for (final sampler in prepared.samplers) ...<(int, int)>[
        (sampler.group, sampler.textureBinding),
        (sampler.group, sampler.samplerBinding),
      ],
    ];
    expect(taken.toSet(), hasLength(taken.length));
  });

  test(
    'the material\'s own come after the engine\'s, in the table\'s order',
    () {
      // Mutation: number every block and sampler of the stage by name, as the
      // engine's own stages are, and `Strands` lands among the engine's blocks
      // and `material_fur` before `metallic_roughness_texture`.
      final numbers = <String, int>{
        for (final block in prepared.blocks) block.name: block.binding,
        for (final sampler in prepared.samplers)
          sampler.name: sampler.textureBinding,
      };
      final engine = <int>[
        for (final MapEntry(:key, :value) in numbers.entries)
          if (!own.contains(key)) value,
      ];
      final ours = <int>[for (final name in own) numbers[name]!];
      expect(ours, orderedEquals(<int>[...ours]..sort()));
      expect(
        ours.first,
        greaterThan(engine.reduce((a, b) => a > b ? a : b)),
        reason: 'numbers: $numbers',
      );
    },
  );

  test(
    'compiled and packed, the section reflects each name at its binding',
    () {
      final compiled = compileStage(
        prepared.glsl,
        name: 'acme_sample_Hair',
        fragment: true,
      );
      final document = wgslSectionDocument(
        vertex: const <String, PackedStage>{},
        fragment: <String, PackedStage>{
          'acme_sample_Hair': (wgsl: compiled.wgsl, prepared: prepared),
        },
      );
      final stage = decodeWebGpuSection(
        Uint8List.fromList(utf8.encode(document)).buffer.asByteData(),
      ).fragment['acme_sample_Hair']!;
      for (final block in prepared.blocks) {
        final reflected = stage.blocks.singleWhere((b) => b.name == block.name);
        expect(
          (reflected.group, reflected.binding),
          (block.group, block.binding),
        );
      }
      final fur = stage.samplers.singleWhere((s) => s.name == 'material_fur');
      final declared = prepared.samplers.singleWhere(
        (s) => s.name == 'material_fur',
      );
      expect(
        (fur.textureBinding, fur.samplerBinding),
        (declared.textureBinding, declared.samplerBinding),
      );
      // The block's members where std140 puts them, as the slot table says.
      final strands = stage.blocks.singleWhere((b) => b.name == 'Strands');
      expect(
        <String, int>{
          for (final member in strands.members)
            member.name: member.offsetInBytes,
        },
        <String, int>{
          for (final member in table.block('Strands')!.members)
            member.name: member.offset,
        },
      );
    },
    skip: _answers(glslangExecutable) && _answers(nagaExecutable)
        ? null
        : 'glslang and naga are not on PATH',
  );

  test(
    'packed, the material\'s own blocks share one binding naga reads, and '
    'a pipeline over the engine\'s mesh stage stays within 8 dynamic blocks',
    () {
      final compiled = compileStage(
        prepared.glsl,
        name: 'acme_sample_Hair',
        fragment: true,
      );
      final document = wgslSectionDocument(
        vertex: const <String, PackedStage>{},
        fragment: <String, PackedStage>{
          'acme_sample_Hair': (wgsl: compiled.wgsl, prepared: prepared),
        },
      );
      final stage = decodeWebGpuSection(
        Uint8List.fromList(utf8.encode(document)).buffer.asByteData(),
      ).fragment['acme_sample_Hair']!;
      // Mutation: give each block of the material's own a binding of its
      // own. With the mesh stage's two and the engine's five, the pipeline
      // asks for 9 dynamic uniform buffers, and WebGPU guarantees 8.
      final packed = packMaterialBlocks(stage);
      final params = packed.blocks.singleWhere(
        (b) => b.name == 'MaterialParams',
      );
      final strands = packed.blocks.singleWhere((b) => b.name == 'Strands');
      expect((strands.group, strands.binding), (params.group, params.binding));
      expect(params.offsetInBinding, 0);
      expect(strands.offsetInBinding, params.sizeInBytes);
      expect(
        params.bindingSizeInBytes,
        params.sizeInBytes + strands.sizeInBytes,
      );
      // The engine's blocks are where they were.
      for (final block in stage.blocks) {
        if (block.name == 'MaterialParams' || block.name == 'Strands') continue;
        final kept = packed.blocks.singleWhere((b) => b.name == block.name);
        expect(
          (kept.binding, kept.bindingSizeInBytes),
          (block.binding, block.sizeInBytes),
        );
      }
      final dynamicBlocks = <(int, int)>{
        for (final b in webGpuEngineShaders.vertex['MeshVertex']!.blocks)
          (b.group, b.binding),
        for (final b in packed.blocks) (b.group, b.binding),
      };
      expect(dynamicBlocks.length, lessThanOrEqualTo(8));

      // And the text is WGSL naga takes, with one uniform where there
      // were two.
      expect(
        RegExp(r'var<uniform>').allMatches(packed.wgsl).length,
        RegExp(r'var<uniform>').allMatches(stage.wgsl).length - 1,
      );
      final scratch = Directory.systemTemp.createTempSync('packed');
      try {
        final file = File('${scratch.path}/packed.wgsl')
          ..writeAsStringSync(packed.wgsl);
        final validated = Process.runSync(nagaExecutable, <String>[file.path]);
        expect(
          validated.exitCode,
          0,
          reason: '${validated.stdout}${validated.stderr}',
        );
      } finally {
        scratch.deleteSync(recursive: true);
      }
    },
    skip: _answers(glslangExecutable) && _answers(nagaExecutable)
        ? null
        : 'glslang and naga are not on PATH',
  );

  test('a stage with fewer than two blocks of the material\'s own is left '
      'as it is', () {
    const alone = WebGpuStage(
      wgsl:
          '@group(1) @binding(3) \nvar<uniform> material_params: '
          'MaterialParams;\n',
      attributes: <WebGpuAttribute>[],
      blocks: <WebGpuBlock>[
        WebGpuBlock(
          name: 'MaterialParams',
          group: 1,
          binding: 3,
          sizeInBytes: 16,
          members: <WebGpuBlockMember>[],
        ),
      ],
      samplers: <WebGpuSampler>[],
    );
    expect(packMaterialBlocks(alone), same(alone));
  });
}
