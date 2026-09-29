part of 'river_game.dart';

/// The yaw that turns something built nose along +Z to face [x], [z].
Quaternion _facing(double x, double z) =>
    Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), math.atan2(x, z));

Quaternion _roll(double angle) =>
    Quaternion.axisAngle(Vector3(0.0, 0.0, 1.0), angle);

/// The player's jet.
///
/// **Flame moves it; the bridge draws it.** [RiverGame] writes the jet's
/// Flame position every step, and `Object3dComponent`, flowing Flame to the
/// scene, writes that into the holder node. The pivot below the holder
/// turns it up the river and banks it into a turn.
final class JetComponent extends Object3dComponent
    with CollisionCallbacks, HasGameReference<RiverGame> {
  JetComponent({required super.node, required super.scene, required this.pivot})
    : super(
        plane: RiverGame.air,
        direction: SyncDirection.flameToScene,
        size: Vector2(1.5, 1.8),
        anchor: Anchor.center,
      );

  final SceneNode pivot;

  /// Radians rolled about the nose, eased towards what the stick asks for.
  double bank = 0.0;

  /// Up the river is -Z. A fresh one each read: a shared quaternion is one
  /// caller away from being turned in place for every other.
  static Quaternion get _upRiver => _facing(0.0, -1.0);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox());
  }

  /// The fuel depot under the jet right now, if there is one.
  TargetComponent? get depotBelow {
    for (final other in activeCollisions) {
      if (other is TargetComponent &&
          other.plan.kind == TargetKind.depot &&
          !other.down) {
        return other;
      }
    }
    return null;
  }

  /// Eases the roll towards [stick], full right being a bank of about thirty
  /// degrees into the turn.
  void bankTowards(double stick, double dt) {
    bank += (stick * 0.55 - bank) * math.min(1.0, dt * 6.0);
    pivot.setRotation(_upRiver * _roll(bank));
  }

  void show() {
    node.visible = true;
    bank = 0.0;
    pivot.setRotation(_upRiver);
  }

  void hide() => node.visible = false;

  /// Anything but a depot is a crash: a bridge still standing, a craft, a
  /// helicopter's bullet.
  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    super.onCollisionStart(intersectionPoints, other);
    final solid = switch (other) {
      TargetComponent(:final plan, :final down) =>
        !down && plan.kind != TargetKind.depot,
      BridgeComponent(:final down) => !down,
      EnemyShotComponent() => true,
      _ => false,
    };
    if (solid) game.crash(Crash.collision);
  }
}

/// A tanker, a helicopter, an enemy jet or a fuel depot.
///
/// Still until the jet comes within [RiverGame.wakeRange]; then a tanker or
/// a helicopter that moves at all runs from bank to bank across its
/// channel, a helicopter that is a gunner turns after the jet and fires at
/// it, and a jet crosses the whole valley and comes round again.
///
/// **Shot, it goes the way its kind would.** A tanker lists and sinks,
/// trailing smoke. A helicopter spins and drops into the river. A jet and
/// a depot go up at once, and a depot takes whatever is close with it.
/// From the moment it is hit its hitbox is gone: a sinking tanker is
/// scenery, not something to crash into.
final class TargetComponent extends Object3dComponent
    with HasGameReference<RiverGame> {
  TargetComponent({
    required this.plan,
    required super.node,
    required super.scene,
    required this.pivot,
    required (double, double) channel,
    this.rotor,
  }) : heading = plan.heading,
       _limits = (
         math.min(channel.$1 + plan.kind.halfLength, plan.x),
         math.max(channel.$2 - plan.kind.halfLength, plan.x),
       ),
       super(
         plane: switch (plan.kind) {
           TargetKind.helicopter || TargetKind.jet => RiverGame.air,
           TargetKind.tanker || TargetKind.depot => RiverGame.water,
         },
         direction: SyncDirection.flameToScene,
         position: Vector2(plan.x, -plan.distance),
         size: switch (plan.kind) {
           TargetKind.tanker => Vector2(3.4, 1.2),
           TargetKind.helicopter => Vector2(2.4, 1.2),
           TargetKind.jet => Vector2(2.2, 1.0),
           TargetKind.depot => Vector2(1.9, 2.3),
         },
         anchor: Anchor.center,
       ) {
    face();
  }

  /// Seconds between a gunner's shots.
  static const double fireInterval = 1.8;

  /// A gunner fires only at a jet this far ahead of it, and no nearer.
  static const (double, double) fireRange = (7.0, 36.0);

  final TargetPlan plan;
  final SceneNode pivot;

  /// The stand-in helicopter's blades, spun while it flies. Null for every
  /// other target, and left alone once a model has replaced them.
  final SceneNode? rotor;

  int heading;
  bool awake = false;

  /// Hit, and going down the way its kind does.
  bool down = false;

  double _spin = 0.0;
  double _dying = 0.0;
  double _smokeIn = 0.0;
  double _fireIn = fireInterval / 2.0;

  /// Made with the component rather than on load, so a target hit before
  /// Flame has loaded it has a hitbox to take away.
  final RectangleHitbox _hitbox = RectangleHitbox(
    collisionType: CollisionType.passive,
  );

  /// Where the stretch of water it runs across ends, either way: the
  /// channel it was put on, less its own half-length at each end.
  ///
  /// **Handed in, not looked up on load.** A stretch built and dropped in
  /// one step, which a restart does, has its targets loaded by Flame after
  /// they have left the tree, when there is no game to ask for the course.
  final (double, double) _limits;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    if (!down) add(_hitbox);
  }

  /// Turns the pivot to face [heading] across the river.
  void face() => pivot.setRotation(_facing(heading.toDouble(), 0.0));

  /// Takes the hit. False when it was already down, so a shot and a blast
  /// arriving together count once.
  bool hit() {
    if (down) return false;
    down = true;
    _hitbox.removeFromParent();
    return true;
  }

  @override
  void update(double dt) {
    if (down) {
      _goDown(dt);
    } else {
      if (!awake &&
          game.built &&
          plan.distance - game.distance < RiverGame.wakeRange) {
        awake = true;
      }
      if (awake && plan.gunner) _hunt(dt);
      if (awake && plan.speed > 0.0) _move(dt);
      final blades = rotor;
      if (blades != null) {
        _spin += dt * 18.0;
        blades.setRotation(Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), _spin));
      }
    }
    super.update(dt);
  }

  void _move(double dt) {
    position.x += heading * plan.speed * dt;
    if (plan.kind == TargetKind.jet) {
      const edge = riverReach + 8.0;
      if (position.x > edge) position.x = -edge;
      if (position.x < -edge) position.x = edge;
      return;
    }
    final (lo, hi) = _limits;
    if (position.x >= hi && heading > 0 || position.x <= lo && heading < 0) {
      position.x = position.x.clamp(lo, hi);
      heading = -heading;
      face();
    }
  }

  /// A gunner turns to cut across the jet's line, and fires when it has it
  /// in range ahead.
  void _hunt(double dt) {
    if (game.phase != Phase.flying) return;
    final towards = (game.jet.position.x - position.x).sign.toInt();
    if (towards != 0 && towards != heading) {
      heading = towards;
      face();
    }
    _fireIn -= dt;
    final ahead = plan.distance - game.distance;
    if (_fireIn <= 0.0 && ahead > fireRange.$1 && ahead < fireRange.$2) {
      _fireIn = fireInterval;
      game.enemyFire(from: position.clone());
    }
  }

  void _goDown(double dt) {
    _dying += dt;
    _smokeIn -= dt;
    final yaw = _facing(heading.toDouble(), 0.0);
    switch (plan.kind) {
      case TargetKind.tanker:
        // Lists to one side and goes under, smoking as it does.
        pivot
          ..setRotation(yaw * _roll(math.min(0.55, _dying * 0.45)))
          ..setPosition(0.0, -0.45 * _dying * _dying, 0.0);
        if (_smokeIn <= 0.0) {
          _smokeIn = 0.22;
          game.smoke(plane.to3d(position)..y = 0.8);
        }
        if (_dying > 2.4) removeFromParent();
      case TargetKind.helicopter:
        // Spins about its mast and falls, smoke pouring out, until the
        // river takes it.
        final drop = 0.5 * 9.0 * _dying * _dying;
        pivot
          ..setRotation(
            Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), _dying * 11.0) *
                _roll(0.3),
          )
          ..setPosition(0.0, -drop, 0.0);
        if (_smokeIn <= 0.0) {
          _smokeIn = 0.06;
          game.smoke(plane.to3d(position)..y = flightHeight - drop + 0.3);
        }
        if (drop >= flightHeight) {
          game.splash(plane.to3d(position)..y = 0.1);
          removeFromParent();
        }
      case TargetKind.jet:
      case TargetKind.depot:
        removeFromParent();
    }
  }
}

/// The bridge at the end of a stretch. Solid until shot, and on the last
/// bridge of a level, shielded until the level's task is done.
///
/// **Shot, it breaks in the middle.** It is drawn as two halves, each on a
/// pivot at its own bank end; they swing down into the river, and sink.
final class BridgeComponent extends Object3dComponent
    with HasGameReference<RiverGame> {
  BridgeComponent({
    required this.section,
    required this.span,
    required this.left,
    required this.right,
    required this.shield,
    required super.node,
    required super.scene,
    required super.position,
  }) : super(
         plane: RiverGame.water,
         direction: SyncDirection.flameToScene,
         size: Vector2(span, 2.4),
         anchor: Anchor.center,
       );

  /// The index of the section it ends.
  final int section;
  final double span;

  /// The pivots the two halves hang from, at the bank ends.
  final SceneNode left;
  final SceneNode right;

  /// Glowing rails, lit while [RiverGame.shielded] says it cannot fall: a
  /// pilot sees the task is not done before a shot bounces off.
  final SceneNode shield;

  bool down = false;
  double _falling = 0.0;

  /// Made with the component, for the reason [TargetComponent] gives.
  final RectangleHitbox _hitbox = RectangleHitbox(
    collisionType: CollisionType.passive,
  );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    if (!down) add(_hitbox);
  }

  /// Breaks it. False when it was already down.
  bool collapse() {
    if (down) return false;
    down = true;
    _hitbox.removeFromParent();
    return true;
  }

  @override
  void update(double dt) {
    shield.visible = !down && game.shielded(this);
    if (down) {
      _falling += dt;
      final swing = math.min(0.8, _falling * 1.3);
      final sink = math.max(0.0, _falling - 0.7) * 0.9;
      left
        ..setRotation(_roll(-swing))
        ..setPosition(-span / 2.0, deckHeight - sink, 0.0);
      right
        ..setRotation(_roll(swing))
        ..setPosition(span / 2.0, deckHeight - sink, 0.0);
      if (_falling > 3.5) node.visible = false;
    }
    super.update(dt);
  }
}

/// One shot, straight up the river until it hits something or runs out.
final class ShotComponent extends Object3dComponent
    with CollisionCallbacks, HasGameReference<RiverGame> {
  ShotComponent({
    required super.node,
    required super.scene,
    required super.position,
    required this.speed,
  }) : super(
         plane: RiverGame.air,
         direction: SyncDirection.flameToScene,
         // Longer than the rod drawn: at thirty frames a second a shot moves
         // two and a half metres a frame, and a shorter box could step over
         // a tanker without ever overlapping it.
         size: Vector2(0.4, 1.8),
         anchor: Anchor.center,
       );

  final double speed;
  double _life = 0.9;
  bool _spent = false;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox());
  }

  @override
  void update(double dt) {
    position.y -= speed * dt;
    _life -= dt;
    if (_life <= 0.0) _spend();
    super.update(dt);
  }

  void _spend() {
    if (_spent) return;
    _spent = true;
    removeFromParent();
  }

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    super.onCollisionStart(intersectionPoints, other);
    if (_spent) return;
    switch (other) {
      case TargetComponent(down: false):
        game.hitTarget(other);
      case BridgeComponent(down: false):
        game.hitBridge(other, at: position.clone());
      default:
        return;
    }
    _spend();
  }
}

/// A helicopter's bullet: slow enough to see and to dodge, flying at where
/// the jet was when it was fired.
final class EnemyShotComponent extends Object3dComponent
    with CollisionCallbacks {
  EnemyShotComponent({
    required super.node,
    required super.scene,
    required super.position,
    required this.velocity,
  }) : super(
         plane: RiverGame.air,
         direction: SyncDirection.flameToScene,
         size: Vector2.all(0.5),
         anchor: Anchor.center,
       );

  static const double speed = 20.0;

  final Vector2 velocity;
  double _life = 2.5;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox());
  }

  @override
  void update(double dt) {
    position.addScaled(velocity, dt);
    _life -= dt;
    if (_life <= 0.0 && !isRemoving) removeFromParent();
    super.update(dt);
  }

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is JetComponent && !isRemoving) removeFromParent();
  }
}

/// Shards thrown out of a point, falling or rising, shrinking, gone: fire,
/// smoke, spray or sparks, by what it is given.
///
/// A plain Flame [Component] that owns scene nodes and never a Flame
/// position: nothing about a shard is game state.
final class BurstComponent extends Component {
  BurstComponent({
    required Scene scene,
    required DeviceMesh shard,
    required this.material,
    required Vector3 at,
    required int count,
    required double reach,
    this.lift = 3.0,
    this.gravity = 14.0,
    this.lifetime = 0.9,
    this.size = 1.0,
    this.grows = false,
    this.fades = false,
  }) {
    final random = math.Random();
    for (var i = 0; i < count; i++) {
      final node = MeshNode(shard, material, name: 'shard')
        ..setPositionFrom(at)
        ..setUniformScale(size);
      scene.add(node);
      final angle = random.nextDouble() * math.pi * 2.0;
      final out = reach * (0.4 + 0.6 * random.nextDouble());
      _shards.add((
        node: node,
        velocity: Vector3(
          math.cos(angle) * out,
          lift * (0.5 + random.nextDouble()),
          math.sin(angle) * out,
        ),
        spin: Vector3.random(random)..sub(Vector3.all(0.5)),
      ));
    }
  }

  /// This burst's own when [fades]: its glow dims as the shards die.
  final engine.Material material;
  final double lift;
  final double gravity;
  final double lifetime;
  final double size;

  /// Swells as it goes, the way smoke does, rather than only shrinking.
  final bool grows;

  /// Dims [material]'s glow over [lifetime].
  final bool fades;

  final List<({MeshNode node, Vector3 velocity, Vector3 spin})> _shards = [];
  double _age = 0.0;

  @override
  void update(double dt) {
    _age += dt;
    final left = 1.0 - _age / lifetime;
    if (left <= 0.0) {
      removeFromParent();
      return;
    }
    final scale = size * (grows ? (0.6 + 1.4 * _age / lifetime) * left : left);
    for (final shard in _shards) {
      shard.velocity.y -= gravity * dt;
      final at = shard.node.readPosition()..addScaled(shard.velocity, dt);
      shard.node
        ..setPositionFrom(at)
        ..setUniformScale(scale)
        ..setRotationYawPitchRoll(
          shard.spin.x * _age * 20.0,
          shard.spin.y * _age * 20.0,
          shard.spin.z * _age * 20.0,
        );
    }
    if (fades) material.emissiveStrength = 5.0 * left;
  }

  @override
  void onRemove() {
    for (final shard in _shards) {
      shard.node.removeFromParent();
    }
    super.onRemove();
  }
}
