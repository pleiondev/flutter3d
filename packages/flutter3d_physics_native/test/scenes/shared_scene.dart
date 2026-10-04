/// A scene stepped natively and in the browser, and what its snapshot must
/// hash to on both — P9, phase 12.
///
/// The hash is the same number from the native library through `dart:ffi`
/// and from the WebAssembly module through `dart:js_interop`: the core
/// steps to the same bits both ways, and the two Dart backends carry them
/// across unchanged. When the physics changes on purpose, the native test
/// says what the new number is.
library;

import 'dart:typed_data';

import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:vector_math/vector_math.dart';

/// What [sharedSceneSnapshot]'s bytes hash to.
const String sharedSceneHash = '0fd233dd';

/// A floor, a heap of boxes, balls, capsules and a hull, a hinged pair,
/// materials and wind, stepped two seconds on [threads]; its snapshot —
/// the same on any number.
Uint8List sharedSceneSnapshot({int threads = 1}) {
  final world = NativeWorld()..wind = Vector3(1.0, 0.0, 0.5);
  if (threads > 1) world.threads = threads;
  try {
    final floor = world.addBody(
      position: Vector3(0.0, -0.5, 0.0),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    world.setShape(floor, NativeShape.box(Vector3(10.0, 0.5, 10.0)));
    final hull = world.createHull(<Vector3>[
      Vector3(0.3, 0.0, 0.0),
      Vector3(-0.3, 0.0, 0.0),
      Vector3(0.0, 0.4, 0.0),
      Vector3(0.0, -0.2, 0.0),
      Vector3(0.0, 0.0, 0.3),
      Vector3(0.0, 0.0, -0.3),
    ]);
    for (var i = 0; i < 40; i++) {
      final b = world.addBody(
        position: Vector3(
          (i % 5) * 0.7 - 1.4 + (i % 3) * 0.03,
          0.6 + (i ~/ 10) * 0.8,
          ((i ~/ 5) % 2) * 0.7,
        ),
        mass: 1.0 + (i % 4) * 0.5,
      );
      switch (i % 4) {
        case 0:
          world.setShape(b, NativeShape.box(Vector3(0.25, 0.2, 0.3)));
        case 1:
          world.setShape(b, const NativeShape.sphere(0.25));
        case 2:
          world.setShape(b, const NativeShape.capsule(0.15, 0.2));
        default:
          world.setHull(b, hull);
      }
      world.setAngularVelocity(b, Vector3((i % 5) * 0.4, 0.0, (i % 3) * 0.3));
      if (i % 7 == 0) world.setMaterial(b, NativeMaterial.wood());
    }
    final a = world.addBody(position: Vector3(3.0, 2.0, 0.0));
    final b = world.addBody(position: Vector3(3.5, 2.0, 0.0));
    world
      ..setShape(a, NativeShape.box(Vector3(0.2, 0.1, 0.1)))
      ..setShape(b, NativeShape.box(Vector3(0.2, 0.1, 0.1)))
      ..createJoint(
        NativeJointType.revolute,
        a,
        b,
        anchor: Vector3(3.25, 2.0, 0.0),
        axis: Vector3(0.0, 0.0, 1.0),
      );
    for (var i = 0; i < 120; i++) {
      world.step(1 / 60);
    }
    return world.snapshot();
  } finally {
    world.dispose();
  }
}

/// FNV-1a over [bytes] in 32 bits, as hex: written with nothing past 2⁵³,
/// so dart2js works it out as the VM does.
String hashOf(Uint8List bytes) {
  var h = 0x811c9dc5;
  for (final byte in bytes) {
    h = (h ^ byte) & 0xffffffff;
    h = (((h << 24) & 0xffffffff) + h * 403) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
}
