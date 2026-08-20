import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'actions.dart';
import 'blocks.dart';
import 'purse.dart';
import 'spring.dart';
import 'surfaces.dart';

/// How this game's jump feels, which is most of how the game feels.
final class RunnerTuning {
  const RunnerTuning({
    this.jumpSpeed = 9.5,
    this.airJumpSpeed = 8.2,
    this.airJumps = 1,
    this.jumpCut = 0.45,
    this.coyoteTime = 0.12,
    this.dropThroughTime = 0.25,
    this.stompBounce = 7.5,
    this.stompBounceHeld = 11.0,
    this.crouchHeight = 0.45,
    this.crouchSpeed = 2.4,
    this.slideSpeed = 11.0,
    this.slideTime = 0.55,
    this.slideFriction = 6.0,
    this.longJumpUp = 6.0,
    this.longJumpPush = 12.0,
    this.poundSpeed = 26.0,
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

  /// How high a stomp throws the runner back, and how high while holding jump.
  ///
  /// The held figure is above a standing jump's 9.5, so a chain of stomps
  /// climbs — which is the whole reason a player aims for the second enemy
  /// rather than landing beside it.
  final double stompBounce;
  final double stompBounceHeld;

  /// How long a one-way platform stays passable after asking to drop.
  ///
  /// Long enough to fall clear of it: a quarter of a second is about forty
  /// centimetres, and any thickness a level authors is well under that. Too
  /// short and the runner lands back on the platform it just left, which reads
  /// as the input being eaten.
  final double dropThroughTime;

  /// Half the body's height while crouched.
  ///
  /// Half again of the standing 0.9, which is what makes a one-metre gap a
  /// crawlspace rather than a decoration.
  final double crouchHeight;

  /// How fast a crouched runner walks. Slow enough to be a decision.
  final double crouchSpeed;

  /// The speed a slide starts at, whatever the runner was doing.
  ///
  /// Faster than a sprint, or nobody would slide; short-lived, or it would
  /// replace running.
  final double slideSpeed;

  /// How long a slide lasts before it becomes an ordinary crouch.
  final double slideTime;

  /// How quickly a slide bleeds off. Low: a slide that stops in its own length
  /// is a stumble.
  final double slideFriction;

  /// Up and along, for the jump a slide can be cancelled into.
  ///
  /// Deliberately a low arc and a long one: the long jump crosses gaps a normal
  /// jump cannot and reaches ledges a normal jump can, which is what makes it
  /// worth learning rather than strictly better.
  final double longJumpUp;
  final double longJumpPush;

  /// How fast a ground pound drives the runner down.
  ///
  /// Well past terminal velocity for a fall, because the point is that it
  /// arrives *now* and lands hard enough to break something.
  final double poundSpeed;

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
///
/// **It has since cost exactly one line, which is the honest version of that
/// claim.** `MovementTuning.floorSnapLength` keeps a grounded body's feet on
/// the floor they had, and a grounded body whose `velocity.y` somebody else
/// wrote looks precisely like one walking off a stair edge. So every place in
/// here that throws the runner upward also calls
/// `CharacterController.suppressFloorSnap` — still no hook and no subclass,
/// but no longer *nothing*: writing a public field is not by itself a way to
/// state an intention.
final class Runner with KeyHolder
    implements Damageable, Rider, Gatherer, KeyTaker, Launchable {
  Runner({
    required this.body,
    Health? health,
    Purse? purse,
    this.tuning = const RunnerTuning(),
    this.surfaces = const Surfaces.plain(),
  })  : health = health ?? Health(100.0),
        purse = purse ?? Purse() {
    body.collider.userData = this;
    // What this body counts as solid is a policy, and a platformer's policy is
    // that some platforms are floors from above and nothing at all from below.
    // The engine holds the mechanism and this holds the opinion.
    body.solidFilter = _countsAsSolid;
    _standing = body.shape;
    _crouching = CollisionBox(
      Vector3(body.halfExtents.x, tuning.crouchHeight, body.halfExtents.z),
    );
    _ground = body.tuning;
    _land();
  }

  final CharacterController body;
  final RunnerTuning tuning;

  /// What the floors of this game are made of, and what each does.
  ///
  /// Read every step from whatever the feet are on. A game that names no
  /// surfaces gets `MovementTuning` unchanged and pays one map lookup.
  final Surfaces surfaces;

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

  /// How long a one-way platform stays passable after asking to drop through.
  double _dropping = 0.0;

  /// How much of a slide is left, in seconds. Zero when merely crouched.
  double _sliding = 0.0;

  /// Whether the body is currently the short shape.
  bool _crouched = false;

  /// Whether the player has let go of crouch and is waiting for headroom.
  bool _wantsToStand = false;

  /// Whether a ground pound is on its way down.
  bool _pounding = false;

  /// The two shapes this body is ever in, built once in the constructor.
  ///
  /// **Not `late`**, and that is not a style preference: a late `_standing =
  /// body.shape` is read the first time somebody stands up, which is *after*
  /// the first crouch, so it captured the crouched shape and standing up became
  /// a resize to the size it already was. The runner crouched once and stayed
  /// crouched for the rest of the level.
  late final CollisionShape _standing;
  late final CollisionShape _crouching;

  /// Whether the runner is crouched — walking short, or sliding.
  bool get isCrouching => _crouched;

  /// Half the body's height when it is standing, in metres.
  ///
  /// For whatever draws the runner. The body's *current* half height is on the
  /// controller and changes with the crouch; this is the one it came back to,
  /// and a picture that wants to squash by the right amount needs both. Reading
  /// it off `body` is not enough — by the time anything is drawn the shape may
  /// already be the short one.
  double get standingHalfHeight => switch (_standing) {
        CollisionBox(:final Vector3 halfExtents) => halfExtents.y,
        CollisionCapsule(:final double halfHeight, :final double radius) =>
          halfHeight + radius,
        CollisionSphere(:final double radius) => radius,
        // A runner shaped like a ramp is not a thing, and the compiler asking
        // is the sealed hierarchy earning its keep: adding `CollisionWedge`
        // named every switch that had to think about it rather than letting one
        // fall through to a default and answer wrongly for ever.
        CollisionWedge(:final Vector3 halfExtents) => halfExtents.y,
      };

  /// Whether the runner is sliding, which is a crouch with speed in it.
  bool get isSliding => _sliding > 0.0;

  /// Whether a ground pound is in the air on its way down.
  bool get isPounding => _pounding;

  /// True on the step a ground pound hit the floor, for dust and a shake.
  bool poundedThisStep = false;

  /// True on the step a slide started.
  bool slidThisStep = false;

  /// True on the step a long jump left the ground.
  bool longJumpedThisStep = false;

  /// What the runner is climbing, or null.
  Climbable? get climbing => _climbing;
  Climbable? _climbing;
  double _climbCooldown = 0.0;

  /// True on the step the runner took hold of a ladder or a rope.
  bool grabbedThisStep = false;

  /// True on the step the runner touched down after being in the air.
  ///
  /// The simulation had no such moment: the application worked it out by
  /// remembering whether the runner was grounded last frame, which cannot know
  /// *how hard* — and how hard is what decides the dust, the squash and the
  /// volume of the thud.
  bool landedThisStep = false;

  /// How fast the runner was falling when it last landed, in metres a second.
  double landingSpeed = 0.0;

  bool _wasGrounded = false;

  /// The numbers for ordinary ground, kept so a surface can be left again.
  late MovementTuning _ground;

  /// What the feet were on last step, so the tuning is looked up when it
  /// changes rather than on every one of the sixty.
  /// The surface name of the floor underfoot, or null on unnamed ground.
  ///
  /// For whatever wants to make a noise about it: a footstep on ice is not a
  /// footstep on moss, and the level already says which is which on the brush.
  /// The movement numbers are applied from this in `_readSurface`; this is the
  /// same answer, offered rather than kept.
  String? get standingOn => _standingOn;
  String? _standingOn;
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
  bool applyDamage(double amount, {Object? from}) => health.damage(amount);

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
    poundedThisStep = false;
    slidThisStep = false;
    longJumpedThisStep = false;
    landedThisStep = false;
    bouncedThisStep = false;
    _jumpHeld = input.held(GameAction.jump);
    grabbedThisStep = false;

    _climbCooldown = math.max(0.0, _climbCooldown - dt);
    if (_readClimb(input)) {
      _climb(dt, input);
      return;
    }

    _readWish(input, cameraYaw);
    _readSurface();
    _probeWall(dt);
    _tickTimers(dt, input);
    _crouchAndSlide(dt, input);
    _tryMantle();
    _tryJump();
    _cutJumpShort(input);
    _tryDash(input);
    _slideDownWall();

    final sprinting = input.held(GameAction.sprint);
    // Read before the step, because the step is where a landing turns downward
    // speed into zero and the number is gone.
    final falling = math.max(0.0, -body.velocity.y);
    body.step(dt, wishDirection: _wish, sprint: sprinting);
    _readLanding(falling);
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

  /// Whether a contact counts, which for this genre is a question about
  /// one-way platforms and nothing else.
  ///
  /// Three answers, and each is a rule a player can feel:
  ///
  ///  * anything that is not a one-way platform is solid, always;
  ///  * a one-way platform is nothing at all while dropping through it;
  ///  * otherwise it is solid only as a *floor* — a contact whose normal points
  ///    up, met while not rising. Jumping up through it, and running into its
  ///    side in mid-air, both find nothing.
  ///
  /// The third clause is why this is a predicate and not a mask. With a mask
  /// the sides of a one-way platform stay solid, and a player sprinting past
  /// one stops dead on an invisible lip at chest height.
  bool _countsAsSolid(Collider other, Vector3 normal) {
    if (other.layer & PlatformerLayers.oneWay == 0) return true;
    if (_dropping > 0.0) return false;
    return normal.y > 0.5 && body.velocity.y <= 0.0;
  }

  /// Reads what the feet are on and hands the body that surface's numbers.
  ///
  /// The lookup is skipped while the name has not changed, which is almost
  /// always: a runner crosses one floor for seconds at a time.
  void _readSurface() {
    final name = surfaceUnder(body.ground);
    if (name == _standingOn) return;
    _standingOn = name;
    _surfaceTuning = name == null ? _ground : surfaces.tuningFor(name);
    body.tuning = _surfaceTuning;
  }

  /// What the floor alone says, before crouching has its word.
  late MovementTuning _surfaceTuning = body.tuning;

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

  /// Takes hold of a ladder or a rope, and reports whether the runner is on
  /// one.
  ///
  /// An overlap query rather than a listener on the volume, because the answer
  /// has to be true *while* inside rather than on the step of entering: a
  /// climber halfway up a ladder never enters it again.
  bool _readClimb(InputState input) {
    if (_climbCooldown > 0.0) {
      _climbing = null;
      return false;
    }

    _clearance.clear();
    body.world.overlap(
      body.shape,
      body.position,
      _clearance,
      mask: CollisionLayers.trigger,
    );
    Climbable? found;
    for (final other in _clearance) {
      final data = other.userData;
      if (data is Climbable) {
        found = data;
        break;
      }
    }

    if (found == null) {
      _climbing = null;
      return false;
    }
    if (_climbing == null) grabbedThisStep = true;
    _climbing = found;
    return true;
  }

  /// One step of being on a ladder or a rope.
  ///
  /// Gravity, wall probing, dashing and the rest are all skipped: a climber is
  /// somewhere else in the state machine, and the step returns before any of
  /// them. What is left is up, down, and the two ways off.
  ///
  /// The horizontal position is *written from the volume's*, which is the whole
  /// of how a rope carries its passenger: the volume swings, the climber is
  /// wherever it is, and a jump off leaves with the speed it had.
  void _climb(double dt, InputState input) {
    final rope = _climbing!;
    final axis = input.moveAxis;

    if (input.pressed(GameAction.jump)) {
      _letGo();
      body.velocity
        ..x = rope.swingVelocity
        ..y = tuning.jumpSpeed
        ..z = 0.0;
      // The same rule as everywhere else in here: the genre wrote the upward
      // speed, so the genre says the ground was left on purpose. It matters
      // here because a climber holds a ladder without the controller ever
      // stepping, so what the body last recorded may well be the floor it
      // grabbed the ladder from.
      body.suppressFloorSnap();
      _airJumpsLeft = tuning.airJumps;
      jumpedThisStep = true;
      _ownRise = true;
      return;
    }
    if (input.pressed(PlatformerActions.dropThrough)) {
      _letGo();
      return;
    }

    final at = rope.origin;
    final climbed = body.position.y + axis.y * rope.climbSpeed * dt;
    final ceiling = rope.top + body.halfExtents.y;

    body.velocity.setZero();
    body.position.setValues(at.x, math.min(climbed, ceiling), at.z);
    // The controller syncs its collider inside `step`, and this step never
    // called it.
    body.collider.position.setFrom(body.position);
    body.collider.refreshBounds();

    // Over the top: step off onto whatever the ladder was leaning against.
    if (climbed >= ceiling) {
      _letGo();
      _land();
    }
  }

  void _letGo() {
    _climbing = null;
    _climbCooldown = 0.3;
  }

  /// Crouching, sliding, standing back up, and the pound that shares the key.
  ///
  /// One button, and which verb it means is decided by where the runner is and
  /// how fast: in the air it is a ground pound, on a one-way platform it is a
  /// drop through, at speed it is a slide, and otherwise it is a crouch. A
  /// platformer that spends three keys on those four is a platformer with three
  /// keys spare and nothing to bind to them.
  void _crouchAndSlide(double dt, InputState input) {
    final held = input.held(PlatformerActions.dropThrough);
    _sliding = math.max(0.0, _sliding - dt);

    if (input.pressed(PlatformerActions.dropThrough) && !body.isGrounded) {
      _startPound();
      return;
    }

    // The same press already went into a one-way platform: do not also crouch
    // on the way through it.
    if (held && body.isGrounded && !_crouched && _dropping <= 0.0) {
      final speed = math.sqrt(
        body.velocity.x * body.velocity.x + body.velocity.z * body.velocity.z,
      );
      if (body.tryResize(_crouching)) {
        _crouched = true;
        _wantsToStand = false;
        // Fast enough to be worth a slide, or it is a crouch that happened to
        // be moving. The threshold is a walk, so a sprint always slides and a
        // shuffle never does.
        if (speed > body.tuning.walkSpeed * 0.8) {
          _sliding = tuning.slideTime;
          slidThisStep = true;
          _shoveInto(tuning.slideSpeed);
        }
      }
    }

    if (!held && _crouched) _wantsToStand = true;

    if (_wantsToStand && body.tryResize(_standing)) {
      _crouched = false;
      _wantsToStand = false;
      _sliding = 0.0;
    }

    _applyCrouchTuning();
  }

  /// Sets the velocity to [speed] along the way the runner is facing.
  void _shoveInto(double speed) {
    final along = _wish.length2 > 1e-6 ? _wish.normalized() : _facingVector();
    body.velocity
      ..x = along.x * speed
      ..z = along.z * speed;
  }

  Vector3 _facingVector() =>
      Vector3(math.sin(yaw), 0.0, math.cos(yaw));

  /// A crouched runner is a slow one, and a sliding one keeps what it has.
  ///
  /// Derived from whatever the floor said rather than replacing it, which is
  /// what `MovementTuning.copyWith` is for: ice one is crouching on is still
  /// ice.
  void _applyCrouchTuning() {
    final floor = _surfaceTuning;
    if (!_crouched) {
      body.tuning = floor;
      return;
    }
    body.tuning = floor.copyWith(
      walkSpeed: tuning.crouchSpeed,
      sprintSpeed: tuning.crouchSpeed,
      // A slide keeps its speed; a crouch-walk does not slither.
      groundFriction: _sliding > 0.0 ? tuning.slideFriction : floor.groundFriction,
      groundAcceleration:
          _sliding > 0.0 ? floor.groundAcceleration * 0.2 : floor.groundAcceleration,
    );
  }

  /// Drives the runner at the floor. The landing is read in [_land].
  void _startPound() {
    if (_pounding) return;
    _pounding = true;
    _sliding = 0.0;
    body.velocity
      ..x = 0.0
      ..z = 0.0
      ..y = -tuning.poundSpeed;
  }

  /// The hop off something the runner has just landed on.
  ///
  /// Fixed, plus a bonus for holding the jump — the arrangement every
  /// platformer since the first one uses, and the reason is that both halves
  /// are needed: a fixed bounce is predictable enough to chain, and the held
  /// bonus is what makes chaining *worth* aiming for. A bounce scaled by how
  /// fast the runner was falling would reward height instead of timing.
  void bounce() {
    body.velocity.y = _jumpHeld ? tuning.stompBounceHeld : tuning.stompBounce;
    _ownRise = false;
    // Landing on a head is landing, so the body is usually *grounded* at this
    // moment and a floor snap would happily keep it there. Saying so is the
    // only way the controller can tell this apart from a stair edge.
    body.suppressFloorSnap();
    _airJumpsLeft = tuning.airJumps;
    _coyote = 0.0;
    bouncedThisStep = true;
  }

  /// True on the step the runner bounced off something it landed on.
  bool bouncedThisStep = false;

  /// Whether the jump button was down as of this step's input.
  bool _jumpHeld = false;

  /// Whether the rise the runner is in is one they asked for.
  ///
  /// **A held jump released mid-flight used to cut a spring in half.**
  /// `_cutJumpShort` fired on any upward speed, and a spring is documented as
  /// "a promise about height — the level author placed it to reach a particular
  /// ledge". Jump is held almost constantly in a platformer, so running onto a
  /// pad with it down and letting go in the air multiplied a 15 m/s throw by
  /// 0.45 and fell short of the ledge the level was built around. The held
  /// stomp bounce had it too.
  ///
  /// So the cut applies to a jump and to nothing else: set by every way of
  /// jumping, cleared by every way of being thrown.
  bool _ownRise = false;

  /// Asks to fall through the one-way platform underfoot.
  ///
  /// A window rather than a flag: the platform has to stay passable for long
  /// enough to get clear of it, and a single step is not — the body falls three
  /// centimetres in one and would land straight back on it.
  void dropThrough() {
    if (!body.isGrounded) return;
    final under = body.ground;
    if (under == null || under.layer & PlatformerLayers.oneWay == 0) return;
    _dropping = tuning.dropThroughTime;
  }

  void _tickTimers(double dt, InputState input) {
    _dropping = math.max(0.0, _dropping - dt);
    if (input.pressed(PlatformerActions.dropThrough)) dropThrough();
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
      // **Through the same filter the body moves by.** Without it this sweep
      // sees the side of a one-way platform as a wall — so a runner falling
      // past its edge slows to a wall slide and can jump off nothing. That is
      // the invisible lip `_countsAsSolid` was written to abolish, arrived at
      // from the other direction: the body obeyed the rule and the probe asking
      // about the body did not.
      if (!body.world.sweep(body.shape, body.position, _probe, _hit,
          ignore: body.collider, allow: _countsAsSolid)) {
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
    //
    // **Deliberately not through `_countsAsSolid`**, unlike the wall probe
    // above. That filter answers "does this stop me moving", and part of its
    // answer is `velocity.y <= 0` — which is false at exactly the moment a
    // mantle happens, on the way up. This sweep asks a different question:
    // "is there a surface here I could stand on", and the top of a one-way
    // platform is one. Passing the movement filter would make every one-way
    // ledge unmantleable while rising, which is every time.
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
      if (_sliding > 0.0) {
        // Out of a slide: low and long. The horizontal is *set* along the way
        // the runner is going, so a long jump aimed anywhere but forwards is a
        // long jump that goes forwards — which is what makes it a commitment
        // rather than a better jump.
        _shoveInto(tuning.longJumpPush);
        body.velocity.y = tuning.longJumpUp;
        _sliding = 0.0;
        longJumpedThisStep = true;
      } else {
        body.velocity.y = tuning.jumpSpeed;
      }
      // Every jump this genre owns is a departure the controller did not
      // decide, and its floor snap must not treat one as a stair edge. Both
      // branches, because a long jump leaves at six metres a second and is
      // just as much a jump.
      body.suppressFloorSnap();
      _coyote = 0.0;
    } else if (_wallCoyote > 0.0 && _wallAway.length2 > 1e-6) {
      // Up and away from the wall, and the horizontal is *set* rather than
      // added: a runner who was moving into the wall would otherwise leave with
      // almost nothing sideways and slide straight back onto it.
      body.velocity
        ..x = _wallAway.x * tuning.wallJumpPush
        ..y = tuning.wallJumpUp
        ..z = _wallAway.z * tuning.wallJumpPush;
      // Said for the same reason as the branch above, and honestly it
      // can change nothing: this branch is only reachable while airborne —
      // `body.isGrounded || _coyote > 0.0` is tested first — and a body that
      // is already airborne is never snapped. It is here so that "the genre
      // wrote velocity.y to leave the ground" has one spelling rather than
      // three sites and an exception.
      body.suppressFloorSnap();
      _wallCoyote = 0.0;
      _onWall = false;
      // The air jump comes back. Two walls facing each other are meant to be
      // climbable; one wall and a spare jump is the same move twice.
      _airJumpsLeft = tuning.airJumps;
      _buffer = 0.0;
      jumpedThisStep = true;
      _ownRise = true;
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
    _ownRise = true;
  }

  void _cutJumpShort(InputState input) {
    if (!input.released(GameAction.jump)) return;
    if (body.velocity.y <= 0.0) return;
    // Only a rise the player asked for — see [_ownRise]. Cutting a spring is
    // cutting the level's own arithmetic.
    if (!_ownRise) return;
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
    // The other way out of a pound, and it used to leave the flag up: the
    // landing at the end of the dash was then reported as a pound the player
    // did not make. Zeroing the downward speed already ends it in every sense
    // but the one the rest of this file reads.
    _pounding = false;
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
    // A slide is its own speed, exactly as a dash is: this is the thing that
    // hauls anything faster than a walk back down to walking pace, and running
    // it on a slide clamps eleven metres a second to a crouch's two and a half
    // in a handful of steps. The slide then travelled about as far as standing
    // still, which is what the test caught.
    if (_sliding > 0.0) return;
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
    yaw = turnedTowards(yaw, math.atan2(_wish.x, _wish.z), tuning.turnRate * dt);
  }

  /// Thrown by a spring.
  ///
  /// The jump budget comes back and the buffer is cleared: a launch is a fresh
  /// start in the air, and a jump the player pressed a moment before landing on
  /// the pad must not fire at the top of the throw.
  @override
  void launch(double speed) {
    body.velocity.y = speed;
    _ownRise = false;
    // A pad is walked over, so the feet are on the floor under it when this
    // fires: without this line a body with a floor snap set would be entitled
    // to keep that floor, and a launch that meets anything overhead — a
    // ceiling, a ledge, a shaft — is put straight back on the pad, which fires
    // again, for ever.
    body.suppressFloorSnap();
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
    // **A pound ends when the runner is out of it, and dying is out of it.**
    // This was cleared only by landing, and dying mid-pound is the ordinary way
    // a pound kills you — into a hazard, or past the kill plane. So it survived
    // the respawn, and the first *ordinary* landing afterwards reported a
    // pound: the slam, the shake, and whatever `Breakable` was under the
    // checkpoint shattered by a landing nobody aimed.
    _pounding = false;
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
  /// Notices the moment the feet touch down, and how hard.
  void _readLanding(double fallingAt) {
    final grounded = body.isGrounded;
    if (grounded && !_wasGrounded) {
      landedThisStep = true;
      landingSpeed = fallingAt;
      if (_pounding) {
        _pounding = false;
        poundedThisStep = true;
      }
    }
    _wasGrounded = grounded;
  }

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
    yaw = from.number('yaw');
    _coyote = from.number('coyote');
    _buffer = from.number('buffer');
    _airJumpsLeft = from.number('airJumps').round();
    _dashCooldown = from.number('dashCooldown');
    _wallCoyote = from.number('wallCoyote');
    from.vectorInto('wallAway', _wallAway);
  }
}
