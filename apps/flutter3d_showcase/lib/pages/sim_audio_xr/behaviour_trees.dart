/// A guard whose mind is a JSON document: patrol between two posts until
/// the target comes out from behind the wall, then chase it. The overlay
/// draws the path the tree took, one stroke a node, and a line to where
/// its leaf is going.
///
/// Quoted by `behaviour_trees.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' hide Pose;

final class BehaviourTreesDemo extends ShowcaseDemo {
  late (ActorSystem, Actor) _run;
  ActorSystem get _system => _run.$1;
  Actor get _guard => _run.$2;
  late final MeshNode _guardMesh;
  late final MeshNode _targetMesh;
  Renderer? _renderer;

  final Vector3 _target = Vector3(0.0, 0.9, 4.0);
  double _clock = 0.0;
  double _carry = 0.0;
  bool overlay = true;

  static const double _step = 1 / 60;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 18.0
      ..pitch = 0.8
      ..yaw = 0.0;
    context.orbit.target.setValues(0.0, 0.0, 0.0);
  }

  // #region tree
  /// A selector asks its children in order, from the top, every time it is
  /// ticked: chase if the target can be seen, otherwise patrol. A sequence
  /// resumes where it was, so the patrol keeps its place between ticks.
  static const Map<String, Object?> document = <String, Object?>{
    'kind': 'selector',
    'name': 'guard',
    'children': <Object?>[
      <String, Object?>{
        'kind': 'sequence',
        'name': 'chase',
        'children': <Object?>[
          <String, Object?>{'kind': 'seesFocus'},
          <String, Object?>{'kind': 'goToFocus', 'within': 1.2},
        ],
      },
      <String, Object?>{
        'kind': 'sequence',
        'name': 'patrol',
        'children': <Object?>[
          <String, Object?>{'kind': 'goTo', 'key': 'a'},
          <String, Object?>{'kind': 'wait', 'seconds': 0.5},
          <String, Object?>{'kind': 'goTo', 'key': 'b'},
          <String, Object?>{'kind': 'wait', 'seconds': 0.5},
        ],
      },
    ],
  };
  // #endregion tree

  // #region read
  /// Leaves are found by kind in `BehaviorKinds`; the standard ones are
  /// what an actor's `Mind` already does. A document with problems gives no
  /// tree and every problem with where it is.
  static BehaviorTree readTree() {
    final BehaviorTreeRead read = BehaviorTree.read(document, BehaviorKinds());
    final BehaviorTree? tree = read.tree;
    if (tree == null) throw FormatException(read.problems.join('\n'));
    return tree;
  }
  // #endregion read

  // #region spawn
  /// A floor, a wall the guard cannot see through, and the guard on the far
  /// side of it. What the tree knows lives on a `Blackboard` component of
  /// the guard's entity, here its two posts; the brain keeps nothing.
  static (ActorSystem, Actor) _world() {
    final world = CollisionWorld()
      ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(30.0, 1.0, 20.0))
      ..addBox(Vector3(0.0, 1.0, 0.0), Vector3(10.0, 2.0, 0.4))
      ..update();
    final system = ActorSystem(world: world, random: GameRandom(1));
    final Actor guard = system.spawn(
      body: CharacterController(world: world, position: Vector3(-4, 0.9, -3)),
      brain: BehaviorBrain(readTree()),
      name: 'guard',
    );
    system.entities.set(
      guard.entity,
      Blackboard(
        values: <String, Object?>{
          'a': <double>[-4.0, 0.9, -3.0],
          'b': <double>[4.0, 0.9, -3.0],
        },
      ),
    );
    return (system, guard);
  }
  // #endregion spawn

  @override
  Scene build(DemoContext context) {
    _run = _world();
    MeshNode box(Vector3 at, Vector3 size, Vector4 color, String name) =>
        MeshNode(
          DeviceMesh.upload(context.device, CuboidShape(size: size).build()),
          RenderMaterial(name: name, baseColor: _fromSrgb(color)),
          name: name,
        )..setPosition(at.x, at.y, at.z);
    _guardMesh = box(
      Vector3.zero(),
      Vector3(0.7, 1.8, 0.7),
      Vector4(0.85, 0.3, 0.25, 1.0),
      'guard',
    );
    _targetMesh = MeshNode(
      DeviceMesh.upload(context.device, SphereShape(segments: 12).build()),
      RenderMaterial(
        name: 'target',
        baseColor: LinearColor.fromSrgb(0.3, 0.6, 0.95, 1.0),
      ),
      name: 'target',
    )..setScale(0.4, 0.4, 0.4);
    // #region overlay
    // The overlay reads the boards and never makes one, so turning it on
    // cannot change what a snapshot holds.
    _renderer = context.renderer
      ..debugLines = (DebugDraw lines) {
        if (overlay) BehaviorOverlay(_system).draw(lines);
      };
    // #endregion overlay
    _place();
    return Scene()
      ..ambientIntensity = 0.35 * Photometric.legacyUnit
      ..add(
        LightNode(name: 'sun', intensity: 2.5 * Photometric.legacyUnit)
          ..setLocalForward(Vector3(-0.3, -0.8, -0.4)),
      )
      ..add(
        box(
          Vector3(0.0, -0.5, 0.0),
          Vector3(30.0, 1.0, 20.0),
          Vector4(0.38, 0.4, 0.44, 1.0),
          'floor',
        ),
      )
      ..add(
        box(
          Vector3(0.0, 1.0, 0.0),
          Vector3(10.0, 2.0, 0.4),
          Vector4(0.62, 0.58, 0.5, 1.0),
          'wall',
        ),
      )
      ..add(_guardMesh)
      ..add(_targetMesh);
  }

  @override
  void dispose() {
    _renderer?.debugLines = null;
  }

  void _place() {
    final Vector3 at = _guard.position ?? Vector3.zero();
    _guardMesh.setPosition(at.x, at.y, at.z);
    _targetMesh.setPosition(_target.x, _target.y, _target.z);
  }

  // #region step
  /// One fixed step: the system thinks for every actor, the tree ticks from
  /// its root, and the leaf it reaches acts.
  static void _stepOnce(ActorSystem system, Vector3 target) {
    system
      ..beginStep()
      ..step(_step, focus: target);
  }
  // #endregion step

  @override
  void update(DemoContext context, double dt) {
    _clock += dt;
    // Behind the wall for most of the cycle, out past its end for a while.
    _target.x = 9.0 * math.sin(_clock * 0.35);
    _carry += math.min(dt, 0.1);
    while (_carry >= _step) {
      _carry -= _step;
      _stepOnce(_system, _target);
    }
    _place();
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Draw the path the tree took',
      value: () => overlay,
      onChanged: (bool v) => overlay = v,
    ),
    ToggleControl(
      'Start again',
      value: () => false,
      onChanged: (bool v) {
        if (!v) return;
        _run = _world();
        _clock = 0.0;
      },
    ),
  ];

  /// The path the guard took last, by name, for a test.
  @visibleForTesting
  List<String> get described => BehaviorOverlay(_system).describe();

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) throw StateError('nothing reached the frame');
    // #region check
    final (ActorSystem system, Actor guard) = _world();
    String leaf() => BehaviorBrain.pathOf(guard).last.kind;
    String branch() => BehaviorBrain.pathOf(guard)[1].label;

    // Hidden behind the wall: the guard patrols.
    final Vector3 hidden = Vector3(0.0, 0.9, 4.0);
    for (var i = 0; i < 60; i++) {
      _stepOnce(system, hidden);
    }
    if (branch() != 'patrol' || !<String>{'goTo', 'wait'}.contains(leaf())) {
      throw StateError('not patrolling: ${BehaviorOverlay(system).describe()}');
    }
    // Out past the wall's end, in sight from anywhere on the patrol: from
    // post a, at x = −4, the line to a point four metres behind the wall
    // still crosses it, so the point stands a metre behind it, where the
    // line from either post passes the wall's end at x = 5.
    final Vector3 seen = Vector3(9.0, 0.9, 1.0);
    for (var i = 0; i < 5; i++) {
      _stepOnce(system, seen);
    }
    if (branch() != 'chase' || leaf() != 'goToFocus') {
      throw StateError('not chasing: ${BehaviorOverlay(system).describe()}');
    }
    // The overlay draws a stroke per node on the path and a line to the goal.
    final DebugDraw lines = DebugDraw();
    BehaviorOverlay(system).draw(lines);
    if (lines.lineCount != BehaviorBrain.pathOf(guard).length + 1) {
      throw StateError('the overlay drew ${lines.lineCount} lines');
    }
    // #endregion check
  }
}

/// A `Vector4` holding a colour sRGB-encoded, as the linear colour it names.
LinearColor _fromSrgb(Vector4 c) => LinearColor.fromSrgb(c.x, c.y, c.z, c.w);
