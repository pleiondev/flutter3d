/// A plugin's lit model with a block and a texture of its own, as WebGL2
/// binds it: by the block's and the sampler's names, which the linked
/// program reports through `getActiveUniformBlockName` and
/// `getActiveUniform` (D21).
///
///     flutter test test/material_slots_test.dart
///
/// What a VM can hold is the translation: the GLSL ES the build writes keeps
/// every block of the slot table under its name, with its members in the
/// table's order, and the texture under its binding name.
///
/// **The VM only**, for the reason `glsl_translate_test.dart`'s siblings
/// give: the engine's headers are read from disk.
@TestOn('vm')
library;

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_shaders/compile.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
  test('every slot of the table is declared under its name', () {
    final program = parseMaterial(_hair);
    final table = MaterialSlotTable.of(program);
    final es = translateGlsl(
      emitMaterialFragment(
        specializeMaterial(program, const MaterialVariant('acme_sample_Hair')),
      ),
      loadShaders().sources,
      from: 'acme_sample/hair.f3dmat',
      fragment: true,
    );
    for (final block in table.blocks) {
      final declared = RegExp(
        'uniform ${block.name}\\s*\\{([^}]*)\\}',
      ).firstMatch(es);
      expect(declared, isNotNull, reason: 'no block ${block.name} in:\n$es');
      // Members in the table's order, which is the std140 order the
      // renderer's offsets assume.
      final names = RegExp(
        r'(\w+)\s*;',
      ).allMatches(declared!.group(1)!).map((m) => m.group(1)).toList();
      expect(names, <String>[for (final m in block.members) m.name]);
    }
    for (final texture in table.textures) {
      expect(es, contains('uniform sampler2D ${texture.binding};'));
    }
  });
}
