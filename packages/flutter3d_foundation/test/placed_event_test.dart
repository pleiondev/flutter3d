import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// An event that says only where: the shape every game event mixing the
/// place in has, beside the base class it already extends.
final class _Landed with PlacedEvent {
  _Landed(this.at);

  @override
  final Vector3 at;
}

void main() {
  test('a placed event leans nowhere unless it says so', () {
    final landed = _Landed(Vector3(1.0, 2.0, 3.0));
    expect(landed.at, Vector3(1.0, 2.0, 3.0));
    expect(landed.direction, isNull);
  });
}
