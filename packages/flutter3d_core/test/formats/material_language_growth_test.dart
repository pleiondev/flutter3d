/// How the material language grows in a minor without refusing a source
/// that parsed before: an input, a builtin or a reserved block name
/// arrives with a version, and a source of an older version keeps every
/// name it had.
///
///     dart test test/formats/material_language_growth_test.dart
library;

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_shaders/backend.dart' show uniformBlocks;
import 'package:test/test.dart';

const Map<String, List<MaterialInput>> _lists = <String, List<MaterialInput>>{
  'materialInputs': materialInputs,
  'materialLightInputs': materialLightInputs,
  'materialSceneInputs': materialSceneInputs,
  'materialVertexInputs': materialVertexInputs,
  'materialVertexOutputs': materialVertexOutputs,
  'materialAmbientInputs': materialAmbientInputs,
  'materialCompositeInputs': materialCompositeInputs,
  'materialFullscreenInputs': materialFullscreenInputs,
  'materialComputeInputs': materialComputeInputs,
};

String _surface(int version, String declaration) =>
    '''
f3dmat $version
material Growth {
  $declaration
  fragment { return vec4(albedo, alpha); }
}
''';

void main() {
  test('every input says the version it arrived in, one this build reads', () {
    // Mutation: give an input of version 2's lists `since: 1` and a version 1
    // source loses the name to it.
    for (final MapEntry(key: list, value: inputs) in _lists.entries) {
      for (final input in inputs) {
        expect(
          input.since,
          inInclusiveRange(1, materialLanguageVersion),
          reason: '$list.${input.name}',
        );
      }
    }
    for (final list in <String>[
      'materialSceneInputs',
      'materialVertexInputs',
      'materialAmbientInputs',
      'materialCompositeInputs',
      'materialFullscreenInputs',
      'materialComputeInputs',
    ]) {
      expect(
        _lists[list]!.every((MaterialInput i) => i.since >= 2),
        isTrue,
        reason: '$list arrived with version 2',
      );
    }
  });

  test('every builtin says the version it arrived in', () {
    for (final builtin in materialBuiltins) {
      expect(
        materialBuiltinVersions[builtin.name],
        inInclusiveRange(1, materialLanguageVersion),
        reason: builtin.name,
      );
    }
  });

  test('a name an input of a later version takes stays free in an older '
      'source', () {
    // `lightmap` is the ambient block's input since version 2: a version 1
    // parameter of that name is legal, and one in version 2 is not.
    // Mutation: drop the `since` filter from `takenInputs`.
    expect(
      parseMaterial(
        _surface(1, 'uniform float lightmap = 0.5;'),
      ).parameters.single.name,
      'lightmap',
    );
    expect(
      () => parseMaterial(_surface(2, 'uniform float lightmap = 0.5;')),
      throwsA(isA<MaterialSyntaxException>()),
    );
  });

  test("every block of the engine's is frozen or in the reserved shape", () {
    // Mutation: add a block named `Hair` to an engine shader in a minor and
    // this fails: CONTRACTS' own `uniform(Hair)` example would stop parsing.
    for (final blocks in uniformBlocks.values) {
      for (final name in blocks.keys) {
        expect(isEngineBlockName(name), isTrue, reason: name);
      }
    }
  });

  test("a material's block may not take the engine's or the reserved "
      'shape', () {
    String hair(String block) =>
        _surface(2, 'uniform($block) float shift = 0.1;');
    expect(parseMaterial(hair('Hair')).parameters.single.block, 'Hair');
    // Mutation: test the live table rather than the frozen list and shape,
    // and `HairInfo` is a material's name until the engine takes it.
    for (final taken in <String>['PointShadow', 'HairInfo', 'F3dHair']) {
      expect(
        () => parseMaterial(hair(taken)),
        throwsA(isA<MaterialSyntaxException>()),
        reason: taken,
      );
    }
  });
}
