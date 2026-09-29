part of 'arcade_game.dart';

/// The one place that turns an empty [ArcadeGame] into a yard: the ground,
/// the props, the walls, the ship and the three bots, all built from a
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
    _device = device;
    _scene = scene;
    // Seen straight down, a pillar is its top face and nothing else, so its
    // shadow has to read as a shadow on its own: short, under a sun high
    // enough that the pillar still seems to stand in it, and grey rather
    // than a black hole in the floor. The default ambient of 0.06 made it
    // black, and so did 0.6: the ambient term is on the scale of the sun's
    // after its division by pi, and the tone curve crushes what is left of
    // a dark floor near zero. At 2.0 the shadowed floor is about 40% of the
    // lit one on screen.
    scene
      ..ambientIntensity = 2.0
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
          ..setLocalForward(Vector3(-0.2, -1.0, -0.12)),
      );

    wardrobe = ModelWardrobe<CraftRole>(
      device: device,
      scene: scene,
      looks: <CraftRole, ModelLook>{
        for (final MapEntry(key: role, value: look) in _looks.entries)
          role: ModelLook(look.file, length: look.length),
      },
      onDressed: _paintAccent,
    );
    _buildWalls();
    _spawnShip(device, scene);
    _spawnBots(device, scene);

    final actorStepper = ActorSystemComponent(
      system: actorSystem,
      focus: () => _shipBody.position,
      priority: -120,
    );
    final physicsStepper = PhysicsStepComponent(
      dynamics: dynamics,
      world: collisionWorld,
      afterStep: () => shipSensor
        ..position.setFrom(_shipBody.position)
        ..refreshBounds(),
      priority: -110,
    );
    add(actorStepper);
    add(physicsStepper);
    _actorStepper = actorStepper;
    _physicsStepper = physicsStepper;
    spawned = true;
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
  /// [Dynamics] pass nor a bot's [CharacterController] sweep can be pushed
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
    // The ship flies at the same altitude as a bot, half-extents chosen so
    // their vertical ranges overlap — a ship at ground level and a bot
    // floating above it would share an X/Z path all day and never actually
    // touch, which is not what "top-down" means to a player watching from
    // straight overhead.
    _shipBody = dynamics.add(
      RigidBody(
        world: collisionWorld,
        shape: CollisionBox(Vector3(0.45, 0.35, 0.45)),
        position: ArcadeGame.shipStart.clone(),
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
      name: 'ship primitive',
    );
    // Drawn by its visual node: see [ArcadeGameCrafts] for why a model
    // arriving later swaps what that node holds and not the bridged node.
    ship = ShipComponent(
      body: _shipBody,
      node: SceneNode(name: 'ship'),
      scene: scene,
      plane: ArcadeGame.groundPlane,
    )..priority = -50;
    ship.visual.add(mesh);
    wardrobe.dress(ship.visual, CraftRole.ship);
    _colliderComponents[_shipBody.collider] = ship;

    // The bridge listens on the sensor, not the hull: see [shipSensor] for
    // why the hull never reports a bot. The sensor also overlaps the hull
    // itself, which resolves to the ship and is not a bot, so nothing
    // comes of it.
    shipSensor = collisionWorld.add(
      Collider(
        shape: CollisionBox(Vector3(0.6, 0.5, 0.6)),
        position: ArcadeGame.shipStart.clone(),
        kind: ColliderKind.trigger,
      ),
    );
    CollisionBridge(
      collider: shipSensor,
      component: ship,
      resolveOther: (Collider other) => _colliderComponents[other],
    );
    ship.onCollisionStartCallback =
        (Set<Vector2> points, PositionComponent other) {
          if (other is ActorComponent) _onShipHitBot(other);
        };

    add(ship);
  }

  /// The current [level]'s bots, one to a lane — see this class's own doc
  /// comment for why each is an [ActorComponent] rather than a
  /// [RigidBodyComponent].
  ///
  /// The lanes run across the yard, spread evenly from its top to a few
  /// metres short of [ArcadeGame.shipStart], so no bot starts on top of
  /// the ship; neighbouring lanes walk opposite ways. The first
  /// [ArcadeLevel.hunters] bots hunt, and glow magenta rather than orange
  /// so a player can tell which ones will come for the ship.
  void _spawnBots(GraphicsDevice device, Scene scene) {
    final level = this.level;
    final botTuning = MovementTuning(
      gravity: 0.0,
      walkSpeed: level.botSpeed,
      groundAcceleration: 30.0,
    );
    const double top = -arenaHalfDepth + 2.0;
    final double bottom = ArcadeGame.shipStart.z - 3.5;
    const double reach = arenaHalfWidth - 4.0;

    for (var i = 0; i < level.bots; i++) {
      final z = level.bots == 1
          ? top
          : top + (bottom - top) * i / (level.bots - 1);
      final left = Vector3(-reach, 1.3, z);
      final right = Vector3(reach, 1.3, z);
      final (from, to) = i.isEven ? (left, right) : (right, left);
      final hunter = i < level.hunters;
      // Each bot starts its own way along its lane, stepped by the golden
      // ratio so no two start together. Started at the ends, every bot
      // of a level kept pace with every other and the yard marched in two
      // columns.
      final along = (i * 0.618034) % 1.0;
      final start = from + (to - from) * along;

      final body = CharacterController(
        world: collisionWorld,
        shape: CollisionBox(Vector3(0.4, 0.4, 0.4)),
        position: start,
        tuning: botTuning,
      );
      final actor = actorSystem.spawn(
        body: body,
        brain: BotBrain(
          from,
          to,
          chaseRadius: hunter ? level.chaseRadius : 0.0,
          dodgeRadius: level.dodgeRadius,
          shipHeading: () => shipHeading,
        ),
      );

      final mesh = MeshNode(
        DeviceMesh.upload(device, SphereShape(radius: 0.42).build()),
        engine.Material(
          name: 'bot $i',
          lighting: LightingModel.pbr,
          baseColor: hunter
              ? Vector4(0.85, 0.25, 0.75, 1.0)
              : Vector4(0.92, 0.38, 0.22, 1.0),
          roughness: 0.4,
          emissive: hunter
              ? Vector3(0.3, 0.05, 0.25)
              : Vector3(0.25, 0.08, 0.02),
        ),
        name: 'bot $i primitive',
      );
      final bot = ActorComponent(
        actor: actor,
        node: SceneNode(name: 'bot $i'),
        scene: scene,
        plane: ArcadeGame.groundPlane,
      )..priority = -50;
      bot.visual.add(mesh);
      wardrobe.dress(bot.visual, hunter ? CraftRole.hunter : CraftRole.patrol);
      _colliderComponents[body.collider] = bot;
      bots.add(bot);
      add(bot);
    }
  }
}
