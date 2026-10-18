import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('a thing heard is made by name', () {
    final heard = Audible(
      key: 7,
      at: Vector3(1.0, 0.0, 2.0),
      loudness: 0.5,
      rate: 0.9,
    );
    expect(heard.key, 7);
    expect(heard.at, Vector3(1.0, 0.0, 2.0));
    expect(heard.loudness, 0.5);
    expect(heard.rate, 0.9);
  });
}
