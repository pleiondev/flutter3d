/// How much of a sound the walls let through.
///
///     flutter test test/sound_occlusion_test.dart
///
/// The three-room level again: a doorway between A and B, a wall between B
/// and C. A sound heard through the doorway is clear, through one wall it is
/// halved, through two it is quartered, and past four it stops falling.
library;

import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart' show CollisionBox;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

Brush _box(double x, double y, double z, double sx, double sy, double sz) =>
    Brush(center: Vector3(x, y, z), size: Vector3(sx, sy, sz));

/// Rooms A (x 0..8), B (x 10..18) and C (x 20..28); a doorway at z 3..5
/// between A and B, a solid wall between B and C.
Level _rooms() => Level(
  brushes: <Brush>[
    _box(14.0, -0.5, 4.0, 30.0, 1.0, 10.0),
    _box(14.0, 4.5, 4.0, 30.0, 1.0, 10.0),
    _box(14.0, 2.0, -0.5, 30.0, 4.0, 1.0),
    _box(14.0, 2.0, 8.5, 30.0, 4.0, 1.0),
    _box(-0.5, 2.0, 4.0, 1.0, 4.0, 8.0),
    _box(28.5, 2.0, 4.0, 1.0, 4.0, 8.0),
    _box(9.0, 2.0, 1.5, 2.0, 4.0, 3.0),
    _box(9.0, 2.0, 6.5, 2.0, 4.0, 3.0),
    _box(19.0, 2.0, 4.0, 2.0, 4.0, 8.0),
  ],
);

CollisionWorld _world() {
  final world = CollisionWorld();
  _rooms().addTo(world);
  world.update();
  return world;
}

/// The wall between A and B below the doorway (x 8..10, z 0..3), alone and
/// made of [material].
CollisionWorld _walled(PhysicalMaterial material) {
  final world = CollisionWorld()
    ..add(
      Collider(
        shape: CollisionBox(Vector3(1.0, 2.0, 1.5)),
        position: Vector3(9.0, 2.0, 1.5),
        layer: CollisionLayers.world,
        material: material,
      ),
    );
  world.update();
  return world;
}

/// A fixture whose impedance falls as it warms, from 1.6 MRayl at 20 °C to
/// 0.4 at 100 °C, and which has no absorption to read first.
const PhysicalMaterial _softening = PhysicalMaterial(
  id: 'test.softening',
  name: 'softening',
  phase: MaterialPhase.solid,
  acoustic: AcousticProperties(
    impedance: TableLaw(
      1.6e6,
      xs: <double>[293.15, 373.15],
      ys: <double>[1.6e6, 4.0e5],
    ),
    source: 'a test fixture',
  ),
);

/// A fixture with no acoustic group at all.
const PhysicalMaterial _mute = PhysicalMaterial(
  id: 'test.mute',
  name: 'mute',
  phase: MaterialPhase.solid,
);

void main() {
  test('a sound through the doorway is clear', () {
    final occlusion = SoundOcclusion(_world());

    expect(
      occlusion.between(Vector3(14.0, 1.5, 4.0), Vector3(2.0, 1.5, 4.0)),
      1.0,
    );
    expect(occlusion.lastObstacles, 0);
  });

  test('one wall halves it, two quarter it', () {
    final occlusion = SoundOcclusion(_world());

    // B to A past the doorway's edge: through the wall at x 8..10.
    expect(
      occlusion.between(Vector3(14.0, 1.5, 1.0), Vector3(2.0, 1.5, 1.0)),
      0.5,
    );
    expect(occlusion.lastObstacles, 1);
    // C to A: the B–C wall and then the A–B wall.
    expect(
      occlusion.between(Vector3(24.0, 1.5, 1.0), Vector3(2.0, 1.5, 1.0)),
      0.25,
    );
    expect(occlusion.lastObstacles, 2);
  });

  test('is the same from either end', () {
    // Pure, and symmetric: a replay has to sound the way the run did, and
    // the ear and the torch trading places changes nothing about the walls.
    final occlusion = SoundOcclusion(_world());
    final there = occlusion.between(
      Vector3(24.0, 1.5, 1.0),
      Vector3(2.0, 1.5, 1.0),
    );
    final back = occlusion.between(
      Vector3(2.0, 1.5, 1.0),
      Vector3(24.0, 1.5, 1.0),
    );
    expect(back, there);
  });

  test('stops falling at the floor', () {
    // Through the floor, the ceiling and every wall a long diagonal crosses:
    // still audible, faintly, rather than switched off.
    final occlusion = SoundOcclusion(_world(), maxObstacles: 2);

    expect(
      occlusion.between(Vector3(24.0, 1.5, 1.0), Vector3(2.0, 1.5, 1.0)),
      0.25,
      reason: 'two obstacles counted, the cap not yet reached',
    );
    final capped = SoundOcclusion(_world(), floor: 0.3);
    expect(
      capped.between(Vector3(24.0, 1.5, 1.0), Vector3(2.0, 1.5, 1.0)),
      0.3,
    );
  });

  group('a wall made of something', () {
    // The same wall between B and A each time, now with a material. Before
    // the catalogue was read every wall let through `perObstacle`, 0.5,
    // whatever it was made of; the before/after of each is written beside
    // it.
    final from = Vector3(14.0, 1.5, 1.0), to = Vector3(2.0, 1.5, 1.0);
    final air =
        WorldProperties.standard.airDensity *
        WorldProperties.standard.speedOfSound;
    double share(double z) =>
        math.sqrt(4.0 * z * air / ((z + air) * (z + air)));

    test("lets through what its surface's absorption leaves unreflected", () {
      // Mutation: the mean taken over all six bands, or the share used as a
      // gain without its square root.
      final through = <PhysicalMaterial, double>{
        // Was 0.5. (0.01 + 0.015 + 0.02 + 0.02) / 4 = 0.01625 of the
        // energy, √ of it as a gain: −17.9 dB.
        Materials.concrete: math.sqrt(0.065 / 4.0),
        // Was 0.5. (0.1 + 0.05 + 0.04 + 0.07) / 4 = 0.065: −11.9 dB.
        Materials.gypsumBoard: math.sqrt(0.26 / 4.0),
        // Was 0.5. (0.45 + 0.8 + 0.89 + 0.97) / 4 = 0.7775: −1.1 dB.
        Materials.mineralWool: math.sqrt(3.11 / 4.0),
      };
      for (final MapEntry(key: material, value: gain) in through.entries) {
        final occlusion = SoundOcclusion(_walled(material));
        expect(
          occlusion.between(from, to),
          closeTo(gain, 1e-12),
          reason: material.id,
        );
        expect(occlusion.lastObstacles, 1);
      }
    });

    test('with no absorption, by its impedance against the air', () {
      // Steel's entry has a speed of sound and a density and no absorption:
      // 4·Z·Z₀ / (Z + Z₀)² of the energy is not reflected at normal
      // incidence, with Z = ρc its own and Z₀ the world's air's. Was 0.5;
      // now about 0.006, below the floor.
      final steel = Materials.steel;
      final gain = share(steel.density! * steel.acoustic!.speedOfSound!.value);
      expect(gain, lessThan(0.01));

      expect(
        SoundOcclusion(_walled(steel), floor: 0.0).between(from, to),
        closeTo(gain, 1e-15),
      );
      expect(
        SoundOcclusion(_walled(steel)).between(from, to),
        0.06,
        reason: 'below the floor, the floor',
      );
    });

    test("reads the air of the walls' own world", () {
      // Mutation: the standard air whatever the world: the two agree.
      final hot = _walled(Materials.steel)
        ..properties = WorldProperties(airTemperature: 373.15);
      final room = SoundOcclusion(_walled(Materials.steel), floor: 0.0);

      expect(
        SoundOcclusion(hot, floor: 0.0).between(from, to),
        isNot(room.between(from, to)),
      );
    });

    test("reads a law at the wall's own state when one is known", () {
      // Mutation: the reference state whatever the wall's: hot and cold
      // agree.
      final hot = SoundOcclusion(
        _walled(_softening),
        floor: 0.0,
        stateOf: (Collider wall) => MaterialState.at(temperature: 373.15),
      );
      final unknown = SoundOcclusion(
        _walled(_softening),
        floor: 0.0,
        stateOf: (Collider wall) => null,
      );

      expect(
        SoundOcclusion(_walled(_softening), floor: 0.0).between(from, to),
        closeTo(share(1.6e6), 1e-15),
        reason: 'no state known: the law at its reference state',
      );
      expect(unknown.between(from, to), closeTo(share(1.6e6), 1e-15));
      expect(hot.between(from, to), closeTo(share(4.0e5), 1e-15));
    });

    test('with no acoustic group lets through perObstacle', () {
      // Nothing to read: the wall it always was, to the bit.
      expect(SoundOcclusion(_walled(_mute)).between(from, to), 0.5);
      expect(
        SoundOcclusion(_walled(_mute), perObstacle: 0.3).between(from, to),
        0.3,
      );
    });
  });

  test('a sound at the ear is clear', () {
    final occlusion = SoundOcclusion(_world());
    expect(
      occlusion.between(Vector3(2.0, 1.5, 4.0), Vector3(2.0, 1.5, 4.0)),
      1.0,
    );
  });
}
