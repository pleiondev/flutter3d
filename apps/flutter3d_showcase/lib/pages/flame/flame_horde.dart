/// A horde of `flutter3d_sim` actors drawn as slots of one instanced batch,
/// stepped by one `ActorSystemComponent` towards two players at once.
///
/// Quoted by `flame_horde.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flame/components.dart' show Component;
import 'package:flame/game.dart';
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/flame_layer.dart';
import 'package:flutter3d_showcase/src/demo/run_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// How many monsters there are: one draw for all of them.
const int _monsters = 96;

// #region brain
/// Walks at whichever player the system says it can reach first, and
/// remembers which one that was.
final class _Chase extends Brain {
  int attended = -1;

  @override
  void act(Mind it) {
    attended = it.focusIndex;
    it.steerTowardsFocus();
  }
}
// #endregion brain

final class FlameHordeDemo extends ShowcaseDemo {
  late final DemoContext _context;
  late final Scene _scene;
  late final _Horde _game;
  late final Widget _body = flameOrbit(
    _context,
    Flutter3dFlameWidget(
      game: _game,
      existing: (device: _context.device, renderer: _context.renderer),
    ),
  );

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 22.0
      ..pitch = 0.95
      ..yaw = 0.2;
    context.orbit.target.setValues(0.0, 0.0, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    _context = context;
    _scene = Scene()
      ..ambientColor = LinearColor(0.45, 0.5, 0.6)
      ..ambientIntensity = 0.3 * Photometric.legacyUnit
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(28.0, 0.1, 28.0)).build(),
          ),
          RenderMaterial(
            name: 'floor',
            baseColor: LinearColor.fromSrgb(0.34, 0.36, 0.33, 1.0),
          ),
          name: 'floor',
        )..setPosition(0.0, -0.05, 0.0),
      )
      ..add(
        LightNode(name: 'sun', intensity: 2.2 * Photometric.legacyUnit)
          ..setLocalForward(Vector3(-0.3, -0.7, -0.4)),
      );
    _game = _Horde(context.camera)..open3d(context.device, scene: _scene);
    // In the scene from the start, empty until the monsters take their slots.
    _scene.add(_game.batch);
    return _scene;
  }

  @override
  void update(DemoContext context, double dt) =>
      context.orbit.syncProjectionDepth(context.camera);

  /// The Flame game the page runs, for a test that steps it without a window.
  @visibleForTesting
  FlameGame get game => _game;

  /// The one batch every monster is drawn through.
  @visibleForTesting
  InstancedMeshNode get batch => _game.batch;

  /// Every monster's body, and which player it went for on its last step.
  @visibleForTesting
  List<({Vector3 at, int attended})> get monsters =>
      <({Vector3 at, int attended})>[
        for (final (Actor actor, _Chase brain) in _game.monsters)
          (at: actor.body!.position, attended: brain.attended),
      ];

  /// Where the two players are now.
  @visibleForTesting
  List<Vector3> get players => <Vector3>[
    for (final MeshNode hero in _game.heroes) hero.readPosition(),
  ];

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) => _body;

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) throw StateError('the floor was not drawn');
    final batches = scene.meshes.whereType<InstancedMeshNode>();
    if (batches.length != 1) {
      throw StateError(
        'the horde should be one batch, found ${batches.length}',
      );
    }
  }
}

/// The colour a monster wears for the player it is after.
final List<Vector4> _playerColours = <Vector4>[
  Vector4(0.95, 0.55, 0.2, 1.0),
  Vector4(0.3, 0.7, 0.95, 1.0),
];

final class _Horde extends FlameGame with HasFlutter3d {
  _Horde(this._eye);

  final CameraNode _eye;
  final List<MeshNode> heroes = <MeshNode>[];
  final List<(Actor, _Chase)> monsters = <(Actor, _Chase)>[];

  // #region batch
  /// Every monster's mesh and material, drawn in one call however many there
  /// are; the colour is each slot's own.
  late final InstancedMeshNode batch = InstancedMeshNode(
    DeviceMesh.upload(
      device,
      CuboidShape(size: Vector3(0.6, 1.0, 0.6)).build(),
    ),
    RenderMaterial(name: 'monster', baseColor: LinearColor.white),
    capacity: _monsters,
    name: 'horde',
  );
  // #endregion batch

  double _clock = 0.0;

  @override
  CameraNode createCamera3d() => _eye;

  @override
  void onOpen3d() {
    final CollisionWorld world = onRunPhysics(CollisionWorld())
      ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(28.0, 1.0, 28.0))
      ..update();
    final ActorSystem system = ActorSystem(world: world, random: GameRandom(7));
    final DeviceMesh ball = DeviceMesh.upload(
      device,
      SphereShape(segments: 24, radius: 0.5).build(),
    );
    for (var i = 0; i < 2; i++) {
      final MeshNode hero = MeshNode(
        ball,
        RenderMaterial(
          name: 'player $i',
          baseColor: _fromSrgb(_playerColours[i]),
          emissive: _playerColours[i].xyz.toLinearColor(),
          emissiveStrength: 1.5 * Photometric.legacyNits,
        ),
        name: 'player $i',
      );
      heroes.add(hero);
      scene.add(hero);
    }
    _walkHeroes();

    // #region foci
    // One system, stepped towards both players: each monster goes for the
    // one it can reach first. The system is a step clock too, and every
    // monster is drawn between its last two steps by it.
    final ActorSystemComponent stepper = ActorSystemComponent(
      system: system,
      foci: () => <FocusPoint>[
        for (final MeshNode hero in heroes)
          (at: hero.readPosition()..y = 0.9, body: null),
      ],
    );
    // #endregion foci

    // #region spawn
    // Two rings of monsters, each an actor in the system and a slot in the
    // batch; no scene node of their own.
    final List<Component> slots = <Component>[];
    for (var i = 0; i < _monsters; i++) {
      final double radius = i.isEven ? 9.0 : 11.0;
      final double angle = i * 2.0 * math.pi / _monsters;
      final _Chase brain = _Chase();
      final Actor actor = system.spawn(
        body: CharacterController(
          world: world,
          position: Vector3(
            radius * math.cos(angle),
            0.9,
            radius * math.sin(angle),
          ),
          tuning: const MovementSettings(walkSpeed: 2.2),
        ),
        brain: brain,
      );
      monsters.add((actor, brain));
      slots.add(
        _Monster(actor: actor, batch: batch, stepper: stepper, brain: brain),
      );
    }
    addAll(<Component>[stepper, ...slots]);
    // #endregion spawn
    add(flameCaption('one draw, two players: each monster wears its target'));
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!has3d || heroes.isEmpty) return;
    _clock += dt;
    _walkHeroes();
  }

  /// Two players walking circles of their own on either side of the yard.
  void _walkHeroes() {
    for (var i = 0; i < heroes.length; i++) {
      final double side = i == 0 ? -1.0 : 1.0;
      final double turn = _clock * 0.5 + i * math.pi;
      heroes[i].setPosition(
        side * 3.5 + 2.5 * math.cos(turn),
        0.5,
        2.5 * math.sin(turn),
      );
    }
  }
}

// #region monster
/// A monster drawn through its slot, between its steps, in the colour of
/// the player its brain went for.
final class _Monster extends InstancedActorComponent {
  _Monster({
    required super.actor,
    required super.batch,
    required ActorSystemComponent super.stepper,
    required this.brain,
  }) : super(lift: -0.4);

  final _Chase brain;
  int _shown = -1;

  @override
  void update(double dt) {
    super.update(dt);
    final InstanceHandle? at = slot;
    if (at == null || brain.attended == _shown || brain.attended < 0) return;
    _shown = brain.attended;
    at.setColor(_playerColours[_shown].toLinearColor());
  }
}
// #endregion monster

/// A `Vector4` holding a colour sRGB-encoded, as the linear colour it names.
LinearColor _fromSrgb(Vector4 c) => LinearColor.fromSrgb(c.x, c.y, c.z, c.w);
