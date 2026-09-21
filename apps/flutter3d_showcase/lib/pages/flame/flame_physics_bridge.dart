/// `RigidBodyComponent` and `CollisionBridge` carrying a falling
/// `RigidBody`'s own physics, and its landing, onto Flame.
///
/// Quoted by `flame_physics_bridge.md` and shown whole in the Source tab.
library;

import 'package:flame/components.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_flame/flutter3d_flame.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/flame_layer.dart';

/// Hears about the crate's landing the way any Flame component would, and
/// tells whoever is watching.
final class _TrackingRigidBodyComponent extends RigidBodyComponent {
  _TrackingRigidBodyComponent({
    required super.body,
    required super.node,
    required super.scene,
    required super.plane,
    this.onTouch,
  });

  bool collided = false;
  PositionComponent? other;

  /// Called with `true` when the crate starts touching the landing pad and
  /// `false` when it stops.
  final void Function(bool touching)? onTouch;

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    super.onCollisionStart(intersectionPoints, other);
    collided = true;
    this.other = other;
    onTouch?.call(true);
  }

  @override
  void onCollisionEnd(PositionComponent other) {
    super.onCollisionEnd(other);
    onTouch?.call(false);
  }
}

final class FlamePhysicsBridgeDemo extends ShowcaseDemo {
  late final String _report;
  late final double _crateHeight;
  late final bool _collided;

  double dropHeight = 2.5;

  late final DemoContext _context;
  late final Scene _scene;
  late final MeshNode _pad;
  late final TransparentFlameGame _game;
  late final Widget _body = flameOrbit(
    _context,
    Flutter3dFlameWidget(
      game: _game,
      camera: _context.camera,
      existing: (device: _context.device, renderer: _context.renderer),
      buildScene: (GraphicsDevice device) => _scene,
    ),
  );

  static const Color _idle = Color(0xFFE6B333);
  static const Color _touching = Color(0xFF4DD966);
  static Vector4 get _padIdle => Vector4(0.45, 0.36, 0.14, 1.0);
  static Vector4 get _padTouching => Vector4(0.2, 0.6, 0.28, 1.0);

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 6.5
      ..pitch = 0.3
      ..yaw = 0.7;
    context.orbit.target.setValues(0.0, 0.8, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    _context = context;
    final (String report, double height, bool collided) = _run(context.device);
    _report = report;
    _crateHeight = height;
    _collided = collided;

    MeshNode cuboid(String name, Vector3 size, Vector4 color) => MeshNode(
      DeviceMesh.upload(context.device, CuboidShape(size: size).build()),
      Material(name: name, baseColor: color),
      name: name,
    );
    _pad = cuboid('landing pad', Vector3(6.0, 0.1, 6.0), _padIdle)
      ..setPosition(0.0, 0.02, 0.0);
    final MeshNode crate = cuboid(
      'crate',
      Vector3(0.6, 0.6, 0.6),
      Vector4(0.7, 0.5, 0.3, 1.0),
    );
    _scene = Scene()
      ..ambientColor = Vector3(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.3
      ..add(
        cuboid('floor', Vector3(6.0, 1.0, 6.0), Vector4(0.36, 0.4, 0.38, 1.0))
          ..setPosition(0.0, -0.5, 0.0),
      )
      ..add(_pad)
      ..add(crate)
      ..add(
        LightNode(name: 'sun', intensity: 2.5)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.4)),
      );

    // #region live
    // The same world, body and bridge as above, running: a component steps the
    // solver and dispatches the overlaps, and the crate's own component copies
    // where the body went. The map is a side view, Flame's y being height.
    final CollisionWorld world = CollisionWorld()
      ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(6.0, 1.0, 6.0));
    final Collider sensor = world.add(
      Collider(
        shape: CollisionBox(Vector3(3.0, 0.05, 3.0)),
        position: Vector3(0.0, 0.02, 0.0),
        kind: ColliderKind.trigger,
      ),
    );
    final Dynamics dynamics = Dynamics(world: world);
    final RigidBody body = dynamics.add(
      RigidBody(
        world: world,
        shape: CollisionBox(Vector3(0.3, 0.3, 0.3)),
        position: Vector3(0.0, dropHeight, 0.0),
        mass: 1.0,
      ),
    );
    final Map<String, Object?> start = body.save();

    final RectangleComponent landing = RectangleComponent(
      position: Vector2(-3.0, -0.03),
      size: Vector2(6.0, 0.1),
      paint: Paint()..color = _idle,
    );
    final _TrackingRigidBodyComponent crateComponent =
        _TrackingRigidBodyComponent(
          body: body,
          node: crate,
          scene: _scene,
          plane: BridgePlane.backdrop(),
          // The Flame side reacts to the collision it was handed.
          onTouch: (bool touching) {
            landing.paint.color = touching ? _touching : _idle;
            _pad.material.baseColor.setFrom(touching ? _padTouching : _padIdle);
          },
        )..add(
          RectangleComponent(
            size: Vector2.all(0.6),
            anchor: Anchor.center,
            paint: Paint()..color = const Color(0xFFB2804D),
          ),
        );
    CollisionBridge(
      collider: body.collider,
      component: crateComponent,
      resolveOther: (Collider other) => other == sensor ? landing : null,
    );
    // #endregion live

    final FlameMinimap map = FlameMinimap();
    map.world.position = Vector2(120.0, 190.0);
    map.world.addAll(<Component>[
      RectangleComponent(
        position: Vector2(-4.0, 0.0),
        size: Vector2(8.0, 0.6),
        paint: Paint()..color = const Color(0xFF5C6660),
      ),
      landing,
      crateComponent,
    ]);
    _game = TransparentFlameGame()
      ..add(_Fall(world, dynamics, body, start, () => dropHeight))
      ..add(map)
      ..add(flameCaption('the map: a side view of the same fall'))
      ..add(
        flameCaption(
          'the pad turns green when Flame hears the landing',
          at: Vector2(16.0, 40.0),
        ),
      )
      ..add(flameCaption(_report, at: Vector2(16.0, 64.0)));
    return _scene;
  }

  static (String, double, bool) _run(GraphicsDevice device) {
    // #region world
    final world = CollisionWorld();
    world.addBox(Vector3(0.0, -0.5, 0.0), Vector3(6.0, 1.0, 6.0));
    // A thin trigger embedded just above the floor, so the crate's fall
    // genuinely overlaps something: `Dynamics` stops a falling body exactly
    // at the surface it lands on, never inside it, so the floor itself never
    // reports an overlap to relay. `Dynamics.step` ignores triggers entirely
    // (`includeTriggers: false` in its own contact queries), so this sensor
    // never affects how or where the crate actually lands.
    final landingSensor = world.add(
      Collider(
        shape: CollisionBox(Vector3(3.0, 0.05, 3.0)),
        position: Vector3(0.0, 0.02, 0.0),
        kind: ColliderKind.trigger,
      ),
    );
    final dynamics = Dynamics(world: world);
    // #endregion world

    // #region body
    final body = dynamics.add(
      RigidBody(
        world: world,
        shape: CollisionBox(Vector3(0.3, 0.3, 0.3)),
        position: Vector3(0.0, 2.0, 0.0),
        mass: 1.0,
      ),
    );
    // #endregion body

    // #region bridge
    final scene = Scene();
    final node = MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(0.6, 0.6, 0.6)).build(),
      ),
      Material(name: 'bridged-crate', baseColor: Vector4(0.7, 0.5, 0.3, 1.0)),
    );
    scene.add(node);
    final component = _TrackingRigidBodyComponent(
      body: body,
      node: node,
      scene: scene,
      plane: BridgePlane.ground(),
    );
    // A Flame component standing in for the landing sensor, so the bridge
    // below has somewhere real to hand back — a collider with no Flame side
    // of its own would make `resolveOther` answer null, and the bridge
    // calls nothing when it does.
    final landingMarker = PositionComponent();
    CollisionBridge(
      collider: body.collider,
      component: component,
      resolveOther: (Collider other) =>
          other == landingSensor ? landingMarker : null,
    );
    // #endregion bridge

    // #region fall
    // Falls, lands, and the world dispatches the overlap each step — the
    // same two calls `physics_particles/collision_layers.dart` already makes
    // by hand, now feeding a Flame collision callback instead of a listener
    // this page owns directly.
    const double step = 1 / 60;
    for (var i = 0; i < 180; i++) {
      dynamics.step(step);
      world.update();
    }
    component.update(step);
    // #endregion fall

    return (
      'settled at y=${body.position.y.toStringAsFixed(2)}; the bridge heard '
          'the landing: ${component.collided}',
      body.position.y,
      component.collided,
    );
  }

  /// The Flame game the page runs, for a test that steps it without a window.
  @visibleForTesting
  TransparentFlameGame get game => _game;

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) => _body;

  @override
  void update(DemoContext context, double dt) {
    context.orbit.syncProjectionDepth(context.camera);
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Drop height',
      min: 0.5,
      max: 4.0,
      value: () => dropHeight,
      onChanged: (double v) => dropHeight = v,
      format: (double v) => '${v.toStringAsFixed(1)} m',
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the crate marker was not drawn');
    }
    // Compared as numbers and booleans, not read back out of `_report`: see
    // `sim_audio_xr/actors.dart` for why.
    if ((_crateHeight - 0.3).abs() > 0.05) {
      throw StateError(
        'the crate should have settled at y = 0.3, got $_crateHeight',
      );
    }
    if (!_collided) {
      throw StateError(
        'CollisionBridge should have relayed the landing to the Flame '
        'component',
      );
    }
  }
}

/// Steps the solver and the collision world once a Flame frame, and lets the
/// crate go again a moment after it lands. Added before the crate's own
/// component, so the body has moved by the time the component copies it.
final class _Fall extends Component {
  _Fall(this._world, this._dynamics, this._body, this._start, this._height);

  final CollisionWorld _world;
  final Dynamics _dynamics;
  final RigidBody _body;
  final Map<String, Object?> _start;
  final double Function() _height;
  double _rest = 0.0;

  @override
  void update(double dt) {
    super.update(dt);
    _dynamics.step(1 / 60);
    _world.update();
    _rest = _body.isAsleep ? _rest + dt : 0.0;
    if (_rest > 1.2) {
      _body.restore(_start);
      _body.position.y = _height();
      _rest = 0.0;
    }
  }
}
