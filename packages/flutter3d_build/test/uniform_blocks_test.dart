/// Typed uniform blocks: generated from the compiler's reflection of a
/// stage, read back, and held to the reflection so a misspelt or renamed
/// member fails the build by name.
///
///     dart test test/uniform_blocks_test.dart
///
/// The first group needs no compiler: a reflection shaped as `impellerc`
/// writes it. The second runs the real `impellerc` of the Flutter SDK on
/// the facade example's `RimGlow` material, and is skipped where there is
/// none.
library;

import 'dart:io';

import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:flutter3d_build_hooks/flutter3d_build_hooks.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart'
    show UniformMemberLayout;
import 'package:flutter3d_shaders/compile.dart';
import 'package:test/test.dart';

/// A reflection as `impellerc --reflection-json` writes one: a block with a
/// float, std140 padding and a vec3.
const Map<String, Object?> _reflection = <String, Object?>{
  'buffers': <Object?>[
    <String, Object?>{
      'name': 'MaterialParams',
      'type': <String, Object?>{
        'members': <Object?>[
          <String, Object?>{
            'name': 'rimPower',
            'offset': 0,
            'byte_length': 4,
            'type': 'Float',
          },
          <String, Object?>{
            'name': '_PADDING_rimPower_',
            'offset': 4,
            'byte_length': 12,
            'type': 'Float',
          },
          <String, Object?>{
            'name': 'rimColor',
            'offset': 16,
            'byte_length': 12,
            'type': 'Point',
          },
        ],
      },
    },
  ],
};

const UniformBlockLayouts _blocks = <String, Map<String, UniformMemberLayout>>{
  'MaterialParams': <String, UniformMemberLayout>{
    'rimPower': UniformMemberLayout(offset: 0, byteLength: 4, type: 'Float'),
    'rimColor': UniformMemberLayout(offset: 16, byteLength: 12, type: 'Point'),
  },
};

MaterialCompilers? _compilers() {
  try {
    return MaterialCompilers.locate();
  } on MaterialBuildException {
    return null;
  }
}

void main() {
  group('without a compiler', () {
    test('the reflection is read, padding left out', () {
      // Mutation: keep `_PADDING_` members. The class grows a field nobody
      // can fill and the check reads it as a member the source lacks.
      expect(uniformBlocksFromReflection(_reflection), _blocks);
    });

    test('a generated library reads back to the layouts it was made from', () {
      final dart = generateUniformBlocks(
        <String, UniformBlockLayouts>{'RimGlow': _blocks},
        from: const <String, String>{'RimGlow': 'assets_src/rim.f3dmat'},
      );
      expect(dart, contains('final class RimGlowParamsBlock extends'));
      expect(dart, contains("super('MaterialParams')"));
      expect(dart, contains('final Float32List rimColor = Float32List(3);'));
      expect(uniformBlocksInSource(dart), <String, UniformBlockLayouts>{
        'RimGlow': _blocks,
      });
    });

    test('a misspelt member is named, with the one the stage has', () {
      // Mutation: drop `_nearest`. The build says what is missing and not
      // what was meant.
      final problems = uniformBlockProblems(
        <String, Map<String, UniformMemberLayout>>{
          'MaterialParams': <String, UniformMemberLayout>{
            'rimColour': _blocks['MaterialParams']!['rimColor']!,
          },
        },
        _blocks,
        stage: 'RimGlow',
        against: 'lib/uniform_blocks.g.dart',
      );
      expect(problems, hasLength(1));
      expect(problems.single, contains('"rimColour"'));
      expect(problems.single, contains('did you mean "rimColor"?'));
    });

    test('an offset or a size the compiler does not agree with is named', () {
      final problems = uniformBlockProblems(
        <String, Map<String, UniformMemberLayout>>{
          'MaterialParams': <String, UniformMemberLayout>{
            'rimPower': const UniformMemberLayout(
              offset: 0,
              byteLength: 8,
              type: 'Float',
            ),
            'rimColor': const UniformMemberLayout(
              offset: 12,
              byteLength: 12,
              type: 'Point',
            ),
          },
          'Missing': const <String, UniformMemberLayout>{},
        },
        _blocks,
        stage: 'RimGlow',
        against: 'the material source',
      );
      expect(problems, hasLength(3));
      expect(problems[0], contains('takes 8 bytes'));
      expect(problems[1], contains('at byte 12'));
      expect(problems[2], contains('"Missing"'));
    });
  });

  group('with impellerc', () {
    final compilers = _compilers();
    final engine = loadShaders();
    late Directory scratch;
    setUp(() => scratch = Directory.systemTemp.createTempSync('f3d_blocks_'));
    tearDown(() => scratch.deleteSync(recursive: true));

    // The facade example's material, the one the `material-language`
    // golden draws on every backend.
    final rimGlow = File('../flutter3d/example/shaders/rim_glow.f3dmat');

    UniformBlockLayouts reflect(MaterialProgram program) => reflectStageBlocks(
      emitMaterialFragment(
        specializeMaterial(program, MaterialVariant(program.name)),
      ),
      name: program.name,
      fragment: true,
      source: rimGlow.path,
      compilers: compilers!,
      engine: engine,
      scratch: scratch,
    )!;

    test('the material language lays MaterialParams out as impellerc does', () {
      // Mutation: start the std140 arithmetic of `MaterialSlotTable` at
      // byte 4. The compiler puts `rimColor` at 0, and the build names the
      // member instead of shipping a material whose colour the engine
      // writes into the wrong bytes.
      final program = parseMaterial(rimGlow.readAsStringSync());
      final reflected = reflect(program);
      expect(reflected['MaterialParams'], contains('rimColor'));
      expect(
        uniformBlockProblems(
          declaredMaterialBlocks(program),
          reflected,
          stage: program.name,
          against: 'the material source',
        ),
        isEmpty,
      );
    });

    test('the build writes the classes and refuses a stale committed one', () {
      // Mutation: write the file over without reading it back. Code that
      // set `rimColour` stops compiling somewhere else, or compiles against
      // a field the stage never had.
      final project = Directory('${scratch.path}/project')..createSync();
      File(
        '${project.path}/pubspec.yaml',
      ).writeAsStringSync('name: blocks\ndependencies:\n  flutter3d: any\n');
      File('${project.path}/assets_src/rim_glow.f3dmat')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(rimGlow.readAsStringSync());
      runMaterialBuild(project, compilers: compilers, engine: engine);
      final generated = File('${project.path}/lib/uniform_blocks.g.dart');
      final dart = generated.readAsStringSync();
      expect(dart, contains('final class RimGlowParamsBlock'));
      // `rimPower` is a `param`, folded in as a constant; `rimColor` is the
      // block's one member.
      expect(
        dart,
        contains("'rimColor': UniformMemberLayout(\n          offset: 0,"),
      );

      // The committed file names a member the stage does not have.
      generated.writeAsStringSync(dart.replaceAll("'rimColor'", "'rimColour'"));
      File(
        '${project.path}/assets_src/rim_glow.f3dmat',
      ).writeAsStringSync('${rimGlow.readAsStringSync()}\n');
      expect(
        () => runMaterialBuild(project, compilers: compilers, engine: engine),
        throwsA(
          isA<MaterialBuildException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('"rimColour"'),
              contains('did you mean "rimColor"?'),
            ),
          ),
        ),
      );
    });
  }, skip: _compilers() == null ? 'no impellerc in this Flutter SDK' : null);
}
