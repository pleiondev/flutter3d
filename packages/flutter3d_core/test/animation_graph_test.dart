/// The animation graph takes the transitions its parameters say, once, and
/// the same ones on every run — N1.
///
///     dart test test/animation_graph_test.dart
///
/// Every step here is 1/64 s and every fade a power of two, so the weights the
/// tests name are exact rather than close.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 64.0;

/// A one-node clip [length] seconds long holding translation x = [x] and, when
/// [yaw] is given, that rotation about Y.
AnimationClip _clip(String name, double x, {double length = 1.0, double? yaw}) {
  final half = (yaw ?? 0.0) / 2.0;
  final rotation = <double>[0.0, math.sin(half), 0.0, math.cos(half)];
  return AnimationClip(
    name: name,
    tracks: <AnimationTrack>[
      AnimationTrack(
        nodeIndex: 0,
        path: AnimationPath.translation,
        interpolation: AnimationInterpolation.linear,
        times: Float32List.fromList(<double>[0.0, length]),
        values: Float32List.fromList(<double>[x, 0, 0, x, 0, 0]),
        componentCount: 3,
      ),
      if (yaw != null)
        AnimationTrack(
          nodeIndex: 0,
          path: AnimationPath.rotation,
          interpolation: AnimationInterpolation.linear,
          times: Float32List.fromList(<double>[0.0, length]),
          values: Float32List.fromList(<double>[...rotation, ...rotation]),
          componentCount: 4,
        ),
    ],
  );
}

AnimationPose _onePose() => AnimationPose(
  parents: const <int>[-1],
  restTranslations: Float32List(3),
  restRotations: Float32List.fromList(<double>[0, 0, 0, 1]),
  restScales: Float32List.fromList(<double>[1, 1, 1]),
);

final List<AnimationClip> _clips = <AnimationClip>[
  // A rotation track at rest, rather than none: the player fades only a track
  // both clips have, and the graph is compared with it below.
  _clip('idle', 0.0, yaw: 0.0),
  _clip('walk', 10.0, yaw: math.pi / 2.0),
  _clip('attack', 20.0, length: 0.5),
];

AnimationStateMachine _machine({
  List<AnimationTransition> transitions = const <AnimationTransition>[],
}) => AnimationStateMachine(
  parameters: AnimationParameterSchema(const <AnimationParameter>[
    AnimationParameter.float('speed'),
    AnimationParameter.boolean('grounded', initial: true),
    AnimationParameter.integer('stance'),
    AnimationParameter.trigger('attack'),
  ]),
  states: const <AnimationState>[
    AnimationState(name: 'idle', clip: 'idle'),
    AnimationState(name: 'walk', clip: 'walk'),
    AnimationState(name: 'attack', clip: 'attack', wrap: AnimationWrap.once),
  ],
  transitions: transitions,
);

AnimationGraph _graph(List<AnimationTransition> transitions) => AnimationGraph(
  machine: _machine(transitions: transitions),
  clips: _clips,
  pose: _onePose(),
);

/// The yaw [pose]'s node 0 holds, in radians.
double _yaw(AnimationPose pose) =>
    2.0 * math.atan2(pose.rotations[1], pose.rotations[3]);

void main() {
  group('a snapshot', () {
    /// A graph with everything a step changes: a blend, a fade into a
    /// stand, a layer fading in, a look, root motion and markers.
    AnimationGraph busy() {
      AnimationClip walking(String name, double meters, double length) =>
          AnimationClip(
            name: name,
            tracks: <AnimationTrack>[
              AnimationTrack(
                nodeIndex: 0,
                path: AnimationPath.translation,
                interpolation: AnimationInterpolation.linear,
                times: Float32List.fromList(<double>[0.0, length]),
                values: Float32List.fromList(<double>[0, 0, 0, 0, 0.3, meters]),
                componentCount: 3,
              ),
            ],
          );
      final clips = <AnimationClip>[
        walking('walk', 1.5, 1.0),
        walking('run', 3.0, 0.6),
        _clip('stand', 0.0, yaw: 0.4),
      ];
      final graph = AnimationGraph(
        machine: AnimationStateMachine(
          parameters: AnimationParameterSchema(const <AnimationParameter>[
            AnimationParameter.float('speed'),
            AnimationParameter.trigger('stop'),
          ]),
          entry: 'move',
          states: <AnimationState>[
            AnimationState(
              name: 'move',
              blend: AnimationBlendSpace('speed', const <BlendPoint>[
                BlendPoint(0.0, 'walk'),
                BlendPoint(1.0, 'run'),
              ]),
              markers: const <AnimationMarker>[AnimationMarker(0.5, 'step')],
            ),
            const AnimationState(name: 'stand', clip: 'stand'),
          ],
          transitions: <AnimationTransition>[
            AnimationTransition(
              from: 'move',
              to: 'stand',
              conditions: const <AnimationCondition>[TriggerCondition('stop')],
              duration: 0.4,
            ),
          ],
        ),
        clips: clips,
        pose: _onePose(),
      )..rootNode = 0;
      graph.layers.add(
        AnimationGraphLayer(
          graph: AnimationGraph(
            machine: AnimationStateMachine(
              parameters: AnimationParameterSchema(
                const <AnimationParameter>[],
              ),
              entry: 'lean',
              states: const <AnimationState>[
                AnimationState(name: 'lean', clip: 'stand'),
              ],
              transitions: const <AnimationTransition>[],
            ),
            clips: clips,
            pose: _onePose(),
          ),
          blend: AnimationBlend.additive,
          weight: 0.0,
        )..fadeTo(1.0, 2.0),
      );
      graph.goals.add(
        LookGoal(
          joint: 0,
          forward: Vector3(0, 0, 1),
          target: Vector3(3, 0, 1),
          weight: 0.0,
        )..fadeTo(1.0, 0.5),
      );
      return graph;
    }

    /// Steps [graph] from step [from] to [to] of a fixed script, and what
    /// each step gave.
    List<String> play(AnimationGraph graph, int from, int to) => <String>[
      for (var i = from; i < to; i++)
        (() {
          graph.parameters.setFloat('speed', (i % 50) / 50.0);
          if (i == 70) graph.parameters.fire('stop');
          graph.evaluate(1.0 / 60.0);
          return '${graph.pose.translations.toList()}'
              '${graph.pose.rotations.toList()}'
              '${graph.rootDelta.storage.toList()}${graph.passed}';
        })(),
    ];

    test('restored, a graph steps on to the same pose, travel and markers', () {
      final live = busy();
      play(live, 0, 80);
      final saved = jsonDecode(jsonEncode(live.save())) as Map<String, Object?>;
      expect(saved['previous'], 'move', reason: 'saved mid-fade');
      final posed = (
        live.pose.translations.toList(),
        live.pose.rotations.toList(),
      );
      final ahead = play(live, 80, 200);
      // A fresh graph with nothing fading and its head looking elsewhere, so
      // all of it has to come back from the snapshot: the pose made again
      // at once, as it was saved, and the steps after it.
      final again = busy();
      again.layers.first.weight = 0.0;
      again.goals.first.weight = 0.0;
      (again.goals.first as LookGoal).target.setValues(-5.0, 2.0, -5.0);
      again.restore(saved);
      expect(again.state, 'stand');
      expect(again.pose.translations.toList(), posed.$1);
      for (var i = 0; i < posed.$2.length; i++) {
        expect(again.pose.rotations[i], closeTo(posed.$2[i], 1e-6));
      }
      expect(play(again, 80, 200), ahead);
    });

    test('a state it no longer has leaves it in its entry', () {
      final graph = busy()..restore(<String, Object?>{'state': 'gone'});
      expect(graph.state, 'move');
    });
  });

  group('a blend across a plane', () {
    final cross = <BlendPoint>[
      const BlendPoint(0.0, 'forward', y: 1.0),
      const BlendPoint(0.0, 'back', y: -1.0),
      const BlendPoint(1.0, 'right', y: 0.0),
      const BlendPoint(-1.0, 'left', y: 0.0),
    ];
    final clips = <AnimationClip>[
      _clip('forward', 10.0),
      _clip('back', 20.0),
      _clip('right', 30.0),
      _clip('left', 40.0),
    ];

    AnimationGraph strafing() => AnimationGraph(
      machine: AnimationStateMachine(
        parameters: AnimationParameterSchema(const <AnimationParameter>[
          AnimationParameter.float('side'),
          AnimationParameter.float('ahead'),
        ]),
        entry: 'move',
        states: <AnimationState>[
          AnimationState(
            name: 'move',
            blend: AnimationBlendSpace('side', cross, across: 'ahead'),
          ),
        ],
        transitions: const <AnimationTransition>[],
      ),
      clips: clips,
      pose: _onePose(),
    );

    double xAt(double side, double ahead) {
      final graph = strafing();
      graph.parameters
        ..setFloat('side', side)
        ..setFloat('ahead', ahead);
      return graph.evaluate(_dt).translations[0];
    }

    test('plays one clip standing on its point', () {
      expect(xAt(1.0, 0.0), closeTo(30.0, 1e-4));
      expect(xAt(0.0, -1.0), closeTo(20.0, 1e-4));
    });

    test('mixes every point by the inverse square of its distance', () {
      expect(xAt(0.0, 0.0), closeTo(25.0, 1e-4), reason: 'all four alike');
      // At (0.5, 0.5): squared distances 0.5, 2.5, 0.5, 2.5.
      expect(xAt(0.5, 0.5), closeTo(104.0 / 4.8, 1e-4));
    });

    test('says what stops one running', () {
      List<String> problems(AnimationBlendSpace blend) => AnimationStateMachine(
        parameters: AnimationParameterSchema(const <AnimationParameter>[
          AnimationParameter.float('side'),
          AnimationParameter.float('ahead'),
        ]),
        entry: 'move',
        states: <AnimationState>[AnimationState(name: 'move', blend: blend)],
        transitions: const <AnimationTransition>[],
      ).problems(clips);
      expect(
        problems(AnimationBlendSpace('side', cross, across: 'ahead')),
        isEmpty,
      );
      expect(
        problems(AnimationBlendSpace('side', cross, across: 'up')).single,
        contains('`up`, which is not a parameter'),
      );
      expect(
        problems(
          AnimationBlendSpace('side', const <BlendPoint>[
            BlendPoint(0.0, 'forward', y: 1.0),
            BlendPoint(0.0, 'back', y: 1.0),
          ], across: 'ahead'),
        ).single,
        contains('a place of its own'),
      );
    });
  });

  group('root motion', () {
    test('under a turned, scaled armature, along the pose\'s floor', () {
      // A Z-up rig in centimetres: the armature turned a quarter about x so
      // its z stands up, and drawn at a hundredth. The root walks 150 cm a
      // second along its own -y — the pose's +z — and bobs 10 cm along its
      // own z — the pose's up. Read in the root's own parent's space, the
      // stride was 150 along y and the bob was pinned away as floor.
      final turn = Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), -math.pi / 2);
      final graph = AnimationGraph(
        machine: AnimationStateMachine(
          parameters: AnimationParameterSchema(const <AnimationParameter>[]),
          entry: 'walk',
          states: const <AnimationState>[
            AnimationState(name: 'walk', clip: 'walk'),
          ],
          transitions: const <AnimationTransition>[],
        ),
        clips: <AnimationClip>[
          AnimationClip(
            name: 'walk',
            tracks: <AnimationTrack>[
              AnimationTrack(
                nodeIndex: 1,
                path: AnimationPath.translation,
                interpolation: AnimationInterpolation.linear,
                times: Float32List.fromList(<double>[0.0, 0.5, 1.0]),
                values: Float32List.fromList(<double>[
                  20, 0, 90, //
                  20, -75, 100, //
                  20, -150, 90,
                ]),
                componentCount: 3,
              ),
            ],
          ),
        ],
        pose: AnimationPose(
          parents: const <int>[-1, 0],
          restTranslations: Float32List.fromList(<double>[0, 0, 0, 20, 0, 90]),
          restRotations: Float32List.fromList(<double>[
            turn.x, turn.y, turn.z, turn.w, //
            0, 0, 0, 1,
          ]),
          restScales: Float32List.fromList(<double>[0.01, 0.01, 0.01, 1, 1, 1]),
        ),
      )..rootNode = 1;
      final restAt = graph.pose.restCopy().worldMatrices()[1].getTranslation();
      var travelled = Vector3.zero();
      for (var i = 0; i < 30; i++) {
        graph.evaluate(1.0 / 60.0);
        travelled += graph.rootDelta;
      }
      expect(travelled.z, closeTo(0.75, 1e-4), reason: 'half a second');
      expect(travelled.x.abs(), lessThan(1e-5));
      expect(travelled.y, 0.0);
      final at = graph.pose.worldMatrices()[1].getTranslation();
      expect(at.x, closeTo(restAt.x, 1e-5), reason: 'held over rest');
      expect(at.z, closeTo(restAt.z, 1e-5), reason: 'held over rest');
      expect(
        at.y,
        closeTo(1.0, 1e-4),
        reason: 'the bob, a metre up at mid-cycle',
      );
    });

    /// A one-node clip whose root walks [meters] along z over [length]
    /// seconds, at a height of 0.2.
    AnimationClip walking(String name, double meters, double length) =>
        AnimationClip(
          name: name,
          tracks: <AnimationTrack>[
            AnimationTrack(
              nodeIndex: 0,
              path: AnimationPath.translation,
              interpolation: AnimationInterpolation.linear,
              times: Float32List.fromList(<double>[0.0, length]),
              values: Float32List.fromList(<double>[0, 0.2, 0, 0, 0.2, meters]),
              componentCount: 3,
            ),
          ],
        );

    AnimationGraph moving(
      List<AnimationState> states,
      List<AnimationClip> clips, {
      List<AnimationTransition> transitions = const <AnimationTransition>[],
    }) => AnimationGraph(
      machine: AnimationStateMachine(
        parameters: AnimationParameterSchema(const <AnimationParameter>[
          AnimationParameter.float('speed'),
          AnimationParameter.trigger('stop'),
        ]),
        entry: states.first.name,
        states: states,
        transitions: transitions,
      ),
      clips: clips,
      pose: _onePose(),
    )..rootNode = 0;

    double travelled(AnimationGraph graph, int steps) {
      var z = 0.0;
      for (var i = 0; i < steps; i++) {
        graph.evaluate(_dt);
        z += graph.rootDelta.z;
        expect(graph.rootDelta.x, 0.0);
        expect(graph.rootDelta.y, 0.0);
      }
      return z;
    }

    test('hands over the walk and holds the root over the body', () {
      final graph = moving(
        const <AnimationState>[AnimationState(name: 'walk', clip: 'walk')],
        <AnimationClip>[walking('walk', 1.5, 1.0)],
      );
      expect(travelled(graph, 64), closeTo(1.5, 1e-5));
      // Round the loop's turn and on: three metres in two seconds.
      expect(travelled(graph, 64), closeTo(1.5, 1e-5));
      // Halfway round, where the clip has the root three quarters out.
      travelled(graph, 32);
      expect(graph.pose.translations[2], 0.0, reason: 'z held at rest');
      expect(
        graph.pose.translations[1],
        closeTo(0.2, 1e-6),
        reason: "its height is the clip's",
      );
    });

    test('on sixtieths, which do not sum to a turn exactly, it never steps '
        'back', () {
      // Floored from elapsed time alone, the turns came out one short on a
      // step whose sum fell a hair under the loop's length while the
      // playhead had already wrapped: the root leapt a stride back.
      final graph = moving(
        const <AnimationState>[AnimationState(name: 'walk', clip: 'walk')],
        <AnimationClip>[walking('walk', 1.5, 1.0)],
      );
      var z = 0.0;
      for (var i = 0; i < 600; i++) {
        graph.evaluate(1.0 / 60.0);
        expect(graph.rootDelta.z, greaterThan(0.0), reason: 'step $i');
        z += graph.rootDelta.z;
      }
      expect(z, closeTo(15.0, 1e-3));
    });

    test('a clip played once moves its length and no more', () {
      final graph = moving(
        const <AnimationState>[
          AnimationState(
            name: 'lunge',
            clip: 'lunge',
            wrap: AnimationWrap.once,
          ),
        ],
        <AnimationClip>[walking('lunge', 0.8, 0.5)],
      );
      expect(travelled(graph, 200), closeTo(0.8, 1e-5));
    });

    test('a blend travels its mix, a cycle of the mixed length', () {
      final graph = moving(
        <AnimationState>[
          AnimationState(
            name: 'move',
            blend: AnimationBlendSpace('speed', const <BlendPoint>[
              BlendPoint(0.0, 'walk'),
              BlendPoint(1.0, 'run'),
            ]),
          ),
        ],
        <AnimationClip>[walking('walk', 1.5, 1.0), walking('run', 3.0, 0.5)],
      );
      graph.parameters.setFloat('speed', 0.5);
      // Half and half: 2.25 m a cycle of three quarters of a second.
      expect(travelled(graph, 48), closeTo(2.25, 1e-5));
    });

    test('through a crossfade to a stand the travel fades out', () {
      final graph = moving(
        const <AnimationState>[
          AnimationState(name: 'walk', clip: 'walk'),
          AnimationState(name: 'stand', clip: 'stand'),
        ],
        <AnimationClip>[walking('walk', 1.0, 1.0), _clip('stand', 0.0)],
        transitions: <AnimationTransition>[
          AnimationTransition(
            from: 'walk',
            to: 'stand',
            conditions: const <AnimationCondition>[TriggerCondition('stop')],
            duration: 0.5,
          ),
        ],
      );
      travelled(graph, 16);
      graph.parameters.fire('stop');
      graph.evaluate(_dt);
      final steps = <double>[];
      for (var i = 0; i < 40; i++) {
        graph.evaluate(_dt);
        steps.add(graph.rootDelta.z);
      }
      for (var i = 1; i < steps.length; i++) {
        expect(steps[i], lessThanOrEqualTo(steps[i - 1] + 1e-9));
      }
      expect(steps.first, greaterThan(0.0));
      expect(steps.last, 0.0, reason: 'standing once the fade is done');
    });

    test('with no root node the root walks in the pose as drawn', () {
      final graph = moving(
        const <AnimationState>[AnimationState(name: 'walk', clip: 'walk')],
        <AnimationClip>[walking('walk', 1.5, 1.0)],
      )..rootNode = null;
      for (var i = 0; i < 32; i++) {
        graph.evaluate(_dt);
      }
      expect(graph.rootDelta.length, 0.0);
      expect(graph.pose.translations[2], closeTo(0.75, 1e-5));
    });
  });

  group('goals', () {
    /// A chain straight up from the origin, a node every metre: [count]
    /// nodes, each the last one's child.
    AnimationPose chain(int count) => AnimationPose(
      parents: <int>[for (var i = 0; i < count; i++) i - 1],
      restTranslations: Float32List.fromList(<double>[
        for (var i = 0; i < count; i++) ...<double>[0, i == 0 ? 0 : 1, 0],
      ]),
      restRotations: Float32List.fromList(<double>[
        for (var i = 0; i < count; i++) ...<double>[0, 0, 0, 1],
      ]),
      restScales: Float32List.fromList(<double>[
        for (var i = 0; i < count; i++) ...<double>[1, 1, 1],
      ]),
    );

    AnimationGraph still(AnimationPose pose) => AnimationGraph(
      machine: AnimationStateMachine(
        parameters: AnimationParameterSchema(const <AnimationParameter>[]),
        entry: 'still',
        states: const <AnimationState>[
          AnimationState(name: 'still', clip: 'still'),
        ],
        transitions: const <AnimationTransition>[],
      ),
      clips: <AnimationClip>[_clip('still', 0.0, yaw: 0.0)],
      pose: pose,
    );

    /// Which way node [joint] faces, as what faced +Z at rest.
    Vector3 facing(AnimationPose pose, int joint) {
      final q = Quaternion.identity();
      pose.worldMatrices()[joint].decompose(Vector3.zero(), q, Vector3.zero());
      return q.asRotationMatrix().transform(Vector3(0, 0, 1));
    }

    test('a look turns its joint to the target, no further than its limit', () {
      final graph = still(chain(2));
      final look = LookGoal(
        joint: 1,
        forward: Vector3(0, 0, 1),
        limit: 2.0,
        target: Vector3(5, 1, 0),
      );
      graph.goals.add(look);
      var pose = graph.evaluate(_dt);
      expect(facing(pose, 1).x, closeTo(1.0, 1e-5));
      look.limit = 0.5;
      pose = graph.evaluate(_dt);
      expect(facing(pose, 1).x, closeTo(math.sin(0.5), 1e-5));
    });

    test(
      'a joint turned at rest faces what it faced, and turns from there',
      () {
        // The head's own frame a third of a turn round at rest, its face still
        // to +Z: the look must undo the frame to know where the face is.
        final turned = chain(2);
        final q = Quaternion.axisAngle(Vector3(0, 1, 0), 2.0);
        final pose = AnimationPose(
          parents: turned.parents,
          restTranslations: Float32List.fromList(<double>[0, 0, 0, 0, 1, 0]),
          restRotations: Float32List.fromList(<double>[
            0,
            0,
            0,
            1,
            q.x,
            q.y,
            q.z,
            q.w,
          ]),
          restScales: Float32List.fromList(<double>[1, 1, 1, 1, 1, 1]),
        );
        // And the root turned by the animation, so the head's frame is not
        // its rest's either.
        final graph =
            AnimationGraph(
                machine: AnimationStateMachine(
                  parameters: AnimationParameterSchema(
                    const <AnimationParameter>[],
                  ),
                  entry: 'turned',
                  states: const <AnimationState>[
                    AnimationState(name: 'turned', clip: 'turned'),
                  ],
                  transitions: const <AnimationTransition>[],
                ),
                clips: <AnimationClip>[_clip('turned', 0.0, yaw: 0.6)],
                pose: pose,
              )
              ..goals.add(
                LookGoal(
                  joint: 1,
                  forward: Vector3(0, 0, 1),
                  limit: 3.0,
                  target: Vector3(5, 1, 0),
                ),
              );
        graph.evaluate(_dt);
        final face = Quaternion.identity();
        graph.pose.worldMatrices()[1].decompose(
          Vector3.zero(),
          face,
          Vector3.zero(),
        );
        final restFace = q.conjugated().asRotationMatrix().transform(
          Vector3(0, 0, 1),
        );
        final now = face.asRotationMatrix().transform(restFace);
        expect(now.x, closeTo(1.0, 1e-5));
      },
    );

    test('at half weight it turns half as far', () {
      final graph = still(chain(2));
      graph.goals.add(
        LookGoal(
          joint: 1,
          forward: Vector3(0, 0, 1),
          limit: 2.0,
          target: Vector3(5, 1, 0),
          weight: 0.5,
        ),
      );
      final pose = graph.evaluate(_dt);
      expect(facing(pose, 1).x, closeTo(math.sin(math.pi / 4), 1e-5));
    });

    test("a reach brings the chain's tip to its target", () {
      final graph = still(chain(3));
      graph.goals.add(
        ReachGoal(
          root: 0,
          mid: 1,
          tip: 2,
          target: Vector3(0.8, 1.2, 0.0),
          pole: Vector3(1, 0, 0),
        ),
      );
      final pose = graph.evaluate(_dt);
      final tip = pose.worldMatrices()[2].getTranslation();
      expect(tip.distanceTo(Vector3(0.8, 1.2, 0.0)), lessThan(1e-4));
    });

    test('comes in over the time it is given', () {
      final graph = still(chain(2));
      final look = LookGoal(
        joint: 1,
        forward: Vector3(0, 0, 1),
        limit: 2.0,
        target: Vector3(5, 1, 0),
        weight: 0.0,
      )..fadeTo(1.0, 0.25);
      graph.goals.add(look);
      for (var i = 0; i < 8; i++) {
        graph.evaluate(_dt);
      }
      expect(look.weight, 0.5);
      expect(facing(graph.pose, 1).x, closeTo(math.sin(math.pi / 4), 1e-5));
    });
  });

  group('markers', () {
    AnimationGraph marked(
      List<AnimationState> states,
      List<AnimationClip> clips, {
      List<AnimationTransition> transitions = const <AnimationTransition>[],
    }) => AnimationGraph(
      machine: AnimationStateMachine(
        parameters: AnimationParameterSchema(const <AnimationParameter>[
          AnimationParameter.trigger('go'),
          AnimationParameter.float('speed'),
        ]),
        entry: states.first.name,
        states: states,
        transitions: transitions,
      ),
      clips: clips,
      pose: _onePose(),
    );

    /// The step on which each marker was passed, over [steps] steps.
    List<(int, String)> heard(AnimationGraph graph, int steps) =>
        <(int, String)>[
          for (var i = 1; i <= steps; i++)
            for (final m in (graph..evaluate(_dt)).passed) (i, m.name),
        ];

    test("a state's markers are passed once a cycle, the first on entry", () {
      final graph = marked(
        const <AnimationState>[
          AnimationState(
            name: 'walk',
            clip: 'walk',
            markers: <AnimationMarker>[
              AnimationMarker(0.0, 'left'),
              AnimationMarker(0.5, 'right'),
            ],
          ),
        ],
        <AnimationClip>[_clip('walk', 0.0)],
      );
      // A one-second loop at 1/64 s: on entry, at half, at the turn.
      expect(heard(graph, 66), <(int, String)>[
        (1, 'left'),
        (33, 'right'),
        (65, 'left'),
      ]);
    });

    test("a clip's own markers, read from its extras, once for a clip played "
        'once', () {
      final swing = AnimationClip(
        name: 'swing',
        tracks: _clip('swing', 0.0, length: 0.5).tracks,
        extras: const <String, Object?>{
          'markers': <Object?>[
            <String, Object?>{'time': 0.25, 'name': 'hit'},
            <String, Object?>{'time': 'soon', 'name': 'ignored'},
          ],
        },
      );
      expect(swing.markers.single.name, 'hit');
      final graph = marked(
        const <AnimationState>[
          AnimationState(
            name: 'swing',
            clip: 'swing',
            wrap: AnimationWrap.once,
          ),
        ],
        <AnimationClip>[swing],
      );
      expect(heard(graph, 200), <(int, String)>[(17, 'hit')]);
    });

    test('a blend marks its own cycle, the mixed one', () {
      final graph = marked(
        <AnimationState>[
          AnimationState(
            name: 'move',
            blend: AnimationBlendSpace('speed', const <BlendPoint>[
              BlendPoint(0.0, 'walk'),
              BlendPoint(1.0, 'run'),
            ]),
            markers: const <AnimationMarker>[AnimationMarker(0.5, 'step')],
          ),
        ],
        <AnimationClip>[_clip('walk', 0.0), _clip('run', 0.0, length: 0.5)],
      );
      graph.parameters.setFloat('speed', 0.5);
      // The mix is three quarters of a second; its half, 24 steps in.
      expect(heard(graph, 40), <(int, String)>[(25, 'step')]);
    });

    test('in a crossfade only the state entered is heard', () {
      const left = <AnimationMarker>[AnimationMarker(0.25, 'walk-step')];
      const right = <AnimationMarker>[AnimationMarker(0.0, 'run-step')];
      final graph = marked(
        const <AnimationState>[
          AnimationState(name: 'walk', clip: 'walk', markers: left),
          AnimationState(name: 'run', clip: 'run', markers: right),
        ],
        <AnimationClip>[_clip('walk', 0.0), _clip('run', 0.0, length: 0.25)],
        transitions: <AnimationTransition>[
          AnimationTransition(
            from: 'walk',
            to: 'run',
            conditions: const <AnimationCondition>[TriggerCondition('go')],
            duration: 0.5,
          ),
        ],
      );
      graph.evaluate(_dt);
      graph.parameters.fire('go');
      graph.evaluate(_dt);
      // Half a second of fade, a quarter of a second into which the walk
      // would have stepped were it heard: only the run's steps are.
      expect(heard(graph, 64).map((h) => h.$2).toSet(), <String>{'run-step'});
    });
  });

  group('a layer', () {
    /// Two nodes, the second the first's child, both at rest unturned.
    AnimationPose twoPose() => AnimationPose(
      parents: const <int>[-1, 0],
      restTranslations: Float32List(6),
      restRotations: Float32List.fromList(<double>[0, 0, 0, 1, 0, 0, 0, 1]),
      restScales: Float32List.fromList(<double>[1, 1, 1, 1, 1, 1]),
    );

    /// A clip holding node [node] at x = [x], turned [yaw] about y.
    AnimationClip holding(String name, int node, double x, {double yaw = 0}) {
      final h = yaw / 2.0;
      return AnimationClip(
        name: name,
        tracks: <AnimationTrack>[
          AnimationTrack(
            nodeIndex: node,
            path: AnimationPath.translation,
            interpolation: AnimationInterpolation.linear,
            times: Float32List.fromList(<double>[0.0, 1.0]),
            values: Float32List.fromList(<double>[x, 0, 0, x, 0, 0]),
            componentCount: 3,
          ),
          AnimationTrack(
            nodeIndex: node,
            path: AnimationPath.rotation,
            interpolation: AnimationInterpolation.linear,
            times: Float32List.fromList(<double>[0.0, 1.0]),
            values: Float32List.fromList(<double>[
              0,
              math.sin(h),
              0,
              math.cos(h),
              0,
              math.sin(h),
              0,
              math.cos(h),
            ]),
            componentCount: 4,
          ),
        ],
      );
    }

    AnimationGraph playing(AnimationClip clip, [AnimationPose? pose]) =>
        AnimationGraph(
          machine: AnimationStateMachine(
            parameters: AnimationParameterSchema(const <AnimationParameter>[]),
            entry: 'one',
            states: <AnimationState>[
              AnimationState(name: 'one', clip: clip.name!),
            ],
            transitions: const <AnimationTransition>[],
          ),
          clips: <AnimationClip>[clip],
          pose: pose ?? twoPose(),
        );

    double yawOf(AnimationPose pose, int node) =>
        2.0 *
        math.atan2(pose.rotations[node * 4 + 1], pose.rotations[node * 4 + 3]);

    test('overrides the nodes its mask covers, by its weight', () {
      final base = playing(holding('walk', 1, 1.0, yaw: 0.0));
      final layer = AnimationGraphLayer(
        graph: playing(holding('wave', 1, 5.0, yaw: 1.0)),
        mask: AnimationMask(const <int>[1]),
      );
      base.layers.add(layer);
      var pose = base.evaluate(_dt);
      expect(pose.translations[3], 5.0);
      expect(yawOf(pose, 1), closeTo(1.0, 1e-6));
      layer.weight = 0.5;
      pose = base.evaluate(_dt);
      expect(pose.translations[3], 3.0);
      expect(yawOf(pose, 1), closeTo(0.5, 1e-6));
      // Outside the mask the base stands.
      layer.mask = AnimationMask(const <int>[0]);
      pose = base.evaluate(_dt);
      expect(pose.translations[3], 1.0);
    });

    test('adds its distance from rest on top of the base', () {
      final base = playing(holding('walk', 1, 1.0, yaw: math.pi / 2));
      base.layers.add(
        AnimationGraphLayer(
          graph: playing(holding('lean', 1, 2.0, yaw: math.pi / 4)),
          blend: AnimationBlend.additive,
        ),
      );
      final pose = base.evaluate(_dt);
      expect(pose.translations[3], 3.0);
      expect(yawOf(pose, 1), closeTo(3 * math.pi / 4, 1e-6));
    });

    test('comes in over the time it is given, on the steps', () {
      final base = playing(holding('walk', 1, 0.0));
      final layer = AnimationGraphLayer(
        graph: playing(holding('wave', 1, 8.0)),
        weight: 0.0,
      )..fadeTo(1.0, 0.25);
      base.layers.add(layer);
      for (var i = 0; i < 8; i++) {
        base.evaluate(_dt);
      }
      expect(layer.weight, 0.5);
      expect(base.pose.translations[3], 4.0);
      for (var i = 0; i < 20; i++) {
        base.evaluate(_dt);
      }
      expect(layer.weight, 1.0);
    });

    test('masks a subtree, and refuses a skeleton not its own', () {
      final mask = AnimationMask.below(const <int>[-1, 0, 1, 0], 1);
      expect(
        <int>[
          for (var i = 0; i < 4; i++)
            if (mask.covers(i)) i,
        ],
        <int>[1, 2],
      );
      final base = playing(holding('walk', 1, 0.0))
        ..layers.add(
          AnimationGraphLayer(
            graph: playing(holding('one', 0, 0.0), _onePose()),
          ),
        );
      expect(() => base.evaluate(_dt), throwsArgumentError);
    });
  });

  group('a blend space', () {
    /// x from [from] to [to] over [length] seconds.
    AnimationClip ramp(String name, double from, double to, double length) =>
        AnimationClip(
          name: name,
          tracks: <AnimationTrack>[
            AnimationTrack(
              nodeIndex: 0,
              path: AnimationPath.translation,
              interpolation: AnimationInterpolation.linear,
              times: Float32List.fromList(<double>[0.0, length]),
              values: Float32List.fromList(<double>[from, 0, 0, to, 0, 0]),
              componentCount: 3,
            ),
          ],
        );

    AnimationGraph moving(
      List<AnimationClip> clips, {
      List<AnimationTransition> transitions = const <AnimationTransition>[],
    }) => AnimationGraph(
      machine: AnimationStateMachine(
        parameters: AnimationParameterSchema(const <AnimationParameter>[
          AnimationParameter.float('speed'),
        ]),
        entry: 'move',
        states: <AnimationState>[
          AnimationState(
            name: 'move',
            blend: AnimationBlendSpace('speed', const <BlendPoint>[
              BlendPoint(1.0, 'walk'),
              BlendPoint(5.0, 'run'),
            ]),
          ),
          const AnimationState(name: 'idle', clip: 'walk'),
        ],
        transitions: transitions,
      ),
      clips: clips,
      pose: _onePose(),
    );

    double xAfter(AnimationGraph graph, double speed, int steps) {
      graph.parameters.setFloat('speed', speed);
      var x = 0.0;
      for (var i = 0; i < steps; i++) {
        x = graph.evaluate(_dt).translations[0];
      }
      return x;
    }

    test('mixes its two clips by the parameter, and holds past the ends', () {
      final clips = <AnimationClip>[_clip('walk', 10.0), _clip('run', 30.0)];
      expect(xAfter(moving(clips), 3.0, 1), 20.0);
      expect(xAfter(moving(clips), 2.0, 1), 15.0);
      expect(xAfter(moving(clips), 0.0, 1), 10.0);
      expect(xAfter(moving(clips), 9.0, 1), 30.0);
    });

    test('plays both at one phase, at the speed of the mixed length', () {
      // A walk of a second and a run of half of one. Half and half, the
      // cycle is three quarters of a second: 24 steps of 1/64 are half of
      // it, and both clips stand at their middles.
      final clips = <AnimationClip>[
        ramp('walk', 0.0, 1.0, 1.0),
        ramp('run', 0.0, 1.0, 0.5),
      ];
      expect(xAfter(moving(clips), 3.0, 24), closeTo(0.5, 1e-6));
      // All run, a quarter of a second is half its cycle.
      expect(xAfter(moving(clips), 5.0, 16), closeTo(0.5, 1e-6));
    });

    test('counts its exit time in cycles of the mix', () {
      final clips = <AnimationClip>[
        ramp('walk', 0.0, 1.0, 1.0),
        ramp('run', 0.0, 1.0, 0.5),
      ];
      final graph = moving(
        clips,
        transitions: <AnimationTransition>[
          AnimationTransition(from: 'move', to: 'idle', exitTime: 1.0),
        ],
      );
      graph.parameters.setFloat('speed', 3.0);
      for (var i = 0; i < 47; i++) {
        graph.evaluate(_dt);
      }
      expect(graph.state, 'move', reason: 'not yet a cycle of 0.75 s');
      graph.evaluate(_dt);
      expect(graph.state, 'idle');
    });

    test('says what stops one running', () {
      List<String> problems(AnimationState state, {bool flag = false}) =>
          AnimationStateMachine(
            parameters: AnimationParameterSchema(<AnimationParameter>[
              const AnimationParameter.float('speed'),
              if (flag) const AnimationParameter.boolean('fast'),
            ]),
            entry: state.name,
            states: <AnimationState>[state],
            transitions: const <AnimationTransition>[],
          ).problems(<AnimationClip>[_clip('walk', 0.0), _clip('run', 1.0)]);
      AnimationState blending(
        String parameter,
        List<BlendPoint> points, {
        String clip = '',
      }) => AnimationState(
        name: 'move',
        clip: clip,
        blend: AnimationBlendSpace(parameter, points),
      );
      const both = <BlendPoint>[BlendPoint(0, 'walk'), BlendPoint(1, 'run')];

      expect(problems(blending('speed', both)), isEmpty);
      expect(
        problems(blending('speed', both, clip: 'walk')).single,
        contains('leave its clip empty'),
      );
      expect(
        problems(blending('pace', both)).single,
        contains('not a parameter'),
      );
      expect(
        problems(blending('fast', both), flag: true).single,
        contains('needs a number'),
      );
      expect(
        problems(
          blending('speed', const <BlendPoint>[BlendPoint(0, 'walk')]),
        ).single,
        contains('at least two'),
      );
      expect(
        problems(
          blending('speed', const <BlendPoint>[
            BlendPoint(1, 'walk'),
            BlendPoint(1, 'run'),
          ]),
        ).single,
        contains('must rise'),
      );
      expect(
        problems(
          blending('speed', const <BlendPoint>[
            BlendPoint(0, 'walk'),
            BlendPoint(1, 'sprint'),
          ]),
        ).single,
        contains('`sprint`'),
      );
    });
  });

  group('conditions', () {
    // Mutation: drop the `checks.every(_holds)` test in `_takeTransition` and
    // the graph walks at speed 0.4; flip `greater` to `less` in
    // `CompareCondition.holds` and it never walks.
    test('a transition waits for its condition and then fires', () {
      final graph = _graph(<AnimationTransition>[
        AnimationTransition(
          from: 'idle',
          to: 'walk',
          conditions: const <AnimationCondition>[
            CompareCondition('speed', AnimationComparison.greater, 0.5),
          ],
        ),
      ]);

      expect(graph.parameters.setFloat('speed', 0.4).wasWritten, isTrue);
      for (var i = 0; i < 10; i++) {
        graph.evaluate(_dt);
      }
      expect(graph.state, 'idle');
      expect(graph.pose.translations[0], 0.0);

      graph.parameters.setFloat('speed', 0.6);
      final pose = graph.evaluate(_dt);
      expect(graph.state, 'walk');
      expect(pose.translations[0], 10.0, reason: 'a zero fade cuts');
    });

    // Mutation: compare a boolean against `== 0.0` rather than `!= 0.0` and
    // the bool transition fires while grounded; read `int` through a float
    // comparison only and `equals` on an integer never matches.
    test('bool and integer conditions all have to hold', () {
      final graph = _graph(<AnimationTransition>[
        AnimationTransition(
          from: 'idle',
          to: 'walk',
          conditions: const <AnimationCondition>[
            BoolCondition('grounded', value: false),
            CompareCondition('stance', AnimationComparison.equals, 2),
          ],
        ),
      ]);

      graph.parameters.setInteger('stance', 2);
      graph.evaluate(_dt);
      expect(graph.state, 'idle', reason: 'still grounded');

      graph.parameters.setBool('grounded', false);
      graph.evaluate(_dt);
      expect(graph.state, 'walk');
    });

    // Mutation: sort by priority ascending, or drop the sort, and the
    // lower-priority walk declared first wins.
    test('of two transitions ready on one step, the higher priority wins', () {
      final graph = _graph(<AnimationTransition>[
        AnimationTransition(
          from: 'idle',
          to: 'walk',
          conditions: const <AnimationCondition>[
            CompareCondition('speed', AnimationComparison.greater, 0.5),
          ],
        ),
        AnimationTransition(
          from: 'idle',
          to: 'attack',
          priority: 1,
          conditions: const <AnimationCondition>[TriggerCondition('attack')],
        ),
      ]);

      graph.parameters
        ..setFloat('speed', 1.0)
        ..fire('attack');
      graph.evaluate(_dt);
      expect(graph.state, 'attack');
    });
  });

  group('triggers and exit time', () {
    List<AnimationTransition> attackAndBack() => <AnimationTransition>[
      AnimationTransition(
        from: 'idle',
        to: 'attack',
        conditions: const <AnimationCondition>[TriggerCondition('attack')],
      ),
      AnimationTransition(from: 'attack', to: 'idle', exitTime: 1.0),
    ];

    // Mutation: drop `consumeTriggerAt` from `_takeTransition` and the graph
    // goes straight back into the attack the moment it returns to idle.
    test('a trigger fires its transition once and is consumed', () {
      final graph = _graph(attackAndBack());
      final attack = graph.machine.parameters.indexOf('attack');

      graph.parameters.fire('attack');
      graph.evaluate(_dt);
      expect(graph.state, 'attack');
      expect(graph.parameters.valueAt(attack), 0.0);

      final visited = <String>[
        for (var i = 0; i < 200; i++) (graph..evaluate(_dt)).state,
      ];
      expect(visited.where((s) => s == 'attack'), hasLength(31));
      expect(visited.skip(31), everyElement('idle'));
    });

    // Mutation: test the exit time against the wrapped playhead rather than
    // the time in the state, or drop the test, and the attack leaves early.
    test('an exit time holds the state until that much of its clip', () {
      final graph = _graph(attackAndBack());
      graph.parameters.fire('attack');
      graph.evaluate(_dt);

      // The attack clip is half a second, 32 steps; it is entered with its
      // playhead at zero and leaves on the step that reaches the end.
      for (var i = 0; i < 31; i++) {
        graph.evaluate(_dt);
      }
      expect(graph.state, 'attack');
      expect(graph.normalizedTime, closeTo(31 / 32, 1e-12));
      graph.evaluate(_dt);
      expect(graph.state, 'idle');
    });

    // Mutation: clear every trigger at the end of `evaluate` and the press
    // made during the fade is lost.
    test('a trigger set while a transition cannot fire waits for it', () {
      final graph = _graph(<AnimationTransition>[
        AnimationTransition(
          from: 'idle',
          to: 'walk',
          duration: 0.25,
          conditions: const <AnimationCondition>[
            CompareCondition('speed', AnimationComparison.greater, 0.5),
          ],
        ),
        AnimationTransition(
          from: 'walk',
          to: 'attack',
          conditions: const <AnimationCondition>[TriggerCondition('attack')],
        ),
      ]);
      graph.parameters.setFloat('speed', 1.0);
      graph.evaluate(_dt);
      graph.parameters.fire('attack');

      for (var i = 0; i < 15; i++) {
        graph.evaluate(_dt);
      }
      expect(graph.state, 'walk', reason: 'no transition during a fade');
      graph.evaluate(_dt);
      expect(graph.state, 'attack');
    });
  });

  group('crossfade', () {
    AnimationGraph fading() => _graph(<AnimationTransition>[
      AnimationTransition(
        from: 'idle',
        to: 'walk',
        duration: 0.25,
        conditions: const <AnimationCondition>[
          CompareCondition('speed', AnimationComparison.greater, 0.5),
        ],
      ),
    ])..parameters.setFloat('speed', 1.0);

    // Mutation: blend rotation by lerping the four components and
    // normalising, and a quarter of the way through reads 21.6° rather than
    // 22.5° — the two agree only at a half, which is why this checks a quarter.
    test('a quarter of the way through, the pose is a quarter of the way', () {
      final graph = fading();
      graph.evaluate(_dt);
      expect(graph.fadingFrom, 'idle');
      expect(graph.fadeWeight, 0.0);
      expect(graph.pose.translations[0], 0.0, reason: 'weight 0 is the source');

      for (var i = 0; i < 4; i++) {
        graph.evaluate(_dt);
      }
      expect(graph.fadeWeight, 0.25);
      expect(graph.pose.translations[0], closeTo(2.5, 1e-6));
      expect(_yaw(graph.pose), closeTo(math.pi / 8.0, 1e-6));

      for (var i = 0; i < 4; i++) {
        graph.evaluate(_dt);
      }
      expect(graph.pose.translations[0], closeTo(5.0, 1e-6));
      expect(_yaw(graph.pose), closeTo(math.pi / 4.0, 1e-6));
    });

    // Mutation: end the fade one step late, or leave `_previous` set, and the
    // pose stops short of the walk.
    test('when the fade is over the pose is the target clip alone', () {
      final graph = fading();
      for (var i = 0; i < 17; i++) {
        graph.evaluate(_dt);
      }
      expect(graph.fadingFrom, isNull);
      expect(graph.fadeWeight, 1.0);
      expect(graph.pose.translations[0], 10.0);
      expect(_yaw(graph.pose), closeTo(math.pi / 2.0, 1e-6));
    });

    // Mutation: swap the arguments of `shortestArcSlerp` in `Pose.blendFrom`
    // and the graph's half-faded pose stops matching the player's.
    test('the graph fades as the player does', () {
      final graph = fading();
      final node = _Node();
      final player = AnimationPlayer(
        clips: _clips,
        targets: <AnimationTarget?>[node],
      )..play(0);

      graph.evaluate(_dt);
      player.crossFadeTo(1, duration: 0.25);
      for (var i = 0; i < 6; i++) {
        graph.evaluate(_dt);
        player
          ..update(_dt)
          ..apply();
      }
      // Close rather than equal only because a pose holds 32-bit floats and
      // the player hands its targets doubles.
      expect(player.fadeWeight, graph.fadeWeight);
      expect(node.x, closeTo(graph.pose.translations[0], 1e-6));
      for (var i = 0; i < 4; i++) {
        expect(node.rotation[i], closeTo(graph.pose.rotations[i], 1e-6));
      }
    });
  });

  // Mutation: advance by a wall clock, or iterate the outgoing transitions
  // out of a hash set, and two runs over the same script part ways.
  test('the same parameters on the same steps give the same run', () {
    List<Object> run() {
      final graph = _graph(<AnimationTransition>[
        AnimationTransition(
          from: 'idle',
          to: 'walk',
          duration: 0.125,
          conditions: const <AnimationCondition>[
            CompareCondition('speed', AnimationComparison.greater, 0.5),
          ],
        ),
        AnimationTransition(
          from: 'walk',
          to: 'attack',
          duration: 0.0625,
          conditions: const <AnimationCondition>[TriggerCondition('attack')],
        ),
        AnimationTransition(
          from: 'attack',
          to: 'idle',
          duration: 0.25,
          exitTime: 1.0,
        ),
      ]);
      final trace = <Object>[];
      for (var step = 0; step < 600; step++) {
        graph.parameters.setFloat('speed', (step % 90) / 60.0);
        if (step % 47 == 0) graph.parameters.fire('attack');
        final pose = graph.evaluate(_dt);
        trace
          ..add(graph.state)
          ..add(graph.fadeWeight)
          ..addAll(pose.translations)
          ..addAll(pose.rotations);
      }
      return trace;
    }

    final first = run();
    expect(
      first.toSet().containsAll(<String>['idle', 'walk', 'attack']),
      isTrue,
    );
    expect(run(), first);
  });

  group('refusals', () {
    // Mutation: drop the type check in `_write` and a bool lands in a float.
    test('a write of the wrong type is refused, naming the right call', () {
      final graph = _graph(const <AnimationTransition>[]);
      final refused = graph.parameters.setBool('speed', true);
      expect(refused.wasWritten, isFalse);
      expect(refused.refusal, contains('setFloat'));
      expect(
        graph.parameters.setFloat('sped', 1.0).refusal,
        contains('`speed`'),
      );
      expect(
        graph.parameters.setFloat('speed', double.nan).wasWritten,
        isFalse,
      );
      expect(graph.parameters.values, <double>[0.0, 1.0, 0.0, 0.0]);
    });

    // Mutation: drop `_conditionProblem` and a trigger tested as a bool
    // builds a graph whose transition is never taken.
    test('a definition that cannot run says why and is not built', () {
      final machine = _machine(
        transitions: <AnimationTransition>[
          AnimationTransition(
            from: 'idle',
            to: 'walk',
            conditions: const <AnimationCondition>[BoolCondition('attack')],
          ),
          AnimationTransition(
            from: 'idle',
            to: 'run',
            conditions: const <AnimationCondition>[
              CompareCondition('speed', AnimationComparison.equals, 1.0),
            ],
          ),
          AnimationTransition(from: 'walk', to: 'idle'),
        ],
      );
      final problems = machine.problems(_clips.take(2).toList());
      expect(problems, hasLength(5));
      expect(problems, contains(contains('TriggerCondition')));
      expect(problems, contains(contains('`run`')));
      expect(problems, contains(contains('exact equality')));
      expect(problems, contains(contains('neither a condition')));
      expect(problems, contains(contains('`attack`, which is not among')));
      expect(
        () => AnimationGraph(machine: machine, clips: _clips, pose: _onePose()),
        throwsArgumentError,
      );
    });
  });
}

final class _Node with AnimationTarget {
  double x = 0.0;
  List<double> rotation = const <double>[0, 0, 0, 1];

  @override
  void setPosition(double x, double y, double z) => this.x = x;

  @override
  void setRotation(Quaternion value) =>
      rotation = <double>[value.x, value.y, value.z, value.w];

  @override
  void setScale(double x, double y, double z) {}
}
