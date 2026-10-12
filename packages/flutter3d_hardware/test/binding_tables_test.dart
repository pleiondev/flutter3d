/// The binding tables are classes that can grow.
///
/// `StageBindings` and `UniformMemberLayout` were records, and a record
/// cannot gain a field, so no binding kind and no stride could ever be added
/// to them in a minor. As classes they take named, defaulted fields, and the
/// tables built from them compare by value as the records did.
///
/// Mutation: drop `elements`' default, or compare `blocks` by identity.
library;

import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';

void main() {
  test('a stage that keeps nothing is the empty default', () {
    const none = StageBindings();
    expect(none.blocks, isEmpty);
    expect(none.samplers, isEmpty);
  });

  test('two tables with the same names are equal, in any order', () {
    final a = StageBindings(
      blocks: <String>{'FragInfo', 'FogInfo'},
      samplers: <String>{'base_color_texture'},
    );
    final b = StageBindings(
      blocks: <String>{'FogInfo', 'FragInfo'},
      samplers: <String>{'base_color_texture'},
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(StageBindings(blocks: a.blocks)));
  });

  test('a member that is not an array has one element', () {
    const member = UniformMemberLayout(
      offset: 16,
      byteLength: 16,
      type: 'Vector4',
    );
    expect(member.elements, 1);
    expect(
      member,
      const UniformMemberLayout(
        offset: 16,
        byteLength: 16,
        elements: 1,
        type: 'Vector4',
      ),
    );
    expect(
      member,
      isNot(
        const UniformMemberLayout(offset: 0, byteLength: 16, type: 'Vector4'),
      ),
    );
  });

  test('a handle answers from its table', () {
    final handle = wrapShader(
      backend: Object(),
      name: 'Pbr',
      kept: const StageBindings(blocks: <String>{'FragInfo'}),
    );
    expect(handle.mayBindBlock('FragInfo'), isTrue);
    expect(handle.mayBindBlock('FogInfo'), isFalse);
    expect(handle.mayBindSampler('base_color_texture'), isFalse);
  });
}
