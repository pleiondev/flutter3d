/// Actors' animation graphs stepped by the simulation — N1.
///
///     flutter test test/actor_animations_test.dart
///
/// An actor with a walk whose root strides forward, attached to the actor
/// system's step: the stride walks its body the way it faces, a wall stops
/// it, each footfall arrives as a game event in the step it happened, and a
/// run restored from a save steps on to the same place and the same steps.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' hide Pose;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// A walk whose root strides 1.5 along the model's +z a second, with a
/// footfall at each half.
AnimationGraph _walking() => AnimationGraph(
  machine: AnimationStateMachine(
    parameters: AnimationParameterSchema(const <AnimationParameter>[
      AnimationParameter.float('speed'),
    ]),
    entry: 'walk',
    states: const <AnimationState>[
      AnimationState(
        name: 'walk',
        clip: 'walk',
        markers: <AnimationMarker>[
          AnimationMarker(0.25, 'step'),
          AnimationMarker(0.75, 'step'),
        ],
      ),
    ],
    transitions: const <AnimationTransition>[],
  ),
  clips: <AnimationClip>[
    AnimationClip(
      name: 'walk',
      tracks: <AnimationTrack>[
        AnimationTrack(
          nodeIndex: 0,
          path: AnimationPath.translation,
          interpolation: AnimationInterpolation.linear,
          times: Float32List.fromList(<double>[0.0, 1.0]),
          values: Float32List.fromList(<double>[0, 0, 0, 0, 0, 1.5]),
          componentCount: 3,
        ),
      ],
    ),
  ],
  pose: Pose(
    parents: const <int>[-1],
    restTranslations: Float32List(3),
    restRotations: Float32List.fromList(<double>[0, 0, 0, 1]),
    restScales: Float32List.fromList(<double>[1, 1, 1]),
  ),
)..rootNode = 0;

/// A floor, perhaps a wall across +x at [wallAt], and one walker facing
/// +x — yaw a quarter turn clockwise, since yaw nought looks along -z.
({
  ActorSystem system,
  Actor walker,
  ActorAnimations animations,
  GameEvents events,
})
_stage({double? wallAt, double scale = 1.0}) {
  final world = CollisionWorld()
    ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0));
  if (wallAt != null) {
    world.addBox(Vector3(wallAt + 0.5, 1.0, 0.0), Vector3(1.0, 2.0, 4.0));
  }
  final events = GameEvents();
  final system = ActorSystem(world: world, random: GameRandom(1));
  final walker = system.spawn(
    body: CharacterController(world: world, position: Vector3(0, 0.9, 0)),
    facing: Facing(yaw: -math.pi / 2),
  );
  final animations = ActorAnimations(
    events: events,
    write: (actor, parameters) => parameters.setFloat('speed', 1.0),
  )..attach(walker, _walking(), scale: scale);
  system.strides = animations;
  return (
    system: system,
    walker: walker,
    animations: animations,
    events: events,
  );
}

void _step(ActorSystem system, int steps) {
  for (var i = 0; i < steps; i++) {
    system
      ..beginStep()
      ..step(_dt, focus: Vector3(0.0, 0.0, 30.0));
  }
}

void main() {
  test('the stride walks the body the way it faces, at the model\'s size', () {
    final s = _stage(scale: 2.0);
    _step(s.system, 60);
    // A second of 1.5 along the model's z, drawn twice its size: 3 m along
    // the world's +x, where the actor faces.
    expect(s.walker.body!.position.x, closeTo(3.0, 1e-3));
    expect(s.walker.body!.position.z.abs(), lessThan(1e-3));
  });

  test('a wall stops it, the walk going on', () {
    final s = _stage(wallAt: 2.0);
    _step(s.system, 180);
    expect(
      s.walker.body!.position.x,
      closeTo(2.0 - s.walker.body!.halfExtents.x, 0.01),
    );
    expect(s.animations.graphOf(s.walker)!.rootDelta.z, greaterThan(0.0));
  });

  test('each footfall is a game event of the step it fell in', () {
    final s = _stage();
    final perStep = <int>[];
    for (var i = 0; i < 120; i++) {
      _step(s.system, 1);
      perStep.add(
        s.events.drain().whereType<AnimationMarkerPassed>().where((e) {
          expect(e.actor, s.walker);
          return e.marker == 'step';
        }).length,
      );
    }
    // Two a second, at a quarter and three quarters of the cycle.
    expect(perStep.where((n) => n > 0), hasLength(4));
    expect(perStep[14] + perStep[15], 1, reason: 'the first near step 15');
  });

  test('a run restored from a save steps on to the same place and steps', () {
    List<String> run(
      ({
        ActorSystem system,
        Actor walker,
        ActorAnimations animations,
        GameEvents events,
      })
      s,
      int steps,
    ) => <String>[
      for (var i = 0; i < steps; i++)
        (() {
          _step(s.system, 1);
          return '${s.walker.body!.position.storage.toList()}'
              '${s.events.drain().map((e) => e.name).toList()}';
        })(),
    ];

    final live = _stage(wallAt: 2.5);
    run(live, 47);
    final saved =
        jsonDecode(
              jsonEncode(<String, Object?>{
                'animations': live.animations.save(),
                'body': live.walker.body!.save(),
              }),
            )
            as Map<String, Object?>;
    final ahead = run(live, 100);

    final again = _stage(wallAt: 2.5);
    again.walker.body!.restore(saved['body']! as Map<String, Object?>);
    again.animations.restore(saved['animations']);
    expect(run(again, 100), ahead);
  });
}
