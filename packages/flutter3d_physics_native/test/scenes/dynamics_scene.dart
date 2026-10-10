// A scene of flutter3d_physics' bodies on NativeDynamics, for the tests
// that hold the browser to the native library through the mirror: a floor,
// a wedge, a lift, crates that can turn and crates that cannot, a ball
// down the wedge and a push — and every body's state afterwards, hashed.
import 'dart:typed_data';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:vector_math/vector_math.dart';

/// [h]'s low byte: h · 2²⁴ modulo 2³² is it times 2²⁴.
int low2(int h) => h % 256;

/// What [dynamicsSceneHash] comes to: written natively, matched in Chrome.
const String dynamicsSceneExpected = '8aea08a2';

/// Steps the scene and hashes every body's position, velocity, spin and
/// orientation by their float64 bytes, so that the browser's numbers and the
/// VM's — which print differently — are compared as what they are.
String dynamicsSceneHash() {
  final world = CollisionWorld()
    ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(30.0, 1.0, 30.0))
    ..add(
      Collider(
        shape: CollisionWedge(Vector3(2.0, 2.0, 2.0)),
        position: Vector3(6.0, 2.0, 0.0),
      ),
    );
  final lift = world.add(
    Collider(
      shape: CollisionBox(Vector3(1.0, 0.25, 1.0)),
      position: Vector3(-6.0, 0.25, 0.0),
      kind: ColliderKind.kinematic,
    ),
  );
  final dynamics = NativeDynamics(world: world);
  final bodies = <RigidBody>[
    for (var i = 0; i < 6; i++)
      dynamics.add(
        RigidBody(
          world: world,
          shape: CollisionBox(Vector3.all(0.4)),
          position: Vector3(i * 0.35 - 1.0, 0.6 + i * 0.9, 0.1 * i),
          canRotate: i.isEven,
        ),
      ),
    dynamics.add(
      RigidBody(
        world: world,
        shape: CollisionSphere(0.25),
        position: Vector3(7.0, 3.6, 0.0),
        friction: 0.1,
        canRotate: true,
      ),
    ),
    dynamics.add(
      RigidBody(
        world: world,
        shape: CollisionBox(Vector3.all(0.4)),
        position: Vector3(-6.0, 1.0, 0.0),
      ),
    ),
  ];
  final walker = world.add(
    Collider(
      shape: CollisionCapsule(radius: 0.3, halfHeight: 0.3),
      position: Vector3(-1.0, 0.6, -0.4 - 0.3 - 0.005),
      kind: ColliderKind.kinematic,
    ),
  );
  for (var step = 0; step < 240; step++) {
    if (step == 60) dynamics.push(walker, Vector3(0.0, 0.0, 2.0));
    if (step >= 90 && step < 150) {
      lift.moveTo(lift.position + Vector3(0.0, 1.0 / 60.0, 0.0));
    }
    dynamics.step(1.0 / 60.0);
    world.clearKinematicDeltas();
  }
  final numbers = Float64List(bodies.length * 13);
  var at = 0;
  for (final body in bodies) {
    for (final v in <Vector3>[
      body.position,
      body.velocity,
      body.angularVelocity,
    ]) {
      numbers[at++] = v.x;
      numbers[at++] = v.y;
      numbers[at++] = v.z;
    }
    final q = body.orientation;
    numbers[at++] = q.x;
    numbers[at++] = q.y;
    numbers[at++] = q.z;
    numbers[at++] = q.w;
  }
  dynamics.dispose();
  // FNV-1a, 32 bits, in arithmetic exact in JavaScript's numbers: the xor
  // on the low byte only, the product split as h·0x193 + h·2²⁴, each part
  // under 2⁵³ where the whole is not.
  var hash = 0x811c9dc5;
  for (final byte in numbers.buffer.asUint8List()) {
    final low = hash % 256;
    hash = hash - low + (low ^ byte);
    hash = (hash * 0x193 + low2(hash) * 0x1000000) % 0x100000000;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
