/// Many small Flame components drawn as one instanced batch, and fire and
/// smoke from particle pools running on Flame's clock.
///
/// Quoted by `flame_crowd.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/flame_layer.dart';

/// How many sparks circle the brazier.
const int _sparks = 80;

final class FlameCrowdDemo extends ShowcaseDemo {
  late final DemoContext _context;
  late final Scene _scene;
  late final _Brazier _game;
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
      ..distance = 10.0
      ..pitch = 0.55
      ..yaw = 0.4;
    context.orbit.target.setValues(0.0, 0.8, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    _context = context;
    _scene = Scene()
      ..ambientColor = Vector3(0.45, 0.5, 0.6)
      ..ambientIntensity = 0.25
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(10.0, 0.1, 10.0)).build(),
          ),
          Material(name: 'floor', baseColor: Vector4(0.5, 0.52, 0.5, 1.0)),
          name: 'floor',
        )..setPosition(0.0, -0.05, 0.0),
      )
      ..add(
        LightNode(name: 'sun', intensity: 2.0)
          ..setLocalForward(Vector3(-0.3, -0.7, -0.4)),
      );
    _game = _Brazier(context.camera)..open3d(context.device, scene: _scene);
    // In the scene from the start, empty until the sparks take their slots.
    _scene.add(_game.batch);
    return _scene;
  }

  @override
  void update(DemoContext context, double dt) =>
      context.orbit.syncProjectionDepth(context.camera);

  /// The Flame game the page runs, for a test that steps it without a window.
  @visibleForTesting
  FlameGame get game => _game;

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) => _body;

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) throw StateError('the floor was not drawn');
    final batches = scene.meshes.whereType<InstancedMeshNode>();
    if (batches.length != 1) {
      throw StateError(
        'the sparks should be one batch, found ${batches.length}',
      );
    }
  }
}

final class _Brazier extends FlameGame with HasFlutter3d {
  _Brazier(this._eye);

  final CameraNode _eye;

  // #region batch
  /// Every spark's mesh and material, drawn in one call however many there
  /// are; each spark takes a slot in it while it is in the game.
  late final InstancedMeshNode batch = InstancedMeshNode(
    DeviceMesh.upload(device, CuboidShape(size: Vector3.all(0.12)).build()),
    Material(
      name: 'spark',
      baseColor: Vector4(1.0, 0.8, 0.4, 1.0),
      emissive: Vector3(1.0, 0.6, 0.2),
      emissiveStrength: 3.0,
    ),
    capacity: _sparks,
    name: 'sparks',
  );
  // #endregion batch

  // #region pools
  /// Fire adds light and smoke takes it away: two pools, two draws.
  final Particles3dComponent _fire = Particles3dComponent(
    system: ParticleSystem(capacity: 256),
    plane: BridgePlane.ground(),
  );
  final Particles3dComponent _smoke = Particles3dComponent(
    system: ParticleSystem(capacity: 128),
    plane: BridgePlane.ground(),
  );
  // #endregion pools

  late final DeviceMesh _puff = DeviceMesh.upload(
    device,
    const SphereShape(radius: 0.3, segments: 10, rings: 6).build(),
  );
  late final DeviceMesh _shard = DeviceMesh.upload(
    device,
    CuboidShape(size: Vector3.all(0.25)).build(),
  );

  double _clock = 0.0;

  @override
  CameraNode createCamera3d() => _eye;

  // #region sparks
  @override
  void onOpen3d() {
    addAll(<Component>[
      for (var i = 0; i < _sparks; i++)
        _Spark(batch, i * 2.0 * math.pi / _sparks, 1.5 + (i % 4) * 0.5),
      _fire,
      _smoke,
    ]);
  }
  // #endregion sparks

  // #region draw
  @override
  void onRenderer3d(Renderer renderer) {
    _fire.drawWith(renderer, _shard);
    _smoke.drawWith(renderer, _puff, blend: MeshParticleContributor.darkening);
  }
  // #endregion draw

  @override
  void update(double dt) {
    super.update(dt);
    if (!has3d) return;
    _clock += dt;
    if (_clock < 0.08) return;
    _clock = 0.0;
    _fire.burstAt(_flame, Vector2.zero(), elevation: 0.3);
    _smoke.burstAt(_soot, Vector2.zero(), elevation: 1.2);
  }

  static ParticleEffect get _flame => ParticleEffect(
    count: 4,
    emitter: const ConeEmitter(speed: Range(1.0, 2.5), halfAngleDegrees: 25.0),
    lifetime: const Range(0.4, 0.7),
    size: const Range(0.8, 1.1),
    color: Vector4(3.0, 1.6, 0.4, 1.0),
    affectors: const <ParticleAffector>[ParticleSizeOverLife()],
  );

  static ParticleEffect get _soot => ParticleEffect(
    count: 1,
    emitter: const ConeEmitter(speed: Range(0.6, 1.2), halfAngleDegrees: 20.0),
    lifetime: const Range(2.0, 2.6),
    size: const Range(0.9, 1.2),
    color: Vector4(0.25, 0.27, 0.32, 1.0),
    affectors: const <ParticleAffector>[
      ParticleDrag(1.0),
      ParticleSizeOverLife(from: 0.5, to: 2.5),
      ParticleFade(startsAt: 0.5),
    ],
  );
}

/// One spark circling the brazier: an ordinary Flame component, moved by
/// setting its position, drawn through its slot in the batch.
final class _Spark extends InstancedObject3dComponent {
  _Spark(InstancedMeshNode batch, this._phase, this._radius)
    : super(batch: batch, plane: BridgePlane.ground(), elevation: 0.5);

  final double _phase;
  final double _radius;
  double _t = 0.0;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    final turn = _phase + _t * (1.2 / _radius);
    position.setValues(_radius * math.cos(turn), _radius * math.sin(turn));
    elevation = 0.5 + 0.4 * math.sin(_t * 3.0 + _phase * 5.0);
  }
}
