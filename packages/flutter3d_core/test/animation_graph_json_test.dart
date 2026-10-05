/// Animation graphs as JSON, and kept in a model file — N1.
///
///     dart test test/animation_graph_json_test.dart
///
/// A machine with every kind of part goes out and comes back the same; a
/// graph built over what came back runs as the one built over the original;
/// a shape that is wrong says where; and a document's root `extras` keeps
/// its graphs through a `.f3d` written and read.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:test/test.dart';

/// Every kind of part: each parameter type, with and without an initial;
/// a clip state with markers, speed and wrap; blends along a line and
/// across a plane; each condition, an exit time, a priority, a fade.
AnimationStateMachine _everything() => AnimationStateMachine(
  parameters: AnimationParameterSchema(const <AnimationParameter>[
    AnimationParameter.float('speed', initial: 0.5),
    AnimationParameter.float('side'),
    AnimationParameter.integer('weapon', initial: 2),
    AnimationParameter.boolean('grounded', initial: true),
    AnimationParameter.trigger('jump'),
  ]),
  entry: 'move',
  states: <AnimationState>[
    const AnimationState(
      name: 'idle',
      clip: 'idle',
      speed: 0.5,
      markers: <AnimationMarker>[AnimationMarker(0.5, 'breath')],
    ),
    AnimationState(
      name: 'move',
      blend: AnimationBlendSpace('speed', const <BlendPoint>[
        BlendPoint(0.0, 'walk'),
        BlendPoint(1.0, 'run'),
      ]),
      markers: const <AnimationMarker>[
        AnimationMarker(0.25, 'step'),
        AnimationMarker(0.75, 'step'),
      ],
    ),
    AnimationState(
      name: 'strafe',
      blend: AnimationBlendSpace('side', const <BlendPoint>[
        BlendPoint(-1.0, 'walk', y: 0.0),
        BlendPoint(1.0, 'run', y: 0.0),
        BlendPoint(0.0, 'idle', y: 1.0),
      ], across: 'speed'),
    ),
    const AnimationState(name: 'leap', clip: 'jump', wrap: AnimationWrap.once),
  ],
  transitions: <AnimationTransition>[
    AnimationTransition(
      from: 'move',
      to: 'idle',
      conditions: const <AnimationCondition>[
        CompareCondition('speed', AnimationComparison.less, 0.1),
      ],
      duration: 0.2,
    ),
    AnimationTransition(
      from: 'idle',
      to: 'move',
      conditions: const <AnimationCondition>[
        CompareCondition('speed', AnimationComparison.greater, 0.1),
        BoolCondition('grounded'),
      ],
      duration: 0.2,
    ),
    AnimationTransition(
      from: 'move',
      to: 'leap',
      conditions: const <AnimationCondition>[
        TriggerCondition('jump'),
        CompareCondition('weapon', AnimationComparison.notEquals, 3),
      ],
      priority: 2,
    ),
    AnimationTransition(
      from: 'leap',
      to: 'move',
      conditions: const <AnimationCondition>[
        BoolCondition('grounded', value: true),
      ],
      exitTime: 1.0,
      duration: 0.1,
    ),
    AnimationTransition(from: 'idle', to: 'strafe', exitTime: 0.5),
    // Never fires: the script stays on the ground.
    AnimationTransition(
      from: 'strafe',
      to: 'idle',
      conditions: const <AnimationCondition>[
        BoolCondition('grounded', value: false),
      ],
    ),
  ],
);

AnimationClip _clip(String name, double x, double length) => AnimationClip(
  name: name,
  tracks: <AnimationTrack>[
    AnimationTrack(
      nodeIndex: 0,
      path: AnimationPath.translation,
      interpolation: AnimationInterpolation.linear,
      times: Float32List.fromList(<double>[0.0, length]),
      values: Float32List.fromList(<double>[0, 0, 0, x, 0, 0]),
      componentCount: 3,
    ),
  ],
);

final List<AnimationClip> _clips = <AnimationClip>[
  _clip('idle', 1.0, 2.0),
  _clip('walk', 2.0, 1.0),
  _clip('run', 4.0, 0.6),
  _clip('jump', 3.0, 0.8),
];

Pose _pose() => Pose(
  parents: const <int>[-1],
  restTranslations: Float32List(3),
  restRotations: Float32List.fromList(<double>[0, 0, 0, 1]),
  restScales: Float32List.fromList(<double>[1, 1, 1]),
);

/// [machine] run through a script that visits every state, step by step.
List<String> _run(AnimationStateMachine machine) {
  final graph = AnimationGraph(machine: machine, clips: _clips, pose: _pose());
  return <String>[
    for (var i = 0; i < 400; i++)
      (() {
        graph.parameters.setFloat('speed', i < 150 ? 0.8 : 0.0);
        if (i == 60) graph.parameters.fire('jump');
        graph.evaluate(1.0 / 60.0);
        return '${graph.state} ${graph.pose.translations.toList()} '
            '${graph.passed}';
      })(),
  ];
}

Object? _throughText(Object? json) => jsonDecode(jsonEncode(json));

void main() {
  test('a machine with every kind of part comes back the same', () {
    final machine = _everything();
    expect(machine.problems(_clips), isEmpty);
    final once = AnimationGraphJson.encode(machine);
    final back = AnimationGraphJson.decode(_throughText(once));
    expect(AnimationGraphJson.encode(back), once);
    expect(back.entry, 'move');
    expect(back.parameters.parameters[2].initial, 2.0);
    expect(back.states[2].blend!.across, 'speed');
    expect(back.states[2].blend!.points[2].y, 1.0);
    expect(back.states[3].wrap, AnimationWrap.once);
    expect(back.transitions[3].exitTime, 1.0);
    expect(back.transitions[2].priority, 2);
  });

  test('and runs as the original', () {
    final steps = _run(_everything());
    expect(steps.map((s) => s.split(' ').first).toSet(), <String>{
      'move',
      'leap',
      'idle',
      'strafe',
    }, reason: 'the script visits every state');
    expect(
      _run(
        AnimationGraphJson.decode(
          _throughText(AnimationGraphJson.encode(_everything())),
        ),
      ),
      steps,
    );
  });

  test('leaves the defaults out', () {
    final json = AnimationGraphJson.encode(
      AnimationStateMachine(
        parameters: AnimationParameterSchema(const <AnimationParameter>[]),
        states: const <AnimationState>[AnimationState(name: 'a', clip: 'a')],
        transitions: <AnimationTransition>[
          AnimationTransition(from: 'a', to: 'a'),
        ],
      ),
    );
    expect(
      jsonEncode(json),
      '{"parameters":[],"entry":"a","states":'
      '[{"name":"a","clip":"a"}],"transitions":[{"from":"a","to":"a"}]}',
    );
  });

  test('a wrong shape says where', () {
    String complaint(Object? json) {
      try {
        AnimationGraphJson.decode(json);
      } on FormatException catch (error) {
        return error.message;
      }
      fail('read $json');
    }

    final good = AnimationGraphJson.encode(_everything());
    Map<String, Object?> edited(void Function(Map<String, Object?>) edit) {
      final copy = _throughText(good)! as Map<String, Object?>;
      edit(copy);
      return copy;
    }

    expect(complaint(<Object?>[]), 'the graph is [], not an object');
    expect(
      complaint(
        edited(
          (m) =>
              (((m['states']! as List<Object?>)[1]!
                      as Map<String, Object?>)['blend']!
                  as Map<String, Object?>)['points'] = <Object?>[
                <String, Object?>{'at': 'fast', 'clip': 'run'},
              ],
        ),
      ),
      'states[1].blend.points[0].at is "fast", not a number',
    );
    expect(
      complaint(
        edited(
          (m) =>
              ((m['parameters']! as List<Object?>)[0]!
                      as Map<String, Object?>)['type'] =
                  'double',
        ),
      ),
      'parameters[0].type is "double", not one of float, integer, boolean, '
      'trigger',
    );
    expect(
      complaint(
        edited(
          (m) =>
              ((m['transitions']! as List<Object?>)[0]!
                  as Map<String, Object?>)['conditions'] = <Object?>[
                <String, Object?>{'parameter': 'speed'},
              ],
        ),
      ),
      'transitions[0].conditions[0] says none of "compare", "is" or '
      '"trigger": true',
    );
    expect(
      complaint(edited((m) => m.remove('states'))),
      'states is null, not a list',
    );
  });

  test('a model file keeps its graphs, by name, through .f3d', () {
    final extras = AnimationGraphJson.keep(
      <String, Object?>{'author': 'someone'},
      <String, AnimationStateMachine>{'hero': _everything()},
    );
    final document = PlainModelDocument(
      animations: _clips,
      asset: DocumentAsset(generator: 'test', extras: extras),
    );
    final reread = F3dDocument.parse(F3dWriter(document).write());
    expect(reread.asset!.extras!['author'], 'someone');
    final graphs = AnimationGraphJson.graphsIn(reread.asset);
    expect(graphs.keys, <String>['hero']);
    expect(_run(graphs['hero']!), _run(_everything()));
    expect(AnimationGraphJson.graphsIn(null), isEmpty);
    expect(
      () => AnimationGraphJson.graphsIn(
        const DocumentAsset(
          extras: <String, Object?>{
            'animationGraphs': <String, Object?>{'broken': <Object?>[]},
          },
        ),
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          'graph "broken": the graph is [], not an object',
        ),
      ),
    );
  });
}
