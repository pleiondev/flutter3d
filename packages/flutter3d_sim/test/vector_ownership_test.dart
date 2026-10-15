/// Who owns a vector the simulation hands out (docs/CONTRACTS.md, "Space").
///
///     dart test test/vector_ownership_test.dart
///
/// A getter answers a copy: writing into what a step read must not change
/// what the next step reads.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('the input\'s axes are copies', () {
    final input = InputState()
      ..setStickAxis(0.5, 0.25)
      ..addLook(3.0, 4.0);
    // Mutation: return `_moveAxis` or `_lookDelta` from the getters. A brain
    // that normalised the stick it read would change the recorded input.
    input.moveAxis.setValues(1.0, 1.0);
    input.lookDelta.setZero();
    expect(input.moveAxis, Vector2(0.5, 0.25));
    expect(input.lookDelta, Vector2(3.0, 4.0));
  });

  test('an interpolated vector\'s current value is a copy', () {
    final smoothed = InterpolatedVector3()..jumpTo(Vector3(1.0, 2.0, 3.0));
    // Mutation: return `_current` from `current`.
    smoothed.current.setZero();
    expect(smoothed.current, Vector3(1.0, 2.0, 3.0));
  });
}
