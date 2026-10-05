/// Actors directed by a cutscene: walked to their marks over the navigation
/// mesh, turned, held, and handed back to their brains.
///
///     dart test test/cutscene_actors_test.dart
library;

import 'dart:convert';

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

Brush _box(double x0, double y0, double z0, double x1, double y1, double z1) =>
    Brush(
      centre: Vector3((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
      size: Vector3(x1 - x0, y1 - y0, z1 - z0),
    );

/// Two rooms either side of a wall, the doorway at its north end.
List<Brush> _rooms() => <Brush>[
  _box(-6, -1, -4, 6, 0, 4),
  _box(0, 0, -4, 0.5, 3, 1.5),
  _box(0, 2.5, 1.5, 0.5, 3, 3.5),
  _box(0, 0, 3.5, 0.5, 3, 4),
];

/// The guard's own wish: stand at its post in the west room.
final BehaviourTree _guarding = BehaviourTree.read(const <String, Object?>{
  'kind': 'goTo',
  'key': 'post',
  'within': 0.3,
}, BehaviourKinds()).tree!;

/// Four seconds: the guard sent through the doorway to the east room, made
/// to look north there, and released a second before the end.
const Map<String, Object?> _scene = <String, Object?>{
  'seconds': 4,
  'actors': <Object?>[
    <String, Object?>{
      't': 0,
      'actor': 'guard',
      'do': 'goTo',
      'at': <double>[4, 0.9, -2],
    },
    <String, Object?>{
      't': 2.5,
      'actor': 'guard',
      'do': 'face',
      'at': <double>[4, 0.9, 3],
    },
    <String, Object?>{'t': 3, 'actor': 'guard', 'do': 'release'},
  ],
};

final class _Stage {
  _Stage({required bool directed}) {
    for (final brush in _rooms()) {
      world.addBox(brush.centre, brush.size);
    }
    world.update();
    system.navMeshes = <NavMesh>[
      NavMesh.bake(_rooms(), config: const NavMeshConfig(agentRadius: 0.35)),
    ];
    final guard = system.spawn(
      body: CharacterController(world: world, position: Vector3(-4, 0.9, -2)),
      brain: BehaviourBrain(_guarding),
      facing: Facing(),
      name: 'guard',
    );
    system.entities.set(
      guard.entity,
      Blackboard(
        values: <String, Object?>{
          'post': <double>[-4, 0.9, -2],
        },
      ),
    );
    if (directed) system.director = player;
  }

  final CollisionWorld world = CollisionWorld();
  late final ActorSystem system = ActorSystem(
    world: world,
    random: GameRandom(2),
  );
  final SequencePlayer player = SequencePlayer(
    Sequence.read(_scene, stepsPerSecond: 60).sequence!,
  );

  Actor get guard => system.actors.single;
  Vector3 get at => guard.body!.position;

  void step() {
    player.advance();
    system
      ..beginStep()
      ..step(_dt, focus: Vector3(0, -50, 0));
  }

  void steps(int n) {
    for (var i = 0; i < n; i++) {
      step();
    }
  }

  Map<String, Object?> state() => <String, Object?>{
    'ecs': system.entities.save(),
    'system': system.save(),
    'cutscene': player.save(),
  };

  void restore(Map<Object?, Object?> state) {
    system.entities.restore((state['ecs']! as Map).cast<String, Object?>());
    system.restore(state['system']);
    player.restore((state['cutscene']! as Map).cast<String, Object?>());
  }
}

double _flat(Vector3 a, double x, double z) {
  final dx = a.x - x;
  final dz = a.z - z;
  return dx * dx + dz * dz;
}

void main() {
  test('the guard is walked through the doorway to its mark', () {
    final stage = _Stage(directed: true)..steps(150);
    expect(_flat(stage.at, 4, -2), lessThan(0.4 * 0.4));
    // And stands there. Mutation: steering at the mark from on it paces
    // the guard back and forth across it at full speed.
    expect(stage.guard.body!.velocity.length, lessThan(0.5));
  });

  test('and stays at its post when nobody directs it', () {
    // Mutation: an actor system that asks the brain whatever the director
    // says leaves the guard at its post here too.
    final stage = _Stage(directed: false)..steps(150);
    expect(_flat(stage.at, -4, -2), lessThan(0.4 * 0.4));
  });

  test('it is turned to look where it is told, standing', () {
    final stage = _Stage(directed: true)..steps(175);
    final facing = stage.guard.facing!;
    // Facing north, +z: a yaw whose forward has a positive z.
    final yaw = facing.yaw;
    expect(Vector2(-Portable.sin(yaw), -Portable.cos(yaw)).y, greaterThan(0.9));
    expect(stage.guard.body!.velocity.length, lessThan(0.5));
  });

  test('released, it goes back to its post on its own', () {
    final stage = _Stage(directed: true)..steps(180);
    final released = stage.at.x;
    expect(released, greaterThan(2.0));
    // Released at three seconds, with a second of the cutscene still to
    // run. Mutation: a director that keeps an actor it has released holds
    // the guard until the cutscene ends.
    stage.steps(50);
    expect(stage.at.x, lessThan(released - 1.0));
    stage.steps(250);
    expect(_flat(stage.at, -4, -2), lessThan(0.4 * 0.4));
  });

  test('a run restored mid-scene steps on to the same bits', () {
    final original = _Stage(directed: true)..steps(70);
    final saved = jsonDecode(jsonEncode(original.state())) as Map;
    final restored = _Stage(directed: true)..restore(saved);
    for (var i = 0; i < 200; i++) {
      original.step();
      restored.step();
      expect(restored.at.storage, original.at.storage, reason: 'step $i');
    }
  });

  test('a gesture is asked for once, on its cue\'s step', () {
    final world = CollisionWorld()
      ..addBox(Vector3(0, -0.5, 0), Vector3(20, 1, 20))
      ..update();
    late SequencePlayer playing;
    final strides = _Gestures(() => playing.step);
    final system = ActorSystem(world: world, random: GameRandom(1))
      ..strides = strides;
    system.spawn(
      body: CharacterController(world: world, position: Vector3(0, 0.9, 0)),
      facing: Facing(),
      name: 'guard',
    );
    final read = Sequence.read(<String, Object?>{
      'seconds': 2,
      'actors': <Object?>[
        <String, Object?>{
          't': 0.5,
          'actor': 'guard',
          'do': 'play',
          'clip': 'Jump',
        },
      ],
    }, stepsPerSecond: 60);
    final player = playing = SequencePlayer(read.sequence!);
    system.director = player;
    for (var i = 0; i < 90; i++) {
      player.advance();
      system
        ..beginStep()
        ..step(_dt, focus: Vector3(0, -50, 0));
    }
    // Mutation: asking on every step the cue holds plays it ninety times.
    expect(strides.asked, <String>['30:guard:Jump']);

    // Restored past it, nothing is asked again.
    final again = playing = SequencePlayer(read.sequence!)
      ..restore(<String, Object?>{'step': 40});
    system.director = again;
    strides.asked.clear();
    for (var i = 0; i < 30; i++) {
      again.advance();
      system
        ..beginStep()
        ..step(_dt, focus: Vector3(0, -50, 0));
    }
    expect(strides.asked, isEmpty);
  });

  test('a play cue names its clip', () {
    final read = Sequence.read(<String, Object?>{
      'seconds': 1,
      'actors': <Object?>[
        <String, Object?>{'t': 0, 'actor': 'guard', 'do': 'play'},
      ],
    }, stepsPerSecond: 60);
    expect(read.problems, <Matcher>[contains('actors[0].clip')]);
  });
}

/// Strides that move nobody and write down every gesture asked for, with
/// the cutscene's step it was asked on.
final class _Gestures extends ActorStrides {
  _Gestures(this.step);

  final List<String> asked = <String>[];
  final int Function() step;

  @override
  Vector3? strideOf(Actor actor, Vector3 wish, double dt) => null;

  @override
  void gesture(Actor actor, String name) =>
      asked.add('${step()}:${actor.name}:$name');
}
