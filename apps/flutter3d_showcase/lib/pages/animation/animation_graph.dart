/// The robot driven by an animation graph instead of by hand: a state
/// machine over its own clips, a blend space from a walk to a run by speed,
/// a wave laid over one arm by a masked layer, a head that turns to the
/// camera by a look goal, and the walk's stride carried into the world as
/// root motion.
///
/// Quoted by `animation_graph.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class AnimationGraphDemo extends ShowcaseDemo {
  late final ModelAsset _asset;
  late final ModelInstance _model;
  late final List<AnimationClip> _clips;
  late final AnimationGraph _graph;
  late final AnimationGraphLayer _wave;
  late final LookGoal _look;

  /// Node indices in the robot's file, found by name.
  late final int _body, _shoulder, _head, _thigh;

  /// The speed the graph is told, m/s, and whether it changes by itself.
  double speed = 0.0;
  bool wandering = true;
  bool waving = false;
  bool watching = true;

  double _clock = 0.0;
  double _yaw = 0.0;
  final Vector3 _at = Vector3(3.0, 0.0, 0.0);

  /// `RobotExpressive.glb` stands this tall in its own units; scaled to
  /// 1.8 m.
  static const double _modelHeight = 4.461221901699901;
  static const double _scale = 1.8 / _modelHeight;

  /// Where the blend space is all walk and all run, m/s.
  static const double walkAt = 1.5;
  static const double runAt = 4.0;

  /// The circle the robot walks round, m.
  static const double _radius = 3.0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 9.0
      ..pitch = 0.45
      ..yaw = 0.3;
    context.orbit.target.setValues(0.0, 0.8, 0.0);
  }

  @override
  Future<void> prepare(DemoContext context) async {
    // CC0, Tomás Laulhé, with facial morph targets by Don McCurdy; see
    // `packages/flutter3d_samples/assets/ATTRIBUTION.md`.
    final document = await loadModelByPath(
      'packages/flutter3d_samples/assets/RobotExpressive.glb',
    );
    _asset = await ModelAsset.fromDocument(document, device: context.device);
  }

  int _node(String name) => _asset.nodes.indexWhere((n) => n.name == name);

  // #region machine
  /// Idle, a move that blends a walk into a run by `speed`, and a jump
  /// played once on a trigger. The parameters are typed: a write of the
  /// wrong kind is refused with the call that would have been right.
  static AnimationStateMachine machine() => AnimationStateMachine(
    parameters: AnimationParameterSchema(const <AnimationParameter>[
      AnimationParameter.float('speed'),
      AnimationParameter.trigger('jump'),
    ]),
    entry: 'idle',
    states: <AnimationState>[
      const AnimationState(name: 'idle', clip: 'Idle'),
      AnimationState(
        name: 'move',
        blend: AnimationBlendSpace('speed', const <BlendPoint>[
          BlendPoint(walkAt, 'Walking'),
          BlendPoint(runAt, 'Running'),
        ]),
      ),
      const AnimationState(
        name: 'jump',
        clip: 'Jump',
        wrap: AnimationWrap.once,
      ),
    ],
    transitions: <AnimationTransition>[
      AnimationTransition(
        from: 'idle',
        to: 'move',
        conditions: const <AnimationCondition>[
          CompareCondition('speed', AnimationComparison.greater, 0.5),
        ],
        duration: 0.3,
      ),
      AnimationTransition(
        from: 'move',
        to: 'idle',
        conditions: const <AnimationCondition>[
          CompareCondition('speed', AnimationComparison.less, 0.3),
        ],
        duration: 0.3,
      ),
      for (final from in <String>['idle', 'move'])
        AnimationTransition(
          from: from,
          to: 'jump',
          conditions: const <AnimationCondition>[TriggerCondition('jump')],
          duration: 0.1,
          priority: 1,
        ),
      AnimationTransition(
        from: 'jump',
        to: 'idle',
        exitTime: 1.0,
        duration: 0.2,
      ),
    ],
  );
  // #endregion machine

  // #region graph
  /// A graph over the robot's clips into a pose of its own skeleton, with
  /// the walk's travel taken out of the body as root motion.
  AnimationGraph _newGraph() => AnimationGraph(
    machine: machine(),
    clips: _clips,
    pose: AnimationPose.fromNodes(_asset.nodes),
  )..rootNode = _body;
  // #endregion graph

  // #region layer
  /// A second graph that only waves, laid over the right arm from the
  /// shoulder down. Its weight starts at nought and fades in when asked.
  AnimationGraphLayer _waveLayer(AnimationGraph base) => AnimationGraphLayer(
    graph: AnimationGraph(
      machine: AnimationStateMachine(
        parameters: AnimationParameterSchema(const <AnimationParameter>[]),
        entry: 'wave',
        states: const <AnimationState>[
          AnimationState(name: 'wave', clip: 'Wave'),
        ],
        transitions: const <AnimationTransition>[],
      ),
      clips: _clips,
      pose: AnimationPose.fromNodes(_asset.nodes),
    ),
    mask: AnimationMask.below(base.pose.parents, _shoulder),
    weight: 0.0,
  );
  // #endregion layer

  @override
  Scene build(DemoContext context) {
    _body = _node('Body');
    _shoulder = _node('Shoulder.R');
    _head = _node('Head');
    _thigh = _node('UpperLeg.L');

    final scene = Scene()
      ..ambientIntensity = 0.3 * Photometric.legacyUnit
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(10.0, 0.2, 10.0)).build(),
          ),
          RenderMaterial(
            name: 'floor',
            baseColor: LinearColor.fromSrgb(0.42, 0.45, 0.5, 1.0),
          ),
          name: 'floor',
        )..setPosition(0.0, -0.1, 0.0),
      )
      ..add(
        LightNode(name: 'sun', intensity: 2.5 * Photometric.legacyUnit)
          ..setLocalForward(Vector3(-0.3, -0.7, -0.4)),
      );
    _model = _asset.instantiate(scene, name: 'robot');
    _model.root.setScale(_scale, _scale, _scale);

    final player = _model.player!;
    // The robot's walk and run are made in place. Their body is given a
    // stride along +z here, so that root motion has something to carry.
    _clips = <AnimationClip>[
      for (final clip in player.clips)
        switch (clip.name) {
          'Walking' => _strided(clip, _body, walkAt),
          'Running' => _strided(clip, _body, runAt),
          _ => clip,
        },
    ];

    _graph = _newGraph();
    _wave = _waveLayer(_graph);
    _graph.layers.add(_wave);
    // #region look
    // The head turns towards a point in the pose's space, a radian at most;
    // what faced +z at rest is what turns.
    _look = LookGoal(joint: _head, forward: Vector3(0.0, 0.0, 1.0), limit: 1.0);
    _graph.goals.add(_look);
    // #endregion look
    _place();
    return scene;
  }

  /// [clip] with [node]'s translation moved along +z at [metersPerSecond]
  /// in the world, in the units of the body's parent: the armature is
  /// scaled a hundred times inside a robot scaled to 1.8 m.
  static AnimationClip _strided(
    AnimationClip clip,
    int node,
    double metersPerSecond,
  ) {
    final perSecond = metersPerSecond / (_scale * 100.0);
    return AnimationClip(
      name: clip.name,
      tracks: <AnimationTrack>[
        for (final track in clip.tracks)
          if (track.nodeIndex == node &&
              track.path == AnimationPath.translation &&
              track.interpolation == AnimationInterpolation.linear)
            AnimationTrack(
              nodeIndex: node,
              path: AnimationPath.translation,
              interpolation: AnimationInterpolation.linear,
              times: track.times,
              values: Float32List.fromList(<double>[
                for (var k = 0; k < track.times.length; k++) ...<double>[
                  track.values[k * 3],
                  track.values[k * 3 + 1],
                  track.values[k * 3 + 2] + track.times[k] * perSecond,
                ],
              ]),
              componentCount: 3,
            )
          else
            track,
      ],
    );
  }

  void _place() {
    _model.root
      ..setPosition(_at.x, _at.y, _at.z)
      ..setRotation(Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), _yaw));
  }

  @override
  void update(DemoContext context, double dt) {
    _clock += dt;
    if (wandering) {
      // Stands, walks, runs and slows again, over twelve seconds.
      speed = math.max(0.0, 4.6 * math.sin(_clock * math.pi / 6.0) - 0.4);
    }
    // #region drive
    // The game writes the parameters between steps; the graph decides.
    _graph.parameters.setFloat('speed', speed);
    _wave.fadeTo(waving ? 1.0 : 0.0, 0.3);
    _look.fadeTo(watching ? 1.0 : 0.0, 0.3);
    final Matrix4 toPose = Matrix4.inverted(_model.root.worldMatrix);
    _look.target.setFrom(
      toPose.transformed3(context.camera.readWorldPosition()),
    );
    _graph.evaluate(dt).writeTo(_model.player!.targets);
    // #endregion drive

    // #region root
    // The stride the clips took, turned and scaled into the world by the
    // model's own matrix, moves the robot; a game would hand it to a
    // `CharacterController` to sweep. Here it bends round a circle.
    final Vector3 step = _graph.rootDeltaIn(_model.root.worldMatrix);
    _at.add(step);
    _yaw -= step.length / _radius;
    // #endregion root
    // Held on the circle against drift.
    final double around = math.atan2(_at.z, _at.x);
    _at.setValues(_radius * math.cos(around), 0.0, _radius * math.sin(around));
    _place();
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Speed',
      min: 0.0,
      max: 4.5,
      value: () => speed,
      onChanged: (double v) {
        wandering = false;
        speed = v;
      },
      format: (double v) => '${v.toStringAsFixed(1)} m/s',
    ),
    ToggleControl(
      'Speed changes by itself',
      value: () => wandering,
      onChanged: (bool v) => wandering = v,
    ),
    ToggleControl(
      'Wave with the right arm (a masked layer)',
      value: () => waving,
      onChanged: (bool v) => waving = v,
    ),
    ToggleControl(
      'Head watches the camera (a look goal)',
      value: () => watching,
      onChanged: (bool v) => watching = v,
    ),
    ToggleControl(
      'Jump (a trigger)',
      value: () => false,
      onChanged: (bool v) {
        if (v) _graph.parameters.fire('jump');
      },
    ),
  ];

  /// The state the shown graph is in, for a test.
  @visibleForTesting
  String get state => _graph.state;

  static double _dot(AnimationPose a, AnimationPose b, int joint) {
    var sum = 0.0;
    for (var k = 0; k < 4; k++) {
      sum += a.rotations[joint * 4 + k] * b.rotations[joint * 4 + k];
    }
    return sum.abs();
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the robot did not reach the frame');
    }
    // #region check
    // A graph of its own, so the one on screen is left as it was.
    const double step = 1 / 60;
    final AnimationGraph graph = _newGraph()..evaluate(step);
    if (graph.state != 'idle') throw StateError('it did not start idle');

    // Past the threshold it takes the transition on that step, and on the
    // next both states are playing, the move coming in.
    const double told = 2.0;
    graph.parameters.setFloat('speed', told);
    graph.evaluate(step);
    if (graph.state != 'move' || graph.fadingFrom != 'idle') {
      throw StateError('no transition from idle to move');
    }
    graph.evaluate(step);
    if (!(graph.fadeWeight > 0.0 && graph.fadeWeight < 1.0)) {
      throw StateError('no crossfade from idle to move');
    }
    for (var i = 0; i < 30; i++) {
      graph.evaluate(step);
    }
    if (graph.fadingFrom != null) throw StateError('the fade never ended');

    // A fifth of the way from the walk's point to the run's, the pose is
    // four fifths walk and one fifth run at the shared phase: two weights
    // that sum to one.
    final double t = (told - walkAt) / (runAt - walkAt);
    final AnimationClip walk = _clips.firstWhere((c) => c.name == 'Walking');
    final AnimationClip run = _clips.firstWhere((c) => c.name == 'Running');
    final AnimationPose expected = graph.pose.restCopy()
      ..sampleClip(walk, graph.stateTime * walk.duration);
    final AnimationPose ran = graph.pose.restCopy()
      ..sampleClip(run, graph.stateTime * run.duration);
    expected.blendFrom(ran, 1.0 - t);
    if (_dot(expected, graph.pose, _thigh) < 0.9999) {
      throw StateError('the leg is not half walk and half run');
    }

    // Root motion: the body is held over its rest and its travel handed
    // over instead, forwards.
    if (!(graph.rootDelta.z > 0.0)) throw StateError('no root motion');

    // The layer writes the arm and leaves the head to the base.
    final AnimationGraphLayer layer = _waveLayer(graph)..weight = 1.0;
    graph.layers.add(layer);
    graph.evaluate(step);
    final int arm = _node('UpperArm.R');
    if (_dot(layer.graph.pose, graph.pose, arm) < 0.9999) {
      throw StateError('the wave did not reach the arm');
    }
    if (!layer.mask.covers(arm) || layer.mask.covers(_head)) {
      throw StateError('the mask is not the right arm');
    }
    // #endregion check
  }
}
