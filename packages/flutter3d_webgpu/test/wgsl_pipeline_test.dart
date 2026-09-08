/// The whole road, over the whole manifest, with both compilers really run.
///
/// `glsl_to_wgsl_test.dart` asks whether the right edit was made. This asks
/// whether the edit compiles — which is a different question, and the only one
/// that can catch a rule that is reasonable and wrong.
///
/// **Every stage, not a sample.** A translation is a set of textual rules, and
/// a rule that fires on one shader in the manifest and nowhere else is exactly
/// the one worth running: the sky is the only stage with a cube sampler, the
/// probe is the only vertex stage that samples a texture, and `unlit.frag` is
/// the only one that switches a whole header off. A subset would be green while
/// one of those was broken.
///
/// On the VM because it runs two programs. `tool/ci.sh` runs this package on
/// both platforms and the browser run skips this file, which is right: nothing
/// here is about a browser.
@TestOn('vm')
library;

import 'dart:io';

// ignore: implementation_imports
import 'package:flutter3d_webgl/src/glsl_translate.dart';
import 'package:flutter3d_webgpu/src/glsl_to_wgsl.dart';
import 'package:flutter3d_webgpu/src/source_package.dart';
import 'package:flutter3d_webgpu/src/wgsl_compiler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final shaders = loadShaders();
  final resolved = <String, String>{
    for (final entry in shaders.stages.values)
      entry.file: resolveIncludes(
        shaders.sources[entry.file]!,
        shaders.sources,
        from: entry.file,
      ),
  };
  final locations = assignVaryingLocations(<Set<String>>[
    for (final entry in shaders.stages.values)
      scanVaryings(
        resolved[entry.file]!,
        from: entry.file,
        fragment: entry.fragment,
      ),
  ]);

  PreparedStage prepare(String name) {
    final entry = shaders.stages[name]!;
    return prepareStage(
      resolved[entry.file]!,
      from: entry.file,
      fragment: entry.fragment,
      varyingLocations: locations,
    );
  }

  group('every stage the manifest names', () {
    for (final name in shaders.stages.keys) {
      test('$name compiles to WGSL and back', () {
        final entry = shaders.stages[name]!;
        final prepared = prepare(name);
        final compiled = compileStage(
          prepared.glsl,
          name: name,
          fragment: entry.fragment,
        );

        expect(compiled.wgsl, isNotEmpty);
        expect(
          compiled.wgsl,
          contains(entry.fragment ? '@fragment' : '@vertex'),
        );

        // The y-flip naga would have inserted, absent. Checked on every stage
        // rather than on one, because the flag is passed per invocation and a
        // vertex stage that lost it would come back upside down with nothing
        // failing.
        expect(
          compiled.wgsl,
          isNot(contains('gl_Position.y = -(')),
          reason: 'naga turned $name over',
        );

        // Every block the reflection claims is a block glslang really
        // compiled, at the offsets std140 says. The sharp half is the first
        // expectation: a block in the reflection and not in the shader is a
        // buffer bound to a slot that is not there.
        for (final block in prepared.blocks) {
          final theirs = compiled.offsets[block.name];
          expect(
            theirs,
            isNotNull,
            reason: '$name reflects "${block.name}" and does not compile it',
          );
          for (final member in block.members) {
            expect(
              theirs![member.name],
              member.offsetInBytes,
              reason: '$name: ${block.name}.${member.name}',
            );
          }
        }
      });
    }
  });

  group('the numbering, over the manifest', () {
    /// Every `layout(location = N) in|out … name;` in a prepared stage.
    Map<String, int> declared(String name, {required bool outputs}) {
      final direction = outputs ? 'out' : 'in';
      return <String, int>{
        for (final match in RegExp(
          r'^layout\(location = (\d+)\) ' +
              direction +
              r' (?:\w+\s+)*\w+ (v_\w+);$',
          multiLine: true,
        ).allMatches(prepare(name).glsl))
          match.group(2)!: int.parse(match.group(1)!),
      };
    }

    test('gives one varying name one location everywhere', () {
      final seen = <String, (String, int)>{};
      for (final entry in shaders.stages.entries) {
        final here = declared(entry.key, outputs: !entry.value.fragment);
        here.forEach((varying, location) {
          final first = seen[varying];
          if (first == null) {
            seen[varying] = (entry.key, location);
            return;
          }
          expect(
            location,
            first.$2,
            reason:
                '$varying is location $location in ${entry.key} and '
                '${first.$2} in ${first.$1}',
          );
        });
      }
      // The seventeen names the manifest has today. Stated so that a shader
      // adding an eighteenth has to come back and read the family rule.
      expect(seen.length, 17);
    });

    test('keeps every family inside WebGPU\'s sixteen locations', () {
      expect(
        locations.values.every(
          (location) => location < kMaxInterStageVariables,
        ),
        isTrue,
      );
      // Four families and a widest of eight. One flat numbering would have
      // needed seventeen.
      expect(locations.length, 17);
      expect(locations.values.toSet().length, 8);
    });

    test('gives every stage its own bind group', () {
      for (final entry in shaders.stages.entries) {
        final prepared = prepare(entry.key);
        final group = entry.value.fragment ? kFragmentGroup : kVertexGroup;
        for (final block in prepared.blocks) {
          expect(block.group, group, reason: entry.key);
        }
        for (final sampler in prepared.samplers) {
          expect(sampler.group, group, reason: entry.key);
        }
      }
    });

    test('gives every binding in a stage to one thing only', () {
      for (final entry in shaders.stages.entries) {
        final prepared = prepare(entry.key);
        final bindings = <int>[
          for (final block in prepared.blocks) block.binding,
          for (final sampler in prepared.samplers) ...<int>[
            sampler.textureBinding,
            sampler.samplerBinding,
          ],
        ];
        expect(
          bindings.toSet().length,
          bindings.length,
          reason: '${entry.key} binds two things to one slot',
        );
      }
    });
  });

  group('the two measurements this pipeline is built on', () {
    // Both are facts about the tools rather than about this repository, and
    // both are the kind of fact that quietly stops being true. Written as
    // tests so that the day one of them changes, something says so.

    test('naga refuses a combined sampler and accepts a split one', () {
      const combined =
          '#version 460 core\n'
          'layout(set = 0, binding = 0) uniform sampler2D tex;\n'
          'layout(location = 0) in vec2 uv;\n'
          'layout(location = 0) out vec4 frag_color;\n'
          'void main() { frag_color = texture(tex, uv); }\n';
      const split =
          '#version 460 core\n'
          'layout(set = 0, binding = 0) uniform texture2D tex_tex;\n'
          'layout(set = 0, binding = 1) uniform sampler tex_smp;\n'
          '#define tex sampler2D(tex_tex, tex_smp)\n'
          'layout(location = 0) in vec2 uv;\n'
          'layout(location = 0) out vec4 frag_color;\n'
          'void main() { frag_color = texture(tex, uv); }\n';

      // glslang accepts both — the refusal is naga's, and it names neither a
      // file nor a construct. That is why the workaround is a rule about
      // declarations rather than a response to a diagnostic.
      expect(
        () => compileStage(combined, name: 'combined', fragment: true),
        throwsA(
          isA<WgslCompileError>().having(
            (error) => error.message,
            'message',
            contains('invalid id'),
          ),
        ),
      );
      expect(
        compileStage(split, name: 'split', fragment: true).wgsl,
        contains('textureSample(tex_tex, tex_smp'),
      );
    });

    test('naga turns a vertex stage over unless told not to', () {
      const source =
          '#version 460 core\n'
          'layout(location = 0) in vec3 position;\n'
          'void main() { gl_Position = vec4(position, 1.0); }\n';
      final directory = Directory.systemTemp.createTempSync('flutter3d_flip_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final glsl = File('${directory.path}/flip.vert')
        ..writeAsStringSync(source);
      final spirv = '${directory.path}/flip.spv';
      expect(
        Process.runSync(kGlslang, <String>[
          '-V',
          '--auto-map-locations',
          glsl.path,
          '-o',
          spirv,
        ]).exitCode,
        0,
      );

      String translate(List<String> flags) {
        final out = '${directory.path}/flip${flags.length}.wgsl';
        expect(
          Process.runSync(kNaga, <String>[...flags, spirv, out]).exitCode,
          0,
        );
        return File(out).readAsStringSync();
      }

      // The default, which is the trap: no error, no warning, and every scene
      // upside down.
      expect(translate(<String>[]), contains('gl_Position.y = -('));
      expect(
        translate(<String>['--keep-coordinate-space']),
        isNot(contains('gl_Position.y = -(')),
      );
    });

    test('naga keeps the names the reflection is written against', () {
      // The spike's README says WGSL "drops every name before the browser sees
      // the module". That is not what naga 30.0.1 does with explicit bindings,
      // and this backend's reflection does not depend on it either way — the
      // packer hands out the numbers. Measured because the claim is written
      // down somewhere a reader will find it.
      final compiled = compileStage(
        '#version 460 core\n'
        'layout(set = 0, binding = 0, std140) uniform FrameInfo {\n'
        '  mat4 mvp;\n'
        '}\n'
        'frame_info;\n'
        'layout(set = 0, binding = 1) uniform texture2D probe_tex;\n'
        'layout(set = 0, binding = 2) uniform sampler probe_smp;\n'
        'layout(location = 0) in vec3 position;\n'
        'void main() { gl_Position = frame_info.mvp * vec4(position, 1.0); }\n',
        name: 'names',
        fragment: false,
      );
      for (final kept in <String>[
        'FrameInfo',
        'mvp',
        'frame_info',
        'probe_tex',
        'probe_smp',
        'position',
      ]) {
        expect(compiled.wgsl, contains(kept), reason: '$kept did not survive');
      }
    });
  });
}
