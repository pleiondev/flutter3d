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

/// A walk whose root strides 1.5 along +z a second.
AnimationClip _walkClip() => AnimationClip(
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
);

/// One node at rest at the origin.
Pose _pose() => Pose(
  parents: const <int>[-1],
  restTranslations: Float32List(3),
  restRotations: Float32List.fromList(<double>[0, 0, 0, 1]),
  restScales: Float32List.fromList(<double>[1, 1, 1]),
);

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
  clips: <AnimationClip>[_walkClip()],
  pose: _pose(),
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
    write: (actor, graph, wish) => graph.parameters.setFloat('speed', 1.0),
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
  test('a gesture fires its cue on the graph, and the machine plays it', () {
    // A graph that walks, and plays a jump once on `cue:jump`, back to its
    // walk when the jump is done.
    AnimationGraph gesturing(Actor actor) => AnimationGraph(
      machine: AnimationStateMachine(
        parameters: AnimationParameterSchema(const <AnimationParameter>[
          AnimationParameter.trigger('cue:jump'),
        ]),
        entry: 'walk',
        states: const <AnimationState>[
          AnimationState(name: 'walk', clip: 'walk'),
          AnimationState(name: 'jump', clip: 'walk', wrap: AnimationWrap.once),
        ],
        transitions: <AnimationTransition>[
          AnimationTransition(
            from: 'walk',
            to: 'jump',
            conditions: const <AnimationCondition>[
              TriggerCondition('cue:jump'),
            ],
          ),
          AnimationTransition(from: 'jump', to: 'walk', exitTime: 1.0),
        ],
      ),
      clips: <AnimationClip>[_walkClip()],
      pose: _pose(),
    );
    final world = CollisionWorld()
      ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0));
    final animations = ActorAnimations(graphFor: gesturing);
    final system = ActorSystem(world: world, random: GameRandom(1))
      ..strides = animations;
    final actor = system.spawn(
      body: CharacterController(world: world, position: Vector3(0, 0.9, 0)),
      facing: Facing(),
    );
    void step() => system
      ..beginStep()
      ..step(_dt, focus: Vector3(0, -50, 0));

    // Before its first step: the graph is made for the gesture.
    system.gesture(actor, 'jump');
    step();
    // Mutation: firing the gesture's own name rather than its `cue:` lands
    // on no parameter, and the walk goes on.
    expect(animations.graphOf(actor)!.state, 'jump');
    // A gesture the machine has no cue for is nothing, not an error.
    system.gesture(actor, 'dance');
    for (var i = 0; i < 90; i++) {
      step();
    }
    expect(animations.graphOf(actor)!.state, 'walk');
  });

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
                'actors': live.system.save(),
                'body': live.walker.body!.save(),
              }),
            )
            as Map<String, Object?>;
    final ahead = run(live, 100);

    final again = _stage(wallAt: 2.5);
    again.walker.body!.restore(saved['body']! as Map<String, Object?>);
    again.system.restore(saved['actors']);
    expect(run(again, 100), ahead);
  });

  test('made on an actor\'s first step, and made again by a restore that '
      'needs it', () {
    ActorAnimations made(GameEvents events) => ActorAnimations(
      events: events,
      write: (actor, graph, wish) => graph.parameters.setFloat('speed', 1.0),
      graphFor: (actor) => actor.yaw == 0.0 ? null : _walking(),
    );
    final live = _stage(wallAt: 2.5);
    final animations = made(live.events);
    live.system.strides = animations;
    expect(animations.graphOf(live.walker), isNull, reason: 'not stepped yet');
    _step(live.system, 1);
    expect(animations.graphOf(live.walker), isNotNull);
    _step(live.system, 46);
    final saved =
        jsonDecode(
              jsonEncode(<String, Object?>{
                'actors': live.system.save(),
                'body': live.walker.body!.save(),
              }),
            )
            as Map<String, Object?>;
    final ahead = <String>[
      for (var i = 0; i < 60; i++)
        (() {
          _step(live.system, 1);
          return '${live.walker.body!.position.storage.toList()}';
        })(),
    ];

    final again = _stage(wallAt: 2.5);
    final restored = made(again.events);
    again.system.strides = restored;
    again.walker.body!.restore(saved['body']! as Map<String, Object?>);
    again.system.restore(saved['actors']);
    expect(restored.graphOf(again.walker)!.stateTime, greaterThan(0.0));
    expect(<String>[
      for (var i = 0; i < 60; i++)
        (() {
          _step(again.system, 1);
          return '${again.walker.body!.position.storage.toList()}';
        })(),
    ], ahead);

    // Restored to before its first step, it has no graph until it takes it.
    again.system.restore(<String, Object?>{'tick': 0});
    expect(restored.graphOf(again.walker), isNull);
  });

  test('a body its stride moves leaves its idle when its brain asks', () {
    // The graph stands until `speed` passes 0.3, then walks. Asked from the
    // body's velocity, a body that only its walk moves would stand for ever:
    // standing, its velocity is nought. Asked from the brain's wish, it goes.
    AnimationGraph standThenWalk() {
      return AnimationGraph(
        machine: AnimationStateMachine(
          parameters: AnimationParameterSchema(const <AnimationParameter>[
            AnimationParameter.float('speed'),
          ]),
          entry: 'stand',
          states: const <AnimationState>[
            AnimationState(name: 'stand', clip: 'stand'),
            AnimationState(name: 'walk', clip: 'walk'),
          ],
          transitions: <AnimationTransition>[
            AnimationTransition(
              from: 'stand',
              to: 'walk',
              conditions: const <AnimationCondition>[
                CompareCondition('speed', AnimationComparison.greater, 0.3),
              ],
            ),
          ],
        ),
        clips: <AnimationClip>[
          AnimationClip(name: 'stand', tracks: const <AnimationTrack>[]),
          _walkClip(),
        ],
        pose: _pose(),
      )..rootNode = 0;
    }

    double walked(void Function(Actor, AnimationGraph, Vector3) write) {
      final world = CollisionWorld()
        ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0));
      final system = ActorSystem(world: world, random: GameRandom(1));
      final walker = system.spawn(
        body: CharacterController(world: world, position: Vector3(0, 0.9, 0)),
        facing: Facing(yaw: -math.pi / 2),
        brain: _Ahead(),
      );
      system.strides = ActorAnimations(write: write)
        ..attach(walker, standThenWalk());
      _step(system, 60);
      return walker.body!.position.x;
    }

    expect(
      walked((actor, graph, wish) {
        final v = actor.body!.velocity;
        graph.parameters.setFloat('speed', Vector2(v.x, v.z).length);
      }),
      closeTo(0.0, 1e-3),
      reason: 'asked from its velocity, it never leaves its idle',
    );
    expect(
      walked(
        (actor, graph, wish) =>
            graph.parameters.setFloat('speed', 1.5 * wish.length),
      ),
      greaterThan(1.0),
    );
  });
}

/// Asks to go along +x, always.
final class _Ahead extends Brain {
  @override
  void act(Mind it) => it.steer(Vector3(1.0, 0.0, 0.0));
}
