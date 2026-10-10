import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A mover written outside the package: everything it answers is a
/// [CharacterMoved] it builds itself, which a later field must not break.
final class _Lift extends CharacterMover {
  const _Lift();

  @override
  CharacterMoved move(
    CharacterController body,
    Vector3 delta, {
    required double stepHeight,
    required double walkableNormalY,
    required bool mayStep,
  }) => CharacterMoved(
    position: body.position + Vector3(0.0, 0.25, 0.0),
    grounded: true,
    velocity: Vector3.zero(),
    groundNormal: Vector3(0.0, 1.0, 0.0),
    stepped: true,
    steppedUp: 0.25,
  );
}

void main() {
  test('a mover of its own hands the controller a CharacterMoved', () {
    final world = CollisionWorld()..characterMover = const _Lift();
    final body = CharacterController(
      world: world,
      shape: CollisionBox(Vector3(0.3, 0.9, 0.3)),
      position: Vector3(0.0, 0.9, 0.0),
    );
    body.step(1.0 / 60.0, wishDirection: Vector3.zero());
    // Float32 vectors: a quarter metre up, to their precision.
    expect(body.position.y, closeTo(1.15, 1e-6));
    expect(body.steppedUp, 0.25);
    expect(body.isGrounded, isTrue);
  });

  test('what a mover leaves unsaid is nothing met', () {
    final moved = CharacterMoved(
      position: Vector3.zero(),
      grounded: false,
      velocity: Vector3.zero(),
    );
    expect(moved.hitWall, isFalse);
    expect(moved.hitCeiling, isFalse);
    expect(moved.stepped, isFalse);
    expect(moved.steppedUp, 0.0);
    expect(moved.groundNormal, Vector3.zero());
    expect(moved.ground, isNull);
  });

  test('a drop says where it is, how fast, how much and of what', () {
    final drop = JetDrop(
      position: Vector3(1.0, 2.0, 3.0),
      velocity: Vector3(0.0, -1.0, 0.0),
      volume: 1e-9,
      medium: FluidMedium.water,
    );
    expect(drop.volume, 1e-9);
    expect(drop.concentrations, isEmpty);
    expect(drop.medium, FluidMedium.water);
  });
}
