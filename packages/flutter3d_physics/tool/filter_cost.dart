/// How much the contact filter costs in the loop it was put into.
///
///     dart run tool/filter_cost.dart
///
/// The predicate goes into `sweep`, which the character controller calls four
/// times a step and a game steps sixty times a second. An indirect call there
/// is the kind of thing that is cheap until it is not, and the plan that asked
/// for it asked for this number too.
library;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

const int _steps = 200000;

CollisionWorld _level() {
  final world = CollisionWorld()
    ..add(
      Collider(
        shape: CollisionBox(Vector3(60.0, 0.5, 60.0)),
        position: Vector3(0.0, -0.5, 0.0),
      ),
    );
  // Something to sweep against: a field of pillars, which is what a level of
  // brushes looks like to the broadphase.
  for (var x = -40; x <= 40; x += 4) {
    for (var z = -40; z <= 40; z += 4) {
      world.add(
        Collider(
          shape: CollisionBox(Vector3(0.6, 2.0, 0.6)),
          position: Vector3(x.toDouble(), 2.0, z.toDouble()),
        ),
      );
    }
  }
  return world;
}

double _run({ContactFilter? filter}) {
  final world = _level();
  final body = CharacterController(
    world: world,
    position: Vector3(1.0, 0.9, 1.0),
  )..solidFilter = filter;
  final wish = Vector3(1.0, 0.0, 0.35);
  final clock = Stopwatch()..start();
  for (var i = 0; i < _steps; i++) {
    if (i % 900 == 0) body.requestJump();
    body.step(1.0 / 60.0, wishDirection: wish);
    if (body.position.x > 40.0 || body.position.z > 40.0) {
      body.teleport(Vector3(-40.0, 0.9, -40.0));
    }
  }
  clock.stop();
  return clock.elapsedMicroseconds / _steps;
}

void main() {
  // Warm, then measure: the first thousand steps are the JIT's.
  _run();
  final without = _run();
  _run(filter: (Collider other, Vector3 normal) => true);
  final trivial = _run(filter: (Collider other, Vector3 normal) => true);
  final oneWay = _run(
    filter: (Collider other, Vector3 normal) =>
        other.layer & (1 << 6) == 0 || normal.y > 0.5,
  );

  // ignore: avoid_print
  print(
    'microseconds per step over $_steps steps\n'
    '  no filter      ${without.toStringAsFixed(3)}\n'
    '  trivial filter ${trivial.toStringAsFixed(3)}  '
    '(+${((trivial / without - 1) * 100).toStringAsFixed(1)}%)\n'
    '  one-way filter ${oneWay.toStringAsFixed(3)}  '
    '(+${((oneWay / without - 1) * 100).toStringAsFixed(1)}%)',
  );
}
