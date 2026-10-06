/// Cloth on the run's backend: the core's `f3d_cloth_solve` held to
/// `stepCloth`, the reference, on the scenes the reference's own users
/// step — a curtain pinned along its top, a flag in the wind, and a sheet
/// dropped on a ball, a box, a capsule, a wedge and a heightfield.
///
/// The two are not promised to agree to the bit, only each with itself: a
/// sheet on the core is held to where the reference puts it within a
/// tolerance that the rounding of single precision and the order the
/// constraints are solved in leave room for.
///
///     flutter test test/native_cloth_simulation_test.dart
///     flutter test --dart-define=FLUTTER3D_PHYSICS=dart \
///         test/native_cloth_simulation_test.dart
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1 / 60;

/// A 12 × 12 sheet a metre across at [height], hung by its top row, by the
/// two ends of it ([pinCorners]), or by nothing ([free]).
ClothMesh _sheet({
  double height = 1.0,
  bool pinCorners = false,
  bool free = false,
}) {
  final mesh = ClothMesh.grid(
    cols: 12,
    rows: 12,
    spacing: 0.09,
    height: height,
    pinCorners: pinCorners,
  );
  if (free) mesh.invMass.fillRange(0, mesh.particleCount, 1 / 0.05);
  // Centred over the origin, where the obstacles are.
  for (var i = 0; i < mesh.particleCount; i++) {
    mesh.positions[3 * i] -= 0.495;
    mesh.positions[3 * i + 2] -= 0.495;
  }
  return mesh;
}

ClothMesh _copy(ClothMesh m) => ClothMesh(
  cols: m.cols,
  rows: m.rows,
  positions: Float64List.fromList(m.positions),
  velocities: Float64List.fromList(m.velocities),
  invMass: Float64List.fromList(m.invMass),
  structuralPairs: m.structuralPairs,
  structuralRestLength: m.structuralRestLength,
  bendPairs: m.bendPairs,
  bendRestLength: m.bendRestLength,
  triangles: m.triangles,
  shearPairs: m.shearPairs,
  shearRestLength: m.shearRestLength,
  restPositions: m.restPositions,
);

/// The farthest any particle of [a] is from the same particle of [b].
double _apart(ClothMesh a, ClothMesh b) {
  var worst = 0.0;
  for (var i = 0; i < a.particleCount; i++) {
    final dx = a.positions[3 * i] - b.positions[3 * i];
    final dy = a.positions[3 * i + 1] - b.positions[3 * i + 1];
    final dz = a.positions[3 * i + 2] - b.positions[3 * i + 2];
    worst = math.max(worst, math.sqrt(dx * dx + dy * dy + dz * dz));
  }
  return worst;
}

/// [mesh] stepped [steps] times on the core and, from a copy, on the
/// reference; the core's sheet and how far it ended from the reference's.
(ClothMesh, double) _both(
  ClothMesh mesh,
  int steps, {
  ClothSettings settings = const ClothSettings(),
  List<ClothObstacle> obstacles = const <ClothObstacle>[],
}) {
  final reference = _copy(mesh);
  final core = NativeClothSimulation(mesh);
  addTearDown(core.dispose);
  for (var i = 0; i < steps; i++) {
    core.step(settings, _dt, obstacles: obstacles);
    stepCloth(reference, settings, _dt, obstacles: obstacles);
  }
  return (mesh, _apart(mesh, reference));
}

double _lowest(ClothMesh m) => <double>[
  for (var i = 0; i < m.particleCount; i++) m.positions[3 * i + 1],
].reduce(math.min);

void main() {
  test('the run\'s backend makes its cloth: the core\'s, or the '
      'reference\'s when the build asks for it', () async {
    final was = PhysicsBackend.current;
    addTearDown(() => PhysicsBackend.current = was);
    await startPhysics();
    final cloth = PhysicsBackend.current.cloth(_sheet());
    addTearDown(cloth.dispose);
    expect(
      cloth,
      askedPhysics == 'dart' ? isA<DartCloth>() : isA<NativeClothSimulation>(),
    );
    // A backend with no cloth of its own gets the reference's.
    expect(const DartPhysics().cloth(_sheet()), isA<DartCloth>());
  });

  test('a curtain hangs from its top row where the reference hangs it, the '
      'pinned row not moved by a bit', () {
    final mesh = _sheet(height: 1.5);
    final top = Float64List.fromList(mesh.positions.sublist(0, 3 * 12));
    final (core, apart) = _both(mesh, 90);
    expect(apart, lessThan(5e-3));
    expect(core.positions.sublist(0, 3 * 12), top);
    expect(_lowest(core), lessThan(1.5 - 0.8));
  });

  test('a sheet made stretched pulls back to its own rest lengths, not to '
      'the ones it was made at', () {
    final mesh = _sheet(free: true);
    for (var k = 0; k < mesh.positions.length; k++) {
      mesh.positions[k] *= 1.1;
    }
    final (core, apart) = _both(
      mesh,
      30,
      settings: const ClothSettings(gravity: 0.0),
    );
    expect(apart, lessThan(5e-3));
    // Mutation: the core keeping the lengths it was made at.
    final a = 3 * 1, b = 3 * 2;
    final edge = Vector3(
      core.positions[a] - core.positions[b],
      core.positions[a + 1] - core.positions[b + 1],
      core.positions[a + 2] - core.positions[b + 2],
    ).length;
    expect(edge, closeTo(0.09, 0.01));
  });

  test('a sheet folded onto itself on a floor keeps its layers a spacing '
      'apart, as the reference does', () {
    final mesh = _sheet(free: true, height: 0.1);
    // The far half laid back over the near one, five centimetres above it:
    // closer than the sheet's own spacing, which self-collision keeps.
    for (var row = 6; row < 12; row++) {
      for (var col = 0; col < 12; col++) {
        final i = row * 12 + col;
        mesh.positions[3 * i + 1] = 0.15;
        mesh.positions[3 * i + 2] = (11 - row) * 0.09 - 0.495;
      }
    }
    final floor = ClothObstacle(
      CollisionBox(Vector3(2.0, 0.5, 2.0)),
      Vector3(0.0, -0.5, 0.0),
    );
    final (core, apart) = _both(
      mesh,
      30,
      settings: const ClothSettings(friction: 0.5),
      obstacles: <ClothObstacle>[floor],
    );
    expect(apart, lessThan(5e-3));
    // Mutation: self-collision left out of the core's step.
    final over = 9 * 12 + 6, under = 2 * 12 + 6;
    expect(
      core.positions[3 * over + 1] - core.positions[3 * under + 1],
      greaterThan(0.08),
    );
  });

  test('a flag pinned by two corners blows in the wind as the reference '
      'blows it', () {
    const settings = ClothSettings(
      wind: WindSettings(velocityZ: 3.0, drag: 4.0),
    );
    final (still, _) = _both(_sheet(pinCorners: true), 60);
    final (blown, apart) = _both(
      _sheet(pinCorners: true),
      60,
      settings: settings,
    );
    expect(apart, lessThan(5e-3));
    // Mutation: the wind left out of the core's prediction.
    final last = 3 * (blown.particleCount - 1) + 2;
    expect(blown.positions[last] - still.positions[last], greaterThan(0.02));
  });

  test('a sheet dropped on a ball lies on it as on the reference, and '
      'never inside it', () {
    final ball = ClothObstacle(CollisionSphere(0.3), Vector3(0.0, 0.3, 0.0));
    final (core, apart) = _both(
      _sheet(free: true),
      45,
      settings: const ClothSettings(friction: 0.5),
      obstacles: <ClothObstacle>[ball],
    );
    expect(apart, lessThan(5e-3));
    var nearest = double.infinity;
    for (var i = 0; i < core.particleCount; i++) {
      nearest = math.min(
        nearest,
        Vector3(
          core.positions[3 * i],
          core.positions[3 * i + 1],
          core.positions[3 * i + 2],
        ).distanceTo(ball.position),
      );
    }
    expect(nearest, greaterThan(0.3 + 0.01 - 1e-4));
  });

  test('on a box, a capsule and a wedge as on the reference', () {
    for (final shape in <CollisionShape>[
      CollisionBox(Vector3(0.25, 0.25, 0.25)),
      CollisionCapsule(radius: 0.2, halfHeight: 0.15),
      CollisionWedge(Vector3(0.3, 0.25, 0.3)),
    ]) {
      final at = ClothObstacle(shape, Vector3(0.0, 0.25, 0.0));
      final (core, apart) = _both(
        _sheet(free: true),
        45,
        settings: const ClothSettings(friction: 0.5),
        obstacles: <ClothObstacle>[at],
      );
      expect(apart, lessThan(5e-3), reason: '$shape');
      // Held up by it: the middle of the sheet well above the floor of
      // nothing it would otherwise have fallen to.
      expect(core.positions[3 * (6 * 12 + 6) + 1], greaterThan(0.3));
    }
  });

  test('on a heightfield as on the reference, lying on the ground', () {
    final heights = Float32List.fromList(<double>[
      for (var row = 0; row < 5; row++)
        for (var column = 0; column < 5; column++)
          column == 2 && row == 2 ? 0.3 : 0.1 * column,
    ]);
    final field = CollisionHeightfield(
      columns: 5,
      rows: 5,
      cellSize: 0.5,
      heights: heights,
    );
    final ground = ClothObstacle(field, Vector3(0.0, 0.2, 0.0));
    final (core, apart) = _both(
      _sheet(free: true, height: 1.0),
      60,
      settings: const ClothSettings(friction: 0.8),
      obstacles: <ClothObstacle>[ground],
    );
    expect(apart, lessThan(5e-3));
    for (var i = 0; i < core.particleCount; i++) {
      final x = core.positions[3 * i], z = core.positions[3 * i + 2];
      expect(
        core.positions[3 * i + 1],
        greaterThan(field.heightAt(ground.position, x, z) + 0.01 - 1e-4),
      );
    }
  });

  test('a particle carried or pinned through the mesh is carried on the '
      'core, and a disposed simulation says so', () {
    final mesh = _sheet(height: 1.5);
    final cloth = NativeClothSimulation(mesh);
    // Unpin one end of the top row and carry the other up a metre.
    mesh.invMass[11] = 1 / 0.05;
    mesh.positions[1] += 1.0;
    for (var i = 0; i < 30; i++) {
      cloth.step(const ClothSettings(), _dt);
    }
    expect(mesh.positions[1], 2.5);
    // The row under the carried end is pulled up after it, and the end let
    // go of moves. Mutation: the inverse masses not handed to the core.
    expect(mesh.positions[3 * 12 + 1], greaterThan(2.0));
    expect(mesh.velocities[3 * 11 + 1], isNot(0.0));
    cloth.dispose();
    expect(() => cloth.step(const ClothSettings(), _dt), throwsStateError);
    cloth.dispose();
  });
}
