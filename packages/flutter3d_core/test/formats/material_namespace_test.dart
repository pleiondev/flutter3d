/// A plugin's `.f3dmat` writes the bare name and compiles in the plugin's
/// namespace: the stage, and the source renamed to it.
///
///     dart test test/formats/material_namespace_test.dart
///
/// Mutation: let `materialStageIn` keep a name in another namespace, and a
/// plugin compiles a stage another plugin's model names; rename the first
/// `material` word `renameMaterialSource` meets, comments and all, and the
/// commented-out block is renamed instead of the material.
library;

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

const String _hair = '''
// material Fur { } was the first try.
f3dmat 3
material Hair {
  param float gloss = 0.5;
  fragment {
    return vec4(albedo * gloss, alpha);
  }
}
''';

void main() {
  test(
    'a bare name is put in the namespace, its own kept, another refused',
    () {
      expect(materialStageIn('acme_hair', 'Hair'), 'acme_hair__Hair');
      expect(
        materialStageIn('acme_hair', 'acme_hair__Hair'),
        'acme_hair__Hair',
      );
      expect(materialStageIn('acme_hair', 'acme__Hair'), isNull);
      // The stage reads back as the model's dotted name.
      expect(
        LightingModel('Hair', materialStageIn('acme_hair', 'Hair')!).name,
        'acme_hair.Hair',
      );
    },
  );

  test('the source is renamed at its block, and nothing else moves', () {
    final renamed = renameMaterialSource(_hair, 'acme_hair__Hair');
    final program = parseMaterial(renamed);
    expect(program.name, 'acme_hair__Hair');
    expect(program.parameters.single.name, 'gloss');
    expect(renamed, contains('// material Fur { } was the first try.'));
    expect(renamed.replaceFirst('acme_hair__Hair', 'Hair'), _hair);
    expect(
      () => renameMaterialSource('// nothing here\n', 'x'),
      throwsA(isA<MaterialSyntaxException>()),
    );
  });
}
