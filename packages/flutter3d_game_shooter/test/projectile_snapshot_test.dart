/// A save that is missing something loads without the rocket, not without the
/// game.
///
///     flutter test test/projectile_snapshot_test.dart
///
/// **The one restore in this repository that threw.** `Snapshot`'s own rule is
/// that a missing field takes its default and an unknown one is ignored, and
/// every other `restore` in the three genre packages follows it. This one read
/// `row['life']! as num`, so a save written before the field existed — or one
/// truncated, or one from a build where a rocket had no blast — took the whole
/// game down on load rather than one projectile.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

ProjectileSystem _system() => ProjectileSystem(world: CollisionWorld());

void main() {
  test('a whole rocket survives the round trip', () {
    // The other half: leniency that dropped everything would pass every test
    // below and lose the game's state.
    final system = _system();
    system.spawn(
      position: Vector3(1.0, 2.0, 3.0),
      direction: Vector3(0.0, 0.0, 1.0),
      speed: 30.0,
      blast: const Blast(radius: 4.0, damage: 60.0),
    );

    final saved = system.entities.save();
    final loaded = _system()..entities.restore(saved);

    final rocket = loaded.entities
        .query<InFlight>()
        .map((Entity e) => loaded.entities.get<InFlight>(e)!)
        .single;
    expect(rocket.position.x, closeTo(1.0, 1e-6));
    expect(rocket.blast.damage, 60.0);
  });

  test('and a row with no blast is one rocket lost, not a crash', () {
    final system = _system();
    system.spawn(
      position: Vector3.zero(),
      direction: Vector3(0.0, 0.0, 1.0),
      speed: 30.0,
      blast: const Blast(radius: 4.0, damage: 60.0),
    );

    final saved = system.entities.save();
    // Take the blast out, the way a save from a build without one would.
    final components = saved['components']! as Map;
    final rows = (components['inFlight']! as Map).values.first as Map;
    rows.remove('blast');

    final loaded = _system();
    expect(() => loaded.entities.restore(saved), returnsNormally);
    expect(
      loaded.entities.query<InFlight>(),
      isEmpty,
      reason: 'a rocket that cannot be read is not a rocket at the origin',
    );
  });

  test('and a row with no place is not a rocket at the origin', () {
    // The other half of leniency, and the half that is easy to get wrong:
    // shrugging at a missing *position* would spawn a live rocket at the world
    // origin, which flies off and detonates on whatever is standing there. A
    // row without a place is not a rocket.
    final system = _system();
    system.spawn(
      position: Vector3(5.0, 1.0, 0.0),
      direction: Vector3(0.0, 0.0, 1.0),
      speed: 30.0,
      blast: const Blast(radius: 4.0, damage: 60.0),
    );

    final saved = system.entities.save();
    final components = saved['components']! as Map;
    final rows = (components['inFlight']! as Map).values.first as Map;
    rows.remove('at');

    final loaded = _system()..entities.restore(saved);

    expect(loaded.entities.query<InFlight>(), isEmpty);
  });

  test('and a row that is not a row at all is the same', () {
    final loaded = _system();

    expect(
      () => loaded.entities.restore(<String, Object?>{
        'generations': <int>[0],
        'free': <int>[],
        'components': <String, Object?>{
          'inFlight': <String, Object?>{'0': 'this is not a rocket'},
        },
      }),
      returnsNormally,
    );
    expect(loaded.entities.query<InFlight>(), isEmpty);
  });
}
