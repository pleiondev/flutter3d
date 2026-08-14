import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'actions.dart';
import 'purse.dart';

/// How this game's jump feels, which is most of how the game feels.
final class RunnerTuning {
  const RunnerTuning({
    this.jumpSpeed = 9.5,
    this.airJumpSpeed = 8.2,
    this.airJumps = 1,
    this.jumpCut = 0.45,
    this.coyoteTime = 0.12,
    this.jumpBufferTime = 0.12,
    this.dashSpeed = 18.0,
    this.dashCooldown = 0.55,
    this.turnRate = 16.0,
  });

  final double jumpSpeed;

  /// Slightly weaker than the first, so a double jump reads as a recovery
  /// rather than as a second staircase.
  final double airJumpSpeed;

  final int airJumps;

  /// What is left of upward speed when the button comes up early.
  ///
  /// This is variable jump height, and it is the single control that separates
  /// a platformer from a shooter that happens to have gaps in the floor: the
  /// height of every jump has to be a decision the player makes, not one the
  /// tuning made for them.
  final double jumpCut;

  /// How long after walking off a ledge a jump still counts.
  final double coyoteTime;

  /// How long before landing a jump can be asked for and still happen.
  final double jumpBufferTime;

  final double dashSpeed;
  final double dashCooldown;

  /// How fast the runner turns to face where it is going, in radians a second.
  final double turnRate;
}

/// The player: a body that runs, jumps twice, dashes, and carries a purse.
///
/// ## It owns its jump, and the controller does not mind
///
/// [CharacterController] has a jump — with coyote time and a buffer — and this
/// never calls it. Not because the controller's is wrong, but because its
/// policy is one jump from the ground and a platformer's is two with a
/// variable height, and a policy is exactly the kind of thing a genre should be
/// allowed to hold.
///
/// **What made that possible without touching `flutter3d_physics`** is worth
/// writing down, because it was the open question when this package started:
/// `velocity` is public, gravity leaves a positive `velocity.y` alone (its
/// stick-to-the-floor bias only applies while falling), and the ground probe
/// treats anything moving up as airborne. So setting `velocity.y` from out here
/// behaves exactly like the controller's own jump, and the controller needed no
/// hook, no callback and no subclass.
final class Runner implements Damageable, Rider, Gatherer {
  Runner({
    required this.body,
    Health? health,
    Purse? purse,
    this.tuning = const RunnerTuning(),
  })  : health = health ?? Health(100.0),
        purse = purse ?? Purse() {
    body.collider.userData = this;
    _land();
  }

  final CharacterController body;
  final RunnerTuning tuning;
  final Health health;

  @override
  final Purse purse;

  /// Which way it is facing, in radians. Follows movement rather than the
  /// camera: nobody in a third-person game steers with their shoulders.
  double yaw = 0.0;

  double _coyote = 0.0;
  double _buffer = 0.0;
  int _airJumpsLeft = 0;
  double _dashCooldown = 0.0;

  /// True on the step a dash started, for a sound or a puff of dust.
  bool dashedThisStep = false;

  /// True on the step a jump left the ground, and again on an air jump.
  bool jumpedThisStep = false;

  bool get isGrounded => body.isGrounded;

  /// How much of the dash is still to cool down, in seconds.
  double get dashCooldown => _dashCooldown;

  int get airJumpsLeft => _airJumpsLeft;

  Vector3 get position => body.position;

  @override
  Collider? get carriedBy => body.groundBody;

  @override
  bool applyDamage(double amount) => health.damage(amount);

  final Vector3 _wish = Vector3.zero();

  /// One simulation step.
  ///
  /// [cameraYaw] is where the camera is looking, because in a third-person game
  /// "forward" means away from the camera. The simulation holds no camera — see
  /// the game layer's README on why — so the number arrives as an argument, and
  /// a headless test passes zero and gets world axes.
  void step(double dt, InputState input, {double cameraYaw = 0.0}) {
    dashedThisStep = false;
    jumpedThisStep = false;

    _readWish(input, cameraYaw);
    _tickTimers(dt, input);
    _tryJump();
    _cutJumpShort(input);
    _tryDash(input);

    body.step(dt, wishDirection: _wish, sprint: input.held(GameAction.sprint));
    _face(dt);
  }

  void _readWish(InputState input, double cameraYaw) {
    final axis = input.moveAxis;
    // The stick's y is forward, which in world terms is where the camera looks.
    final sin = math.sin(cameraYaw);
    final cos = math.cos(cameraYaw);
    _wish.setValues(
      axis.x * cos + axis.y * sin,
      0.0,
      axis.y * cos - axis.x * sin,
    );
  }

  void _tickTimers(double dt, InputState input) {
    if (body.isGrounded) {
      _coyote = tuning.coyoteTime;
      _airJumpsLeft = tuning.airJumps;
    } else {
      _coyote = math.max(0.0, _coyote - dt);
    }

    _buffer = input.pressed(GameAction.jump)
        ? tuning.jumpBufferTime
        : math.max(0.0, _buffer - dt);

    _dashCooldown = math.max(0.0, _dashCooldown - dt);
  }

  void _tryJump() {
    if (_buffer <= 0.0) return;

    if (body.isGrounded || _coyote > 0.0) {
      body.velocity.y = tuning.jumpSpeed;
      _coyote = 0.0;
    } else if (_airJumpsLeft > 0) {
      // The second jump replaces downward speed rather than adding to it, or a
      // jump taken late in a fall does almost nothing and reads as a bug.
      body.velocity.y = tuning.airJumpSpeed;
      _airJumpsLeft -= 1;
    } else {
      return;
    }

    _buffer = 0.0;
    jumpedThisStep = true;
  }

  void _cutJumpShort(InputState input) {
    if (!input.released(GameAction.jump)) return;
    if (body.velocity.y <= 0.0) return;
    body.velocity.y *= tuning.jumpCut;
  }

  void _tryDash(InputState input) {
    if (!input.pressed(PlatformerActions.dash)) return;
    if (_dashCooldown > 0.0) return;

    // Where it is facing when standing still, where it is asking to go
    // otherwise. A dash that refuses to happen because the stick is centred is
    // a dash that feels broken at exactly the moment it is needed.
    var x = _wish.x;
    var z = _wish.z;
    if (x == 0.0 && z == 0.0) {
      x = math.sin(yaw);
      z = math.cos(yaw);
    }
    final length = math.sqrt(x * x + z * z);
    if (length == 0.0) return;

    body.velocity
      ..x = x / length * tuning.dashSpeed
      ..z = z / length * tuning.dashSpeed
      // A flat dash, so an air dash buys distance rather than height and the
      // ground friction is what ends it.
      ..y = 0.0;
    _dashCooldown = tuning.dashCooldown;
    dashedThisStep = true;
  }

  void _face(double dt) {
    if (_wish.x == 0.0 && _wish.z == 0.0) return;
    final wanted = math.atan2(_wish.x, _wish.z);
    var difference = wanted - yaw;
    while (difference > math.pi) {
      difference -= 2 * math.pi;
    }
    while (difference < -math.pi) {
      difference += 2 * math.pi;
    }
    final step = tuning.turnRate * dt;
    yaw += difference.abs() <= step ? difference : step * difference.sign;
  }

  /// Puts it back at [at], upright, still and unhurt.
  void reviveAt(Vector3 at) {
    body
      ..teleport(at)
      ..velocity.setZero();
    health.restore(<String, Object?>{'current': health.maximum, 'armour': 0.0});
    _buffer = 0.0;
    _dashCooldown = 0.0;
    _land();
  }

  /// Grants the jump budget as though the feet had just touched down.
  ///
  /// **Called at construction and after a revival, and it is not politeness.**
  /// [CharacterController.isGrounded] answers for the last step that ran, and
  /// after a spawn or a teleport no step has run yet — so it says *airborne*
  /// about a runner standing on a checkpoint. Without this, the first press
  /// after coming back is spent as a double jump, which is the kind of thing a
  /// player reports as "it ate my jump" and nobody can reproduce.
  ///
  /// Coyote time is the right shape for it: being placed somewhere counts as
  /// having just been on the ground, and it expires on its own if the placing
  /// was in mid-air.
  void _land() {
    _coyote = tuning.coyoteTime;
    _airJumpsLeft = tuning.airJumps;
  }

  Map<String, Object?> save() => <String, Object?>{
        'body': body.save(),
        'health': health.save(),
        'purse': purse.save(),
        'yaw': yaw,
        // The four that are invisible for exactly one step and then wrong, the
        // same argument the controller's own save makes about its pair.
        'coyote': _coyote,
        'buffer': _buffer,
        'airJumps': _airJumpsLeft,
        'dashCooldown': _dashCooldown,
      };

  void restore(Map<String, Object?> from) {
    final saved = from['body'];
    if (saved is Map<String, Object?>) body.restore(saved);
    final vitality = from['health'];
    if (vitality is Map<String, Object?>) health.restore(vitality);
    final held = from['purse'];
    if (held is Map<String, Object?>) purse.restore(held);
    yaw = _number(from['yaw']);
    _coyote = _number(from['coyote']);
    _buffer = _number(from['buffer']);
    _airJumpsLeft = _number(from['airJumps']).round();
    _dashCooldown = _number(from['dashCooldown']);
  }

  static double _number(Object? value) => value is num ? value.toDouble() : 0.0;
}
