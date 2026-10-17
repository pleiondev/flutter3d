/// What a `.f3dmat` file may hold: one block of the material language,
/// first, and after it only the kernel language's `compute` blocks.
///
///     dart test test/formats/material_language_file_test.dart
library;

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_shaders/kernel.dart' show ComputeKernel;
import 'package:test/test.dart';

const String _material = '''
material Lit {
  fragment { return vec4(albedo, alpha); }
}
''';

/// A kernel of the kernel language, with the punctuation the material
/// language has no token for.
const String _kernel = '''
compute Fill {
  buffer values: u32[] read_write;
  kernel {
    let i = id.x;
    if i >= len(values) { return; }
    values[i] = 1u;
  }
}
''';

Matcher _refused(String message, int line, int column) => throwsA(
  isA<MaterialSyntaxException>()
      .having((e) => e.message, 'message', contains(message))
      .having((e) => e.line, 'line', line)
      .having((e) => e.column, 'column', column),
);

void main() {
  test('a material and the kernels beside it are read by their parsers', () {
    // Mutation: tokenize the whole file as the material language, and the
    // kernel's "[" is refused before the material is read.
    const file = 'f3dmat 2\nkernel 2\n$_material$_kernel// the end\n';
    expect(parseMaterial(file).name, 'Lit');
    expect(ComputeKernel.parseAll(file).single.name, 'Fill');
  });

  test('a second material is refused, not dropped', () {
    // Mutation: return after the first block without looking further, and
    // the second material is dropped without a word.
    expect(
      () => parseMaterial('$_material${_material.replaceFirst('Lit', 'B')}'),
      _refused('holds one material, first', 4, 1),
    );
    expect(
      () => parseMaterial('${_material}fullscreen F { }\n'),
      _refused('"fullscreen" is a second', 4, 1),
    );
  });

  test('anything else after the material is refused where it starts', () {
    expect(
      () => parseMaterial('${_material}junk { more }\n'),
      _refused('"junk" cannot follow the material', 4, 1),
    );
    expect(
      () => parseMaterial('$_material  ;'),
      _refused('";" cannot follow the material', 4, 3),
    );
    expect(
      () => parseMaterial('${_material}compute { }'),
      _refused('names its kernel', 4, 9),
    );
    expect(
      () => parseMaterial('${_material}compute K { kernel { }'),
      _refused('never closed', 4, 1),
    );
  });
}
