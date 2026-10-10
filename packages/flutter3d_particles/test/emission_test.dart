import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show LinearColor;
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('an emission is made by name, and spent when its time runs out', () {
    const effect = ParticleEffect(
      count: 1,
      emitter: SphereEmitter(speed: Range.exact(0.0)),
      lifetime: Range.exact(1.0),
      size: Range.exact(1.0),
      color: LinearColor.white,
    );
    final emission = Emission(
      effect: effect,
      origin: Vector3(1.0, 2.0, 3.0),
      perSecond: 30.0,
      remaining: 0.5,
    );
    expect(emission.direction, isNull);
    expect(emission.perSecond, 30.0);
    expect(emission.isSpent, isFalse);
    emission.remaining = 0.0;
    expect(emission.isSpent, isTrue);
    expect(
      Emission(effect: effect, origin: Vector3.zero(), perSecond: 1.0).isSpent,
      isFalse,
      reason: 'no time limit runs until stopped',
    );
  });
}
