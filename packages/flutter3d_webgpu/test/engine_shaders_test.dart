/// The committed table, held to what a pipeline will ask of it.
///
/// A separate question from `wgsl_pipeline_test.dart`, which regenerates
/// everything from source: this reads what is actually in `lib/` and shipped.
/// The two can disagree, and the day they do is the day somebody edited a
/// generated file by hand or committed a table from before a shader changed —
/// which the WebGL2 backend has done once, and drew a sky nobody could see was
/// wrong.
///
/// It runs in a browser as well as on the VM, which is most of its value here:
/// this is the file that says the table compiles for the web at all, and the
/// device that will read it has no other platform.
library;

import 'package:flutter3d_webgpu/engine_shaders.dart';
import 'package:flutter3d_webgpu/src/webgpu_bundle_section.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final stages = <String, ({WebGpuStage stage, bool fragment})>{
    for (final entry in engineShaders.vertex.entries)
      entry.key: (stage: entry.value, fragment: false),
    for (final entry in engineShaders.fragment.entries)
      entry.key: (stage: entry.value, fragment: true),
  };

  test('holds every stage the engine asks for', () {
    // The names the renderer and `LightingModel.shaderName` reach for. Spelled
    // out rather than counted, because a count passes while a rename does not.
    for (final name in <String>[
      'MeshVertex',
      'MeshSkinnedVertex',
      'MeshInstancedVertex',
      'MeshLightmappedVertex',
      'Unlit',
      'Lambert',
      'BlinnPhong',
      'Pbr',
      'Toon',
      'Normals',
      'Xray',
      'ShadowDepth',
      'FullscreenVertex',
      'Composite',
      'SkyVertex',
      'Sky',
    ]) {
      expect(stages.containsKey(name), isTrue, reason: '$name is missing');
    }
    expect(stages.length, 39);
    expect(engineShaders.vertex.length, 12);
    expect(engineShaders.fragment.length, 27);
  });

  test('every stage carries WGSL with an entry point of its kind', () {
    stages.forEach((name, entry) {
      expect(
        entry.stage.wgsl,
        contains(entry.fragment ? '@fragment' : '@vertex'),
        reason: name,
      );
    });
  });

  test('no vertex stage came back turned over', () {
    // The y-flip naga inserts by default, and the reason
    // `--keep-coordinate-space` is in `wgsl_compiler.dart` rather than in
    // somebody's memory. Checked here as well as at generation time because
    // this is the table that ships.
    engineShaders.vertex.forEach((name, stage) {
      expect(stage.wgsl, isNot(contains('gl_Position.y = -(')), reason: name);
    });
  });

  test('a fragment stage declares no vertex inputs', () {
    engineShaders.fragment.forEach((name, stage) {
      expect(stage.attributes, isEmpty, reason: name);
    });
  });

  test('each stage binds into the group its kind owns', () {
    // Vertex resources in group 0 and fragment resources in group 1, so a
    // pipeline layout can be composed from two stages that were compiled
    // without knowing about each other.
    stages.forEach((name, entry) {
      final group = entry.fragment ? 1 : 0;
      for (final block in entry.stage.blocks) {
        expect(block.group, group, reason: '$name: ${block.name}');
      }
      for (final sampler in entry.stage.samplers) {
        expect(sampler.group, group, reason: '$name: ${sampler.name}');
      }
    });
  });

  test('no two things in a stage share a binding', () {
    stages.forEach((name, entry) {
      final bindings = <int>[
        for (final block in entry.stage.blocks) block.binding,
        for (final sampler in entry.stage.samplers) ...<int>[
          sampler.textureBinding,
          sampler.samplerBinding,
        ],
      ];
      expect(bindings.toSet().length, bindings.length, reason: name);
    });
  });

  test('every block a stage reflects is a struct in its WGSL', () {
    // The bind a phantom block would cause is what `lib/surface.glsl` says
    // costs a native crash on one backend and a silently discarded draw on
    // another. Naga names the struct after the GLSL block, so the table can be
    // held to it without a WGSL parser.
    stages.forEach((name, entry) {
      for (final block in entry.stage.blocks) {
        expect(
          entry.stage.wgsl,
          contains('struct ${block.name} {'),
          reason: '$name reflects "${block.name}" and does not declare it',
        );
        expect(
          entry.stage.wgsl,
          contains('@group(${block.group}) @binding(${block.binding})'),
          reason: '$name: ${block.name} is not bound where it says',
        );
      }
    });
  });

  test('every sampler a stage reflects is two variables in its WGSL', () {
    stages.forEach((name, entry) {
      for (final sampler in entry.stage.samplers) {
        expect(
          entry.stage.wgsl,
          contains('var ${sampler.name}_tex: '),
          reason: '$name has no texture for "${sampler.name}"',
        );
        expect(
          entry.stage.wgsl,
          contains('var ${sampler.name}_smp: sampler;'),
          reason: '$name has no sampler for "${sampler.name}"',
        );
        expect(
          entry.stage.wgsl,
          contains(
            sampler.dimension == WebGpuTextureDimension.cube
                ? 'texture_cube<f32>'
                : 'texture_2d<f32>',
          ),
          reason:
              '$name: ${sampler.name} is not a ${sampler.dimension.gpuName}',
        );
      }
    });
  });

  test('a block that guards itself off is absent, not empty', () {
    // `lighting/unlit.frag` defines `F3D_NO_POINT_SHADOW` before including
    // `lib/surface.glsl`, so the block and the two atlas samplers behind that
    // guard are not in the shader — and must not be in the reflection either.
    // `pbr.frag` includes the same header without the define and has all
    // three, which is what makes this a measurement of the guard rather than of
    // the file.
    final unlit = engineShaders.fragment['Unlit']!;
    expect(unlit.blocks.map((b) => b.name), isNot(contains('PointShadow')));
    expect(
      unlit.samplers.map((s) => s.name),
      isNot(contains('point_shadow_texture')),
    );

    final pbr = engineShaders.fragment['Pbr']!;
    expect(pbr.blocks.map((b) => b.name), contains('PointShadow'));
    expect(pbr.samplers.map((s) => s.name), contains('point_shadow_texture'));
    expect(
      pbr.samplers.map((s) => s.name),
      contains('point_shadow_static_texture'),
    );
  });

  test('a member of a shared block is at one offset everywhere', () {
    // `FragInfo` is one struct in one header and the engine writes one buffer
    // for it, so a model that laid it out differently would read another
    // model's bytes at the wrong offsets.
    //
    // **Per member and not per block, because one block name here is
    // deliberately two shapes.** The three particle stages share none of the
    // lit path's headers and declare a `FogInfo` of their own with the first
    // two members and not the third — `lighting/particle.frag` says so at
    // length: a particle writes no surface buffer, so it is never bound the
    // `forward` the lit models measure their depths along. Two blocks with one
    // name and different lengths is safe exactly as long as what they do share
    // lands in the same place, which is what this measures.
    final offsets = <String, Map<String, (String, int)>>{};
    stages.forEach((name, entry) {
      for (final block in entry.stage.blocks) {
        final known = offsets[block.name] ??= <String, (String, int)>{};
        for (final member in block.members) {
          final first = known[member.name];
          if (first == null) {
            known[member.name] = (name, member.offsetInBytes);
            continue;
          }
          expect(
            member.offsetInBytes,
            first.$2,
            reason:
                '${block.name}.${member.name} is at ${member.offsetInBytes} in '
                '$name and at ${first.$2} in ${first.$1}',
          );
        }
      }
    });

    expect(offsets['FragInfo']!['ambient_ground']!.$2, 848);
    expect(offsets['FogInfo']!['eye']!.$2, 16);
    // The member the particle stages do not declare, from the stages that do.
    expect(offsets['FogInfo']!['forward']!.$2, 32);
    expect(
      engineShaders.fragment['Particle']!.blocks.single.members.length,
      2,
      reason: 'the particle FogInfo grew a member it is never bound',
    );
  });
}
