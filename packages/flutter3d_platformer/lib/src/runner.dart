import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'actions.dart';
import 'purse.dart';
import 'spring.dart';

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
    this.dashDrag = 40.0,
    this.turnRate = 16.0,
    this.wallProbe = 0.14,
    this.wallSlideSpeed = 3.2,
    this.wallJumpUp = 9.0,
    this.wallJumpPush = 7.5,
    this.wallCoyoteTime = 0.12,
    this.mantleLow = 0.35,
    this.mantleHigh = 1.5,
    this.mantleReach = 0.45,
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

  /// How fast speed above walking pace bleeds off, in m/s².
  ///
  /// **Without this a dash never ends.** The character controller accelerates
  /// towards the speed you asked for and applies friction only when you ask for
  /// nothing — so a runner who dashes and keeps holding forward keeps the whole
  /// eighteen metres a second for ever, and the dash stops being a move and
  /// becomes a new walking speed. A test found that; playing it had not.
  final double dashDrag;

  /// How fast the runner turns to face where it is going, in radians a second.
  final double turnRate;

  /// How far sideways to look for a wall, in metres.
  ///
  /// Small: it is the difference between "touching a wall" and "near one", and
  /// a generous figure here makes a runner stick to walls they are not on.
  final double wallProbe;

  /// The fastest a runner slides down a wall they are holding.
  ///
  /// Not zero. A wall you can rest on for ever is a floor stood on its end, and
  /// the whole point of the move is that it buys time rather than granting it.
  final double wallSlideSpeed;

  final double wallJumpUp;

  /// How hard a wall jump throws the runner away from the wall.
  ///
  /// Away is not optional. A wall jump that only goes up lets a player climb
  /// one wall for ever by holding into it, which turns a chimney into a ladder
  /// and every level's ceiling into a suggestion.
  final double wallJumpPush;

  /// How long after leaving a wall a wall jump still counts. Coyote time again,
  /// for the same reason: the player pressed jump when they were on the wall.
  final double wallCoyoteTime;

  /// The shortest ledge worth pulling up onto.
  ///
  /// Below this the character controller's own step-up already handles it, and
  /// mantling a kerb looks like a stumble.
  final double mantleLow;

  /// The tallest ledge the runner can pull up onto.
  ///
  /// Deliberately under a single jump's 1.88 m: a mantle is for the ledge you
  /// *just* missed, and one that beat a jump outright would make jumping the
  /// slower way up.
  final double mantleHigh;

  /// How far past the wall to look for the ledge's floor.
  final double mantleReach;
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
final class Runner with KeyHolder
    implements Damageable, Rider, Gatherer, KeyTaker, Launchable {
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

  @override
  /// The keys this runner is carrying.
  ///
  /// A locked `Door` and a keyed `Exit` ask the body in front of them what it
  /// holds, and until this line existed a platformer's answer was "nothing" —
  /// so every keyed door in the engine was unopenable in this genre and nobody
  /// had noticed, because no level had tried one.
  final KeyRing keyRing = KeyRing();

  @override
  Set<String> get keys => keyRing.keys;

  /// Which way it is facing, in radians. Follows movement rather than the
  /// camera: nobody in a third-person game steers with their shoulders.
  double yaw = 0.0;

  double _coyote = 0.0;
  double _buffer = 0.0;
  double _wallCoyote = 0.0;
  final Vector3 _wallAway = Vector3.zero();
  bool _onWall = false;
  int _airJumpsLeft = 0;
  double _dashCooldown = 0.0;

  /// True on the step a dash started, for a sound or a puff of dust.
  bool dashedThisStep = false;

  /// True on the step a jump left the ground, and again on an air jump.
  bool jumpedThisStep = false;

  /// True on the step a wall jump happened, for a sound and a puff of dust.
  bool wallJumpedThisStep = false;

  /// True on the step the runner pulled itself onto a ledge.
  bool mantledThisStep = false;

  /// Whether the runner is against a wall in the air, sliding down it.
  bool get isOnWall => _onWall;

  /// Which way the wall pushes, when there is one. Zero otherwise.
  Vector3 get wallAway => _wallAway;

  bool get isGrounded => body.isGrounded;

  /// How much of the dash is still to cool down, in seconds.
  double get dashCooldown => _dashCooldown;

  int get airJumpsLeft => _airJumpsLeft;

  Vector3 get position => body.position;

  @override
  Collider? get carriedBy => body.groundBody;

  @override
  bool applyDamage(double amount) => health.damage(amount);

  static final List<Vector3> _sides = <Vector3>[
    Vector3(1.0, 0.0, 0.0),
    Vector3(-1.0, 0.0, 0.0),
    Vector3(0.0, 0.0, 1.0),
    Vector3(0.0, 0.0, -1.0),
  ];

  final Vector3 _wish = Vector3.zero();
  final Vector3 _shove = Vector3.zero();
  final Vector3 _probe = Vector3.zero();
  final Vector3 _mantleAt = Vector3.zero();
  final SweepHit _hit = SweepHit();
  final List<Collider> _clearance = <Collider>[];

  /// What this runner is trying to walk into, for pushing things.
  ///
  /// **Not `body.velocity`, and the difference is the whole reason this
  /// exists.** A character controller slides: when it is stopped by something,
  /// the component of its velocity going into that something is projected away
  /// to zero. So a runner pressed against a crate reports no motion towards it
  /// at all, and a push driven by velocity pushes with nothing — only a glancing
  /// blow, which happens to keep some sideways speed, would ever move anything.
  ///
  /// Intent survives being blocked. This is the direction asked for, at the
  /// speed asked for, and it is zero when the runner is airborne, because
  /// shoving a crate while falling past it is not a thing a platformer does.
  Vector3 get shove => _shove;

  /// One simulation step.
  ///
  /// [cameraYaw] is where the camera is looking, because in a third-person game
  /// "forward" means away from the camera. The simulation holds no camera — see
  /// the game layer's README on why — so the number arrives as an argument, and
  /// a headless test passes zero and gets world axes.
  void step(double dt, InputState input, {double cameraYaw = 0.0}) {
    dashedThisStep = false;
    jumpedThisStep = false;
    wallJumpedThisStep = false;
    mantledThisStep = false;

    _readWish(input, cameraYaw);
    _probeWall(dt);
    _tickTimers(dt, input);
    _tryMantle();
    _tryJump();
    _cutJumpShort(input);
    _tryDash(input);
    _slideDownWall();

    final sprinting = input.held(GameAction.sprint);
    body.step(dt, wishDirection: _wish, sprint: sprinting);
    _face(dt);

    final asked = sprinting ? body.tuning.sprintSpeed : body.tuning.walkSpeed;
    if (body.isGrounded) {
      _shove
        ..setFrom(_wish)
        ..scale(asked);
    } else {
      _shove.setZero();
    }
    _bleedOffDash(dt, asked);
  }

  void _readWish(InputState input, double cameraYaw) {
    final axis = input.moveAxis;
    final sin = math.sin(cameraYaw);
    final cos = math.cos(cameraYaw);

    // Forward is where the camera looks: `F = (sin, 0, cos)`.
    //
    // Right is the screen's right, which is `cross(F, up)` and therefore
    // `(-cos, 0, sin)` — **not** `(cos, 0, -sin)`, which is what this said
    // until somebody played it and reported that A and D were the wrong way
    // round. The test that was supposed to cover this only ever held forward,
    // so it agreed with both signs; `strafing goes to the camera's right` is
    // the one that does not.
    _wish.setValues(
      axis.y * sin - axis.x * cos,
      0.0,
      axis.y * cos + axis.x * sin,
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

  /// Four short sweeps, and the nearest vertical thing wins.
  ///
  /// Sideways rather than along the wish, because a runner who has stopped
  /// pressing into the wall is still on it — and a probe that follows the stick
  /// makes the wall vanish the moment the player centres it, which reads as the
  /// game dropping them.
  void _probeWall(double dt) {
    _onWall = false;
    if (body.isGrounded) {
      _wallCoyote = 0.0;
      _wallAway.setZero();
      return;
    }

    var best = double.infinity;
    for (final side in _sides) {
      _probe
        ..setFrom(side)
        ..scale(tuning.wallProbe);
      if (!body.world.sweep(body.shape, body.position, _probe, _hit,
          ignore: body.collider)) {
        continue;
      }
      // A floor or a ceiling is not a wall, however close it is.
      if (_hit.normal.y.abs() > 0.5) continue;
      if (_hit.fraction >= best) continue;
      best = _hit.fraction;
      _wallAway.setFrom(_hit.normal);
      _onWall = true;
    }

    if (_onWall) {
      _wallCoyote = tuning.wallCoyoteTime;
    } else {
      _wallCoyote = math.max(0.0, _wallCoyote - dt);
      if (_wallCoyote <= 0.0) _wallAway.setZero();
    }
  }

  /// Caps the fall while a wall is being held.
  ///
  /// After the jump rather than before, so a wall jump leaves at its own speed
  /// and is not clamped on the step it happens.
  void _slideDownWall() {
    if (!_onWall || body.isGrounded) return;
    if (body.velocity.y < -tuning.wallSlideSpeed) {
      body.velocity.y = -tuning.wallSlideSpeed;
    }
  }

  /// Pulls the runner onto a ledge it is hanging under.
  ///
  /// Three questions, in the order that makes the cheap one first: is there a
  /// wall, is there a floor just past it at a height worth climbing, and is
  /// there room to stand there. Only the third needs the runner's whole shape,
  /// and skipping it is how a mantle puts somebody inside a ceiling.
  void _tryMantle() {
    if (body.isGrounded || !_onWall) return;
    if (body.velocity.y > 0.5) return;

    // Only if the player is reaching for it. Without this, walking off the end
    // of a platform grabs the edge you just left and pulls you back — the game
    // refusing to let you fall, which is not the same as being forgiving. The
    // test that walks into a pit is what noticed.
    if (_wish.x * -_wallAway.x + _wish.z * -_wallAway.z <= 0.1) return;

    final half = body.halfExtents;
    final feet = body.position.y - half.y;

    // A point just beyond the wall, at the height a ledge would be.
    _mantleAt
      ..setFrom(body.position)
      ..x -= _wallAway.x * (half.x + tuning.mantleReach)
      ..z -= _wallAway.z * (half.z + tuning.mantleReach)
      ..y = feet + tuning.mantleHigh + half.y;

    // Straight down from above the tallest ledge worth taking.
    _probe.setValues(0.0, -(tuning.mantleHigh - tuning.mantleLow), 0.0);
    if (!body.world.sweep(body.shape, _mantleAt, _probe, _hit,
        ignore: body.collider)) {
      return;
    }
    if (_hit.normal.y < 0.5) return;

    _mantleAt.y += _probe.y * _hit.fraction;

    // Room to stand: the sweep above stopped *on* the surface, so anything
    // still overlapping there is a ceiling.
    _clearance.clear();
    body.world.overlap(body.shape, _mantleAt, _clearance,
        ignore: body.collider, includeTriggers: false);
    if (_clearance.isNotEmpty) return;

    body
      ..teleport(_mantleAt)
      ..velocity.setZero();
    _land();
    mantledThisStep = true;
  }

  void _tryJump() {
    if (_buffer <= 0.0) return;

    if (body.isGrounded || _coyote > 0.0) {
      body.velocity.y = tuning.jumpSpeed;
      _coyote = 0.0;
    } else if (_wallCoyote > 0.0 && _wallAway.length2 > 1e-6) {
      // Up and away from the wall, and the horizontal is *set* rather than
      // added: a runner who was moving into the wall would otherwise leave with
      // almost nothing sideways and slide straight back onto it.
      body.velocity
        ..x = _wallAway.x * tuning.wallJumpPush
        ..y = tuning.wallJumpUp
        ..z = _wallAway.z * tuning.wallJumpPush;
      _wallCoyote = 0.0;
      _onWall = false;
      // The air jump comes back. Two walls facing each other are meant to be
      // climbable; one wall and a spare jump is the same move twice.
      _airJumpsLeft = tuning.airJumps;
      _buffer = 0.0;
      jumpedThisStep = true;
      wallJumpedThisStep = true;
      return;
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

  /// Brings speed above walking pace back down after a dash.
  ///
  /// Only downwards, and only above what was asked for, so it cannot fight the
  /// controller's own acceleration or slow a runner a spring has launched — a
  /// pad that throws you across a gap must not be quietly cancelled by this.
  void _bleedOffDash(double dt, double asked) {
    if (!body.isGrounded) return;
    final v = body.velocity;
    final speed = math.sqrt(v.x * v.x + v.z * v.z);
    if (speed <= asked || speed < 1e-4) return;
    final slowed = math.max(asked, speed - tuning.dashDrag * dt);
    final scale = slowed / speed;
    v
      ..x *= scale
      ..z *= scale;
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

  /// Thrown by a spring.
  ///
  /// The jump budget comes back and the buffer is cleared: a launch is a fresh
  /// start in the air, and a jump the player pressed a moment before landing on
  /// the pad must not fire at the top of the throw.
  @override
  void launch(double speed) {
    body.velocity.y = speed;
    _buffer = 0.0;
    _coyote = 0.0;
    _airJumpsLeft = tuning.airJumps;
  }

  /// Puts it back with its feet on [feet], upright, still and unhurt.
  ///
  /// **Feet, not the body's middle**, and the difference is a bug that took a
  /// player about four seconds to find. A level document says where a spawn or
  /// a checkpoint is the way a person would point at the floor; a body is a box
  /// about its centre. Teleporting the centre to the authored point buries the
  /// runner half a body deep in the floor, from where it slides, falls, dies
  /// and comes back to the same place — a death loop with no way out of it.
  void reviveAt(Vector3 feet) {
    body
      ..teleport(Vector3(feet.x, feet.y + body.halfExtents.y, feet.z))
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
        'keys': keyRing.save(),
        'yaw': yaw,
        // The four that are invisible for exactly one step and then wrong, the
        // same argument the controller's own save makes about its pair.
        'coyote': _coyote,
        'buffer': _buffer,
        'airJumps': _airJumpsLeft,
        'dashCooldown': _dashCooldown,
        'wallCoyote': _wallCoyote,
        'wallAway': <double>[_wallAway.x, _wallAway.y, _wallAway.z],
      };

  void restore(Map<String, Object?> from) {
    final saved = from['body'];
    if (saved is Map<String, Object?>) body.restore(saved);
    final vitality = from['health'];
    if (vitality is Map<String, Object?>) health.restore(vitality);
    final held = from['purse'];
    if (held is Map<String, Object?>) purse.restore(held);
    keyRing.restore(from['keys']);
    yaw = _number(from['yaw']);
    _coyote = _number(from['coyote']);
    _buffer = _number(from['buffer']);
    _airJumpsLeft = _number(from['airJumps']).round();
    _dashCooldown = _number(from['dashCooldown']);
    _wallCoyote = _number(from['wallCoyote']);
    final away = from['wallAway'];
    if (away is List && away.length >= 3) {
      _wallAway.setValues(
        _number(away[0]),
        _number(away[1]),
        _number(away[2]),
      );
    }
  }

  static double _number(Object? value) => value is num ? value.toDouble() : 0.0;
}
