/// A material's own blocks and textures share one name space with each
/// other and with the engine's, and `prepareStage` refuses a name taken
/// twice before it numbers anything.
///
///     dart test test/own_bindings_test.dart
///
/// Mutation: drop the check from `prepareStage`, and a block and a texture
/// both called `Hair` are numbered as one, while an own `shadow_texture`
/// takes the engine's sampler for the material's.
library;

import 'package:flutter3d_shaders/translate.dart';
import 'package:test/test.dart';

const String _stage = '''
#version 460
layout(location = 0) out vec4 frag_color;
void main() { frag_color = vec4(1.0); }
''';

PreparedStage _prepare(List<String> own) => prepareStage(
  _stage,
  from: 'acme/hair.f3dmat',
  fragment: true,
  varyingLocations: const <String, int>{},
  ownBindings: own,
);

Matcher _refused(String saying) => throwsA(
  isA<WgslPrepareException>().having(
    (e) => e.message,
    'message',
    allOf(contains('acme/hair.f3dmat'), contains(saying)),
  ),
);

void main() {
  test('a block and a texture under one name are refused', () {
    expect(() => _prepare(<String>['Hair', 'Hair']), _refused('"Hair" twice'));
  });

  test('an own name the engine binds is refused', () {
    expect(
      () => _prepare(<String>['shadow_texture']),
      _refused('the engine binds'),
    );
    expect(() => _prepare(<String>['FogInfo']), _refused('the engine binds'));
  });

  test('MaterialParams and names of the material\'s own are taken', () {
    expect(
      () => _prepare(<String>['MaterialParams', 'Strands', 'material_fur']),
      returnsNormally,
    );
  });
}
