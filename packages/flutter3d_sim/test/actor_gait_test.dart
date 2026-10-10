/// What the view reads of an actor that its save does not keep: the stair
/// its body climbed and whether it stands on something.
///
///     dart test test/actor_gait_test.dart
///
/// Published, so `ActorVisuals` smooths a staircase from published state as
/// it does from the live body; never saved, so a save and its digest are the
/// bytes they were before it.
library;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

void main() {
  test('an actor with a body publishes its gait', () {
    // Mutation: spawn the body without a `Gait` — `PublishedActor` reads
    // nought for every climb, and a published staircase is drawn in jumps.
    final world = CollisionWorld();
    final system = ActorSystem(world: world, random: GameRandom(1));
    final actor = system.spawn(
      body: CharacterController(world: world),
      health: Health(10),
    );
    final published = system.entities.publishedComponents();
    final gait = published[ActorCodecs.gait.id]?[actor.entity];
    expect(gait, isA<Map<Object?, Object?>>());
    expect((gait! as Map)['steppedUp'], 0.0);

    final state = PublishedState(
      step: 1,
      seconds: 1.0 / 60.0,
      components: <String, Map<Entity, Object?>>{
        for (final MapEntry(:key, :value) in published.entries) key: value,
        ActorCodecs.gait.id: <Entity, Object?>{
          actor.entity: <String, Object?>{'steppedUp': 0.3, 'grounded': false},
        },
      },
    );
    final read = PublishedActor.read(state, actor.entity)!;
    expect(read.steppedUp, 0.3);
    expect(read.isGrounded, isFalse);
    expect(read.isAlive, isTrue);
  });

  test('and does not save it', () {
    // Mutation: register the gait without excluding it — the save gains a
    // `gait` table, and every recorded run's digests move.
    final world = CollisionWorld();
    final system = ActorSystem(world: world, random: GameRandom(1));
    system.spawn(body: CharacterController(world: world));
    final saved = system.entities.save();
    final components = saved['components']! as Map;
    expect(components.containsKey(ActorCodecs.gait.id), isFalse);
    expect(components.containsKey(ActorCodecs.body.id), isTrue);
  });

  test('a row with no gait reads as no climb, standing', () {
    // Mutation: require the gait row — a world published before it, or a
    // genre that spawns bodies by hand, reads no actor at all.
    const entity = Entity.of(0, 0);
    final state = PublishedState(
      step: 1,
      seconds: 1.0 / 60.0,
      components: <String, Map<Entity, Object?>>{
        ActorCodecs.body.id: <Entity, Object?>{
          entity: <String, Object?>{
            'at': <double>[0, 0, 0],
          },
        },
      },
    );
    final read = PublishedActor.read(state, entity)!;
    expect((read.steppedUp, read.isGrounded), (0.0, true));
  });
}
