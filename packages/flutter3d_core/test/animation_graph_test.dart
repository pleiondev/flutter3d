/// The animation graph takes the transitions its parameters say, once, and
/// the same ones on every run — N1.
///
///     dart test test/animation_graph_test.dart
///
/// Every step here is 1/64 s and every fade a power of two, so the weights the
/// tests name are exact rather than close.
library;

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

Pose _onePose() => Pose(
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
double _yaw(Pose pose) =>
    2.0 * math.atan2(pose.rotations[1], pose.rotations[3]);

void main() {
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

      expect(graph.parameters.setFloat('speed', 0.4).written, isTrue);
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
      expect(refused.written, isFalse);
      expect(refused.refusal, contains('setFloat'));
      expect(
        graph.parameters.setFloat('sped', 1.0).refusal,
        contains('`speed`'),
      );
      expect(graph.parameters.setFloat('speed', double.nan).written, isFalse);
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

final class _Node implements AnimationTarget {
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
