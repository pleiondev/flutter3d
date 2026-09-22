part of 'arcade_game.dart';

/// The one place that turns an empty [ArcadeGame] into a yard: the ground,
/// the props, the walls, the ship and the three drones, all built from a
/// [GraphicsDevice] and wired into a [Scene] exactly once.
///
/// **An extension rather than a second class**, because the yard is not a
/// document the way a platformer's level is — it is code, and the code
/// already had exactly one caller (`main.dart`'s `buildScene`) with every
/// test reusing it rather than rebuilding it by hand. Splitting it out here
/// keeps that one caller the only one there will ever be, and gives the
/// state a private field on [ArcadeGame] would keep — [ArcadeGame._shipBody],
/// [ArcadeGame._colliderComponents] — the same access an instance method
/// would have had.
extension ArcadeGameStaging on ArcadeGame {
  /// Builds the yard once a [GraphicsDevice] is open, wiring all five
  /// bridges into [scene] and into this game's own component tree. Called
  /// exactly once, from `buildScene`.
  void spawnWorld(GraphicsDevice device, Scene scene) {
    scene
      ..add(_groundMesh(device))
      ..add(
        _prop(
          device,
          CuboidShape(size: Vector3(0.9, 3.2, 0.9)),
          Vector3(-5.0, 1.6, -2.0),
          Vector4(0.55, 0.55, 0.6, 1.0),
          'pillar 1',
        ),
      )
      ..add(
        _prop(
          device,
          CuboidShape(size: Vector3(0.9, 2.4, 0.9)),
          Vector3(5.5, 1.2, 3.5),
          Vector4(0.5, 0.5, 0.56, 1.0),
          'pillar 2',
        ),
      )
      ..add(
        _prop(
          device,
          SphereShape(radius: 0.7),
          Vector3(3.5, 0.7, -5.5),
          Vector4(0.4, 0.32, 0.26, 1.0),
          'rock 1',
        ),
      )
      ..add(
        _prop(
          device,
          SphereShape(radius: 0.5),
          Vector3(-4.5, 0.5, 4.5),
          Vector4(0.42, 0.34, 0.27, 1.0),
          'rock 2',
        ),
      )
      ..add(
        LightNode(name: 'sun', intensity: 3.2)
          ..setLocalForward(Vector3(-0.35, -1.0, -0.2)),
      );

    _buildWalls();
    _spawnShip(device, scene);
    _spawnDrones(device, scene);

    final actorStepper = ActorSystemComponent(
      system: actorSystem,
      focus: () => _shipBody.position,
    )..priority = -120;
    final physicsStepper = _PhysicsStepComponent(
      dynamics: dynamics,
      world: collisionWorld,
    )..priority = -110;
    add(actorStepper);
    add(physicsStepper);
    _actorStepper = actorStepper;
    _physicsStepper = physicsStepper;
  }

  MeshNode _groundMesh(GraphicsDevice device) => MeshNode(
    DeviceMesh.upload(
      device,
      PlaneShape(
        width: arenaHalfWidth * 2.0,
        depth: arenaHalfDepth * 2.0,
      ).build(),
    ),
    engine.Material(
      name: 'yard floor',
      lighting: LightingModel.pbr,
      baseColor: Vector4(0.14, 0.15, 0.19, 1.0),
      roughness: 0.95,
    ),
    name: 'ground',
  );

  MeshNode _prop(
    GraphicsDevice device,
    Shape shape,
    Vector3 at,
    Vector4 color,
    String name,
  ) => MeshNode(
    DeviceMesh.upload(device, shape.build()),
    engine.Material(
      name: name,
      lighting: LightingModel.pbr,
      baseColor: color,
      roughness: 0.85,
    ),
    name: name,
  )..setPosition(at.x, at.y, at.z);

  /// Four static boundary colliders — no mesh, just a wall neither the ship's
  /// [Dynamics] pass nor a drone's [CharacterController] sweep can be pushed
  /// through. What makes the yard a yard rather than an unbounded plane.
  void _buildWalls() {
    const double thickness = 1.0;
    const double height = 5.0;
    final double spanX = arenaHalfWidth * 2.0 + thickness * 2.0;
    final double spanZ = arenaHalfDepth * 2.0 + thickness * 2.0;

    collisionWorld
      ..addBox(
        Vector3(0.0, height / 2.0, -arenaHalfDepth - thickness / 2.0),
        Vector3(spanX, height, thickness),
      )
      ..addBox(
        Vector3(0.0, height / 2.0, arenaHalfDepth + thickness / 2.0),
        Vector3(spanX, height, thickness),
      )
      ..addBox(
        Vector3(-arenaHalfWidth - thickness / 2.0, height / 2.0, 0.0),
        Vector3(thickness, height, spanZ),
      )
      ..addBox(
        Vector3(arenaHalfWidth + thickness / 2.0, height / 2.0, 0.0),
        Vector3(thickness, height, spanZ),
      );
  }

  void _spawnShip(GraphicsDevice device, Scene scene) {
    // The ship flies at the same altitude as a drone, half-extents chosen so
    // their vertical ranges overlap — a ship at ground level and a drone
    // floating above it would share an X/Z path all day and never actually
    // touch, which is not what "top-down" means to a player watching from
    // straight overhead.
    _shipBody = dynamics.add(
      RigidBody(
        world: collisionWorld,
        shape: CollisionBox(Vector3(0.45, 0.35, 0.45)),
        position: Vector3(0.0, 1.2, -arenaHalfDepth + 2.5),
        mass: 1.0,
      ),
    );

    final mesh = MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(0.85, 0.5, 0.95)).build(),
      ),
      engine.Material(
        name: 'ship',
        lighting: LightingModel.pbr,
        baseColor: Vector4(0.3, 0.78, 0.95, 1.0),
        roughness: 0.3,
      ),
      name: 'ship',
    );

    ship = ShipComponent(
      body: _shipBody,
      node: mesh,
      scene: scene,
      plane: ArcadeGame.groundPlane,
    )..priority = -50;
    _colliderComponents[_shipBody.collider] = ship;

    CollisionBridge(
      collider: _shipBody.collider,
      component: ship,
      resolveOther: (Collider other) => _colliderComponents[other],
    );
    ship.onCollisionStartCallback =
        (Set<Vector2> points, PositionComponent other) {
          if (other is ActorComponent) _onShipHitDrone(other);
        };

    add(ship);
  }

  /// Three drones patrolling three lanes of the yard — see this class's own
  /// doc comment for why each is an [ActorComponent] rather than a
  /// [RigidBodyComponent].
  void _spawnDrones(GraphicsDevice device, Scene scene) {
    const MovementTuning droneTuning = MovementTuning(
      gravity: 0.0,
      walkSpeed: 2.6,
      groundAcceleration: 30.0,
    );
    final beats = <(Vector3, Vector3)>[
      (Vector3(-9.0, 1.3, -3.0), Vector3(9.0, 1.3, -3.0)),
      (Vector3(9.0, 1.3, 1.0), Vector3(-9.0, 1.3, 1.0)),
      (Vector3(-6.0, 1.3, 5.0), Vector3(6.0, 1.3, 5.0)),
    ];

    for (var i = 0; i < beats.length; i++) {
      final (from, to) = beats[i];
      final body = CharacterController(
        world: collisionWorld,
        shape: CollisionBox(Vector3(0.4, 0.4, 0.4)),
        position: from.clone(),
        tuning: droneTuning,
      );
      final actor = actorSystem.spawn(body: body, brain: PatrolBrain(from, to));

      final mesh = MeshNode(
        DeviceMesh.upload(device, SphereShape(radius: 0.42).build()),
        engine.Material(
          name: 'drone $i',
          lighting: LightingModel.pbr,
          baseColor: Vector4(0.92, 0.38, 0.22, 1.0),
          roughness: 0.4,
          emissive: Vector3(0.25, 0.08, 0.02),
        ),
        name: 'drone $i',
      );

      final drone = ActorComponent(
        actor: actor,
        node: mesh,
        scene: scene,
        plane: ArcadeGame.groundPlane,
      )..priority = -50;
      _colliderComponents[body.collider] = drone;
      drones.add(drone);
      add(drone);
    }
  }
}
