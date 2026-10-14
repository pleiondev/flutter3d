// Debris on the CPU — P9, phase 10: the core's own through the binding. On
// a GPU it is held to this in `flutter3d_effects/test/visual_workloads_test.dart`.
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A pen two metres wide: a floor and four walls.
final List<DebrisStatic> _pen = <DebrisStatic>[
  DebrisPlane(Vector3(0.0, 1.0, 0.0), 0.0),
  DebrisPlane(Vector3(1.0, 0.0, 0.0), -1.0),
  DebrisPlane(Vector3(-1.0, 0.0, 0.0), -1.0),
  DebrisPlane(Vector3(0.0, 0.0, 1.0), -1.0),
  DebrisPlane(Vector3(0.0, 0.0, -1.0), -1.0),
];

void main() {
  test('a ball comes to rest on the floor through the binding', () {
    final d = NativeDebris(2);
    addTearDown(d.dispose);
    expect(d.capacity, 2);
    d.setStatics(_pen.sublist(0, 1));
    d.add(<DebrisBody>[
      DebrisBody(
        position: Vector3(0.0, 0.5, 0.0),
        velocity: Vector3.zero(),
        radius: 0.1,
        mass: 1.0,
      ),
    ]);
    expect(d.read(), isNull);
    final settings = DebrisSettings(restitution: 0.0);
    for (var i = 0; i < 120; i++) {
      d.step(DebrisSystemStep(settings: settings, dt: 1 / 60));
    }
    final frame = d.read()!;
    expect(frame.step, 120);
    expect(frame.bodies[1], closeTo(0.1, 0.001));
    expect(frame.bodies[7], closeTo(0.1, 1e-7));
    // The second slot is empty, and nothing new comes until a step.
    expect(frame.bodies[15], 0.0);
    expect(d.read(), isNull);
  });

  test('statics past sixty-four, and a disposed set, say so', () {
    final d = NativeDebris(1);
    expect(
      () => d.setStatics(List<DebrisStatic>.filled(65, _pen.first)),
      throwsArgumentError,
    );
    d.dispose();
    expect(() => d.read(), throwsStateError);
    d.dispose();
    expect(() => NativeDebris(0), throwsArgumentError);
  });
}
