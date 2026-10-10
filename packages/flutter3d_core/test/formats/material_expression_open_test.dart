// `MaterialExpression` is an `abstract base class`, not `sealed`: an
// expression kind added in a minor release does not break a `switch` outside,
// and a tool may build its own nodes. What this build does not know it
// refuses by name instead of folding or emitting something wrong.
import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

// Declared outside the library: a compile error while the type is sealed.
final class _Glow extends MaterialExpression {
  _Glow() : super(MaterialType.vec4);
}

void main() {
  test('an expression of a kind this build does not know is refused', () {
    final program = MaterialProgram(
      name: 'glow',
      parameters: const <MaterialParameter>[],
      textures: const <MaterialTextureSlot>[],
      body: <MaterialStatement>[MaterialReturn(_Glow())],
      inputsUsed: const <String>{},
    );
    expect(
      () => specializeMaterial(program, const MaterialVariant('default')),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('not an expression this build'),
        ),
      ),
    );
  });
}
