/// A trigger that only cares about one layer, and a listener that hears it.
///
/// Quoted by `collision_layers.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

/// Which bit means what is a game's own business; `Layers.all` is the only
/// meaning this package ships. These two are named here, once, for this page.
const int _kPlayerLayer = 1 << 1;
const int _kEnemyLayer = 1 << 2;

/// Records every collider that started overlapping the zone it is attached
/// to, by name, in the order it happened.
final class _ZoneListener with CollisionListener {
  final List<String> started = <String>[];

  @override
  void onCollisionStart(Collider self, Collider other) {
    started.add(other.userData! as String);
  }
}

final class CollisionLayersDemo extends ShowcaseDemo {
  late final CollisionWorld _world;
  late final Collider _player;
  late final Collider _enemy;
  final _ZoneListener _listener = _ZoneListener();

  Vector3 get _zoneCentre => Vector3(0.0, 0.5, 0.0);
  Vector3 get _away => Vector3(0.0, 0.5, 6.0);

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 5.0
      ..pitch = 0.2
      ..yaw = 0.5;
  }

  @override
  Scene build(DemoContext context) {
    _world = CollisionWorld();

    // #region zone
    // The zone's mask names one layer, so only a collider carrying that bit
    // is ever considered for it, whatever mask that collider carries itself.
    final Collider zone = Collider(
      shape: CollisionSphere(0.6),
      position: _zoneCentre,
      kind: ColliderKind.trigger,
      mask: _kPlayerLayer,
      listener: _listener,
    );
    _world.add(zone);
    // #endregion zone

    // #region movers
    _player = _world.add(
      Collider(
        shape: CollisionBox(Vector3(0.3, 0.3, 0.3)),
        position: _away,
        kind: ColliderKind.kinematic,
        layer: _kPlayerLayer,
        userData: 'player',
      ),
    );
    _enemy = _world.add(
      Collider(
        shape: CollisionBox(Vector3(0.3, 0.3, 0.3)),
        position: _away,
        kind: ColliderKind.kinematic,
        layer: _kEnemyLayer,
        userData: 'enemy',
      ),
    );
    _world.update();
    // #endregion movers

    return Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            SphereShape(segments: 20, rings: 10).build(),
          ),
          Material(name: 'zone', baseColor: Vector4(0.3, 0.7, 0.9, 0.6)),
          name: 'zone',
        )..setPositionFrom(_zoneCentre),
      )
      ..add(
        LightNode(name: 'sun', intensity: 2.5)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.4)),
      );
  }

  @override
  void update(DemoContext context, double dt) {
    // #region enter
    // Both walk into the same spot. Only the one carrying the layer the
    // zone's mask names will be heard.
    _player.moveTo(_zoneCentre);
    _enemy.moveTo(_zoneCentre);
    _world.update();
    // #endregion enter
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (_listener.started.length != 1 || _listener.started.first != 'player') {
      throw StateError(
        'only the player should have entered the zone, got ${_listener.started}',
      );
    }
    // #endregion check
    if (frame.drawCalls < 1) {
      throw StateError('the zone did not reach the frame');
    }
  }
}
