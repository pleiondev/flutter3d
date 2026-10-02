import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  ActorSystem patrolling() {
    final world = CollisionWorld()
      ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0))
      ..update();
    final system = ActorSystem(world: world, random: GameRandom(1));
    final tree = BehaviourTree.read(<String, Object?>{
      'kind': 'sequence',
      'name': 'patrol',
      'children': <Object?>[
        <String, Object?>{'kind': 'goTo', 'key': 'post'},
        <String, Object?>{'kind': 'wait', 'seconds': 1},
      ],
    }, BehaviourKinds()).tree!;
    final actor = system.spawn(
      body: CharacterController(world: world, position: Vector3(0, 0.9, 0)),
      brain: BehaviourBrain(tree),
      name: 'guard',
    );
    system.entities.set(
      actor.entity,
      Blackboard(
        values: <String, Object?>{
          'post': <double>[5.0, 0.9, 0.0],
        },
      ),
    );
    return system;
  }

  test('draws a stroke per node on the path and a line to the goal', () {
    final system = patrolling();
    system
      ..beginStep()
      // Inside the close range, so the actor thinks on the first step.
      ..step(1 / 60, focus: Vector3(0, 0.9, 10));
    final lines = DebugDraw();
    BehaviourOverlay(system).draw(lines);
    // Mutation: drawing only the leaf leaves the sequence out, and the
    // picture no longer says which branch the leaf belongs to.
    expect(lines.lineCount, 3);
    expect(BehaviourOverlay(system).describe(), <String>[
      'guard: patrol › goTo (running)',
    ]);
  });

  test('an actor that has not decided yet is not drawn, and gets no board', () {
    final system = patrolling();
    final fresh = system.spawn(
      body: CharacterController(
        world: system.world,
        position: Vector3(3, 0.9, 3),
      ),
      brain: BehaviourBrain(
        BehaviourTree.read(<String, Object?>{
          'kind': 'wait',
          'seconds': 1,
        }, BehaviourKinds()).tree!,
      ),
    );
    final lines = DebugDraw();
    BehaviourOverlay(system).draw(lines);
    expect(lines.lineCount, 0);
    // Mutation: an overlay that made a board to read it would put a
    // component in the next snapshot just by being switched on.
    expect(system.entities.has<Blackboard>(fresh.entity), isFalse);
  });
}
