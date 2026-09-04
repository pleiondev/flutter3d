import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'collider.dart';
import 'collision_shape.dart';
import 'collision_world.dart';
import 'movement_tuning.dart';
import 'snapshot.dart';
import 'tolerances.dart';

export 'movement_tuning.dart';

/// Moves a box through a [CollisionWorld] the way a player expects.
///
/// Deliberately not a rigid body. Nothing pushes the player, the player has no
/// angular momentum, and the response to a wall is to slide along it rather
/// than to bounce. A general solver would give all three and be harder to tune
/// into something that feels right.
final class CharacterController {
  CharacterController({
    required this.world,
    CollisionShape? shape,
    Vector3? position,
    this.tuning = const MovementTuning(),
    // Bit one, which a game usually calls its player — a controller is what a
    // game drives an actor with. Named at the call site rather than here, for
    // the reason on [Layers].
    int layer = 1 << 1,
  }) : _shape = shape ?? CollisionBox(Vector3(0.35, 0.9, 0.35)),
       position = position?.clone() ?? Vector3.zero() {
    // The body registers itself, so monsters see the player as an obstacle and
    // triggers see them walk in. A controller that only reads the world is a
    // controller nothing else can react to.
    collider = world.add(
      Collider(
        shape: _shape,
        position: this.position,
        kind: ColliderKind.kinematic,
        layer: layer,
      ),
    );
  }

  final CollisionWorld world;

  /// The body's collision volume.
  ///
  /// Any shape: sweeping runs against bounds whatever it is, so the choice
  /// costs nothing here and matters elsewhere. The player is a box because
  /// nothing tests exact overlap against them; a monster is a capsule because
  /// a melee swing and a blast both do, and those are exact.
  ///
  /// Read fresh wherever it is used, and changed only through [tryResize].
  CollisionShape get shape => _shape;
  CollisionShape _shape;

  /// This body's entry in the world, kept in step with [position].
  late final Collider collider;

  /// Which contacts this body's own movement counts, or null for all of them.
  ///
  /// Every other body in the world decides what it collides with through
  /// `layer` and `mask`; this one collided with everything solid whether it
  /// wanted to or not, and that asymmetry is what made one-way platforms,
  /// drop-through floors and phase states inexpressible. A mask would have
  /// closed it halfway — see [ContactFilter] for why the normal is needed.
  ///
  /// Applied to the four queries this body makes about the world and to
  /// nothing else: other bodies still see it, triggers still fire, and a
  /// monster does not walk through a wall because the player can.
  ContactFilter? solidFilter;

  /// The scratch this controller hands its own [solidFilter] when it asks
  /// directly rather than through a sweep. See [SweptContact].
  final SweptContact _contact = SweptContact();

  /// Half the body's bounding box: radius in X and Z, half the height in Y.
  Vector3 get halfExtents => shape.boundsHalfExtents;

  /// Every number that decides how this body feels — and **swappable**.
  ///
  /// Not final, which is the whole of what ice, mud, water, a low-gravity room
  /// and a slow-effect are made of: the game assigns a different constant and
  /// the next step uses it. The alternative was a friction multiplier on the
  /// engine, which would have been one genre's word for one of the thirteen
  /// numbers in here.
  ///
  /// [save] does not carry it, deliberately: it is a reference to a constant
  /// the game owns, so the game saves *which* one it had and reassigns on
  /// restore. The same reasoning as [groundBody].
  MovementTuning tuning;

  /// Centre of the box. The eye sits above this.
  final Vector3 position;

  final Vector3 velocity = Vector3.zero();

  bool _grounded = false;
  Collider? _ground;
  double _coyote = 0.0;
  double _jumpBuffer = 0.0;

  /// Whether the next ground probe has been told the body meant to leave.
  ///
  /// See [suppressFloorSnap] for why it exists and why it is a single flag
  /// rather than a timer.
  bool _snapSuppressed = false;

  /// Whether the feet are on something as of the last step.
  bool get isGrounded => _grounded;

  /// Whatever the feet are on, of any kind. Null while airborne.
  ///
  /// The general question, and the one a game asks far more often: what am I
  /// standing on. Ice, mud, a conveyor, a damage floor, which footstep to play
  /// — all of them are this, and all of them were unanswerable while the only
  /// thing recorded was the narrow case below.
  Collider? get ground => _ground;

  /// What the feet are on, **when it moves under its own power**. Null on a
  /// static brush.
  ///
  /// The narrow question: who do I have to move with. Kept separate from
  /// [ground] rather than folded into it, because a lift asks whether anybody
  /// is riding it and every brush in the level would answer yes.
  Collider? get groundBody =>
      _ground != null && _ground!.kind == ColliderKind.kinematic
      ? _ground
      : null;

  /// How many separate surfaces the last step slid along.
  ///
  /// Exposed for debugging a corner that feels sticky: two means a proper
  /// wedge, three means the iteration limit was probably reached.
  ///
  /// Which names who it is for — whoever is standing in that corner with a
  /// debug overlay open. Nothing here reads it, and a rule that only counted
  /// callers would have called it dead and taken it away from them.
  int get contactsLastStep => _contacts;
  int _contacts = 0;

  /// How far the last step lifted the body onto a ledge, in metres.
  ///
  /// Climbing a stair is a *teleport*: [_moveHorizontally] raises the body by
  /// [MovementTuning.stepHeight], carries it across and sets it down, and all
  /// of that is one step of simulated time. The simulation wants it that way.
  /// A renderer does not — fifteen centimetres inside a sixtieth of a second is
  /// nine metres a second, which pitches the horizon on every riser — so it is
  /// reported here for anything drawing the body to smooth over. See
  /// `InterpolatedVector3.stepLimit`.
  ///
  /// Reported rather than left to be worked out from the position, because a
  /// rise the body did not travel through is not the same as a rise it was
  /// carried through: a passenger on a lift is moved by [_carryWithGround] and
  /// looks identical from outside.
  double get steppedUp => _steppedUp;
  double _steppedUp = 0.0;

  /// Whether this step slid along a face flat enough to stand on.
  ///
  /// Set by [_slide] and read by [_probeGround], and it exists because the two
  /// cannot tell each other anything through the velocity: a body going up a
  /// ramp and a body that has just jumped are both rising.
  bool _climbed = false;

  /// Records that the player asked to jump.
  ///
  /// Buffered rather than acted on immediately, so the request survives the
  /// fraction of a second before landing.
  void requestJump() => _jumpBuffer = tuning.jumpBufferTime;

  /// Says that the body is leaving the ground **on purpose**, so the next
  /// ground probe must not pull it back.
  ///
  /// [MovementTuning.floorSnapLength] keeps the feet on a floor they already
  /// had. That is what a stair edge wants and the opposite of what a spring, a
  /// bounce or a jump the game owns wants — and from in here the two look
  /// identical, because both are a body that was grounded last step with its
  /// upward speed written from outside. Nothing on a `Vector3` records who
  /// assigned to it.
  ///
  /// This body's own [_tryJump] needs no such announcement: it clears
  /// [CharacterController.isGrounded] on the spot, which the probe reads as "not mine to keep". It
  /// calls this anyway, so that the rule is one rule with one name rather than
  /// two spellings of it that can drift apart.
  ///
  /// **A flag spent by the next probe, not a timer**, and the difference
  /// matters at the call site: a game may write its velocity before the step
  /// or after it, and a window measured in seconds would have to know which.
  /// One probe is also all that is needed — a body that has genuinely left is
  /// airborne by the end of it, and an airborne body is never snapped again.
  void suppressFloorSnap() => _snapSuppressed = true;

  /// Everything about this body that a snapshot has to carry.
  ///
  /// The four scalars beyond position and velocity are the ones whose absence
  /// is invisible for exactly one step and then wrong: a restore that forgot
  /// [CharacterController.isGrounded] gives the player a free coyote jump, and one that forgot the
  /// jump buffer eats a press made a frame before landing.
  ///
  /// [groundBody] is deliberately **not** here. It is a reference, it is
  /// recomputed at the end of every step by the ground probe, and naming it
  /// would mean inventing an identity scheme for colliders. The cost is one
  /// step of not being carried by a moving platform you were standing on;
  /// stated rather than discovered.
  Map<String, Object?> save() => <String, Object?>{
    'at': <double>[position.x, position.y, position.z],
    'velocity': <double>[velocity.x, velocity.y, velocity.z],
    'grounded': _grounded,
    'coyote': _coyote,
    'jumpBuffer': _jumpBuffer,
  };

  void restore(Map<String, Object?> from) {
    readVector(from['at'], position);
    readVector(from['velocity'], velocity);
    collider.position.setFrom(position);
    collider.refreshBounds();
    collider.clearDelta();
    _grounded = from['grounded'] == true;
    _ground = null;
    _snapSuppressed = false;
    _coyote = readNumber(from['coyote']);
    _jumpBuffer = readNumber(from['jumpBuffer']);
  }

  /// Swaps the body's volume, keeping its feet where they are.
  ///
  /// Returns false and changes **nothing** when the new shape does not fit,
  /// which is the whole reason this is a method and not a setter. "Can I be
  /// this size here" is the question crouching asks on the way back up, and it
  /// is the same question a monster rearing up asks, and a slime splitting, and
  /// a vehicle unfolding. Every one of them would otherwise write this check
  /// itself and one of them would get it wrong.
  ///
  /// Shrinking never fails: a body already touching something must be allowed
  /// to become smaller, or a crouch inside a doorway is refused for being in a
  /// doorway. The refusal is only meaningful when growing.
  ///
  /// [keepFeet] is what a character wants — a crouch that dropped the whole
  /// body would sink it into the floor and be depenetrated back out — and a
  /// caller resizing about the centre says so.
  ///
  /// Not carried by [save]: a `CollisionShape` is not JSON. A game that
  /// crouches saves that it was crouching and calls this again after
  /// [restore]; one that forgets restores a standing body inside a crawlspace
  /// and is ejected from it on the next step.
  bool tryResize(CollisionShape to, {bool keepFeet = true}) {
    final was = halfExtents;
    final will = to.boundsHalfExtents;
    final feet = position.y - was.y;
    _resizeAt.setValues(
      position.x,
      keepFeet ? feet + will.y : position.y,
      position.z,
    );

    final grows =
        will.x > was.x + Nearly.same ||
        will.y > was.y + Nearly.same ||
        will.z > was.z + Nearly.same;
    if (grows) {
      world.overlap(
        to,
        _resizeAt,
        _clearance,
        ignore: collider,
        includeTriggers: false,
      );
      for (final other in _clearance) {
        // Asked with an upward normal, because growing is what this is for and
        // upward is which way a body grows: a one-way platform overhead is not
        // in the way of standing up, for the same reason it is not in the way
        // of jumping.
        if (solidFilter == null) return false;
        _contact.set(other, _up);
        if (solidFilter!(_contact)) return false;
      }
    }

    _shape = to;
    collider.shape = to;
    position.setFrom(_resizeAt);
    collider.position.setFrom(position);
    collider.refreshBounds();
    return true;
  }

  /// Places the player somewhere with no motion and no memory. For spawns and
  /// level changes.
  void teleport(Vector3 to) {
    position.setFrom(to);
    collider.position.setFrom(to);
    collider.refreshBounds();
    velocity.setZero();
    _grounded = false;
    _ground = null;
    _coyote = 0.0;
    _jumpBuffer = 0.0;
    _snapSuppressed = false;
  }

  // Scratch. One step runs several sweeps and the step runs sixty times a
  // second, so none of this is allocated per call.
  final SweepHit _hit = SweepHit();
  final Vector3 _delta = Vector3.zero();
  final Vector3 _correction = Vector3.zero();
  final Vector3 _wish = Vector3.zero();
  final Vector3 _plainPosition = Vector3.zero();
  final Vector3 _plainVelocity = Vector3.zero();
  final Vector3 _stepPosition = Vector3.zero();
  final Vector3 _stepVelocity = Vector3.zero();
  final Vector3 _scratchDelta = Vector3.zero();
  final Vector3 _probe = Vector3.zero();
  final Vector3 _resizeAt = Vector3.zero();
  final Vector3 _up = Vector3(0.0, 1.0, 0.0);
  final List<Collider> _clearance = <Collider>[];

  /// How far to sit back from a surface after touching it.
  ///
  /// Resting exactly on a face leaves the next sweep starting on the boundary,
  /// where the slab test can go either way. A millimetre of clearance costs
  /// nothing visible and removes the whole class of jitter.
  static const double _skin = 0.001;

  /// The flattest a contact's normal may lean and still be a floor.
  ///
  /// It is the cosine of the slope, so 0.5 is sixty degrees: anything steeper
  /// is a wall the body slides down rather than a surface it stands on. Named
  /// because the number is now read by a probe that reaches much further, and
  /// a magic 0.5 in a longer sweep is a much easier thing to get wrong.
  ///
  /// **A game may have a constant that looks like this one and is not.** A
  /// filter deciding whether a particular platform is solid for a particular
  /// contact asks about that contact, not about walkability, and the two agree
  /// today only because the sweeps in [CollisionWorld] cannot report a normal
  /// that is not an axis. Give this figure a name in one place and it stays
  /// one question; share it and the first genre that wants a steeper limit for
  /// its own geometry changes what "standing" means for everybody.
  static const double _walkableNormalY = 0.5;

  /// Advances by [dt].
  ///
  /// [wishDirection] is where the player wants to go, in world space and
  /// horizontal; it need not be normalised, and its length scales the requested
  /// speed so an analogue stick works. [sprint] picks which top speed applies.
  void step(double dt, {required Vector3 wishDirection, bool sprint = false}) {
    _contacts = 0;
    _steppedUp = 0.0;
    _climbed = false;
    _coyote = math.max(0.0, _coyote - dt);
    _jumpBuffer = math.max(0.0, _jumpBuffer - dt);

    _carryWithGround(dt);
    _resolveOverlap();
    _accelerate(dt, wishDirection, sprint);
    _applyGravity(dt);
    _tryJump();
    _moveHorizontally(dt);
    _moveVertically(dt);
    _probeGround();

    // Collider holds its own copy of the position — it clones on construction,
    // and relying on a shared vector would have been a silent aliasing bug the
    // first time one of them was replaced rather than mutated.
    collider.position.setFrom(position);
    collider.refreshBounds();
  }

  /// Moves with whatever the player is standing on, before they move
  /// themselves.
  ///
  /// A lift that rises has to take its passenger with it. Doing this by
  /// collision alone does not work: the lift's surface would push through the
  /// player's feet between one step and the next, and the depenetration below
  /// would shove them out sideways.
  void _carryWithGround(double dt) {
    final under = _ground;
    if (under == null || !_grounded) return;
    // Two ways to be carried, and they are not the same thing. A lift moves,
    // so its whole transform changed and `delta` says by how much. A conveyor
    // does not move at all — only its skin does — so it drags by
    // `surfaceVelocity` and there is nothing in `delta` to find.
    position.add(under.delta);
    final drag = under.surfaceVelocity;
    if (drag.x != 0.0 || drag.y != 0.0 || drag.z != 0.0) {
      position
        ..x += drag.x * dt
        ..y += drag.y * dt
        ..z += drag.z * dt;
    }
  }

  void _resolveOverlap() {
    if (world.depenetrate(
      position,
      halfExtents,
      _correction,
      ignore: collider,
      allow: solidFilter,
    )) {
      position.add(_correction);
      // A ceiling pressing down should not leave upward speed, and a floor
      // pushing up should not leave downward speed.
      if (_correction.y > 0.0 && velocity.y < 0.0) velocity.y = 0.0;
      if (_correction.y < 0.0 && velocity.y > 0.0) velocity.y = 0.0;
    }
  }

  void _accelerate(double dt, Vector3 wishDirection, bool sprint) {
    final topSpeed = sprint ? tuning.sprintSpeed : tuning.walkSpeed;
    _wish.setValues(wishDirection.x, 0.0, wishDirection.z);
    final wishLength = _wish.length;

    if (wishLength < Nearly.still) {
      // Nothing asked for: bleed off horizontal speed. Only on the ground —
      // stopping dead in mid-air is what makes a jump feel like a lift.
      if (!_grounded) return;
      final speed = math.sqrt(
        velocity.x * velocity.x + velocity.z * velocity.z,
      );
      if (speed <= Nearly.still) {
        velocity.x = 0.0;
        velocity.z = 0.0;
        return;
      }
      final drop = math.min(speed, tuning.groundFriction * dt);
      final scale = (speed - drop) / speed;
      velocity.x *= scale;
      velocity.z *= scale;
      return;
    }

    // The length of the request scales the target speed, so half a stick
    // deflection means half speed.
    final requested = topSpeed * math.min(1.0, wishLength);
    _wish.scale(1.0 / wishLength);

    final acceleration =
        (_grounded ? tuning.groundAcceleration : tuning.airAcceleration) * dt;

    // Accelerate only up to the requested speed along the requested direction.
    // Written this way rather than as a straight lerp towards a target velocity
    // because it leaves speed already carried in other directions alone, which
    // is what stops a mid-air turn from acting as a brake.
    final current = velocity.x * _wish.x + velocity.z * _wish.z;
    final add = math.min(acceleration, requested - current);
    if (add <= 0.0) return;

    velocity.x += _wish.x * add;
    velocity.z += _wish.z * add;

    // Then clamp the total, which the step above does not.
    //
    // Acceleration is capped along the requested direction, and that alone is
    // not enough once a wall is involved: sliding strips one component out of
    // the velocity, so the projection onto the wish direction falls, so the
    // body is allowed to accelerate again — and again. A monster with a stated
    // speed of 5.4 was measured doing 6.7 along a wall, and the same arithmetic
    // lets a player wall-strafe faster than they can sprint.
    //
    // Only on the ground. In the air the projection cap is what gives a jump
    // its feel, and clamping there would make mid-air control mushy for the
    // sake of an exploit that needs a surface to work.
    if (!_grounded) return;
    final speed = math.sqrt(velocity.x * velocity.x + velocity.z * velocity.z);
    if (speed > requested && speed > Nearly.still) {
      final scale = requested / speed;
      velocity.x *= scale;
      velocity.z *= scale;
    }
  }

  void _applyGravity(double dt) {
    if (_grounded && velocity.y <= 0.0) {
      // A small downward bias keeps the box pressed against the floor, so the
      // ground probe below keeps finding it on the way down a staircase.
      //
      // Kept even though [MovementTuning.floorSnapLength] now does that job
      // properly, because it is also what the *default* has instead of a snap:
      // removing it would change how every existing game walks, which is a
      // re-baselining this change is not worth. A sixtieth of a second of it
      // is 1.7 cm, well inside the snap's reach, so the two do not fight.
      velocity.y = -1.0;
      return;
    }
    velocity.y = math.max(
      -tuning.terminalVelocity,
      velocity.y - tuning.gravity * dt,
    );
  }

  void _tryJump() {
    if (_jumpBuffer <= 0.0) return;
    if (!_grounded && _coyote <= 0.0) return;

    velocity.y = tuning.jumpSpeed;
    _jumpBuffer = 0.0;
    _coyote = 0.0;
    _grounded = false;
    _ground = null;
    // Belt and braces, and said out loud: clearing [_grounded] on the line
    // above is already enough for this step's probe. See [suppressFloorSnap]
    // for why the rule is spelt once rather than twice.
    suppressFloorSnap();
  }

  /// Horizontal motion, with a step-up attempt when it gets blocked.
  void _moveHorizontally(double dt) {
    _delta.setValues(velocity.x * dt, 0.0, velocity.z * dt);
    if (_delta.x == 0.0 && _delta.z == 0.0) return;

    // The plain attempt: slide along whatever is in the way.
    _plainPosition.setFrom(position);
    _plainVelocity.setFrom(velocity);
    _scratchDelta.setFrom(_delta);
    final blocked = _slide(_plainPosition, _plainVelocity, _scratchDelta);

    if (!blocked || !_grounded) {
      position.setFrom(_plainPosition);
      velocity.setFrom(_plainVelocity);
      return;
    }

    // Blocked while on the ground: it might be a stair rather than a wall.
    // Going up, across and down is the cheap way to tell the difference — a
    // wall stops the across move too, a stair does not.
    _stepPosition.setFrom(position);
    _stepVelocity.setFrom(velocity);

    if (!_moveAxisSwept(_stepPosition, 0.0, tuning.stepHeight, 0.0)) {
      // No headroom to step into.
      position.setFrom(_plainPosition);
      velocity.setFrom(_plainVelocity);
      return;
    }

    _scratchDelta.setFrom(_delta);
    _slide(_stepPosition, _stepVelocity, _scratchDelta);
    _moveAxisSwept(_stepPosition, 0.0, -tuning.stepHeight, 0.0);

    // Take the step only if it actually got further along the way the player
    // asked to go. Comparing total distance instead would accept a stumble
    // sideways, and comparing height would accept climbing a wall.
    final plainProgress =
        (_plainPosition.x - position.x) * _delta.x +
        (_plainPosition.z - position.z) * _delta.z;
    final stepProgress =
        (_stepPosition.x - position.x) * _delta.x +
        (_stepPosition.z - position.z) * _delta.z;

    if (stepProgress > plainProgress + Nearly.still) {
      // Before the assignment, because this is how far the body was lifted and
      // [position] is still where it was lifted from.
      _steppedUp = math.max(0.0, _stepPosition.y - position.y);
      position.setFrom(_stepPosition);
      velocity.setFrom(_stepVelocity);
    } else {
      position.setFrom(_plainPosition);
      velocity.setFrom(_plainVelocity);
    }
  }

  void _moveVertically(double dt) {
    _scratchDelta.setValues(0.0, velocity.y * dt, 0.0);
    if (_scratchDelta.y == 0.0) return;
    _slide(position, velocity, _scratchDelta);
  }

  /// Moves [point] by one axis-aligned offset, stopping at the first contact.
  ///
  /// Returns whether the whole offset was travelled.
  bool _moveAxisSwept(Vector3 point, double dx, double dy, double dz) {
    _probe.setValues(dx, dy, dz);
    if (!world.sweep(
      shape,
      point,
      _probe,
      _hit,
      ignore: collider,
      allow: solidFilter,
    )) {
      point.add(_probe);
      return true;
    }
    final travel = math.max(0.0, _hit.fraction);
    point
      ..x += _probe.x * travel + _hit.normal.x * _skin
      ..y += _probe.y * travel + _hit.normal.y * _skin
      ..z += _probe.z * travel + _hit.normal.z * _skin;
    return false;
  }

  /// Sweep, stop, strip the blocked direction out, repeat.
  ///
  /// Three passes, not one: in an inside corner the first slide runs the player
  /// straight into the second wall, and one more pass is needed for each
  /// surface they end up touching. Three covers a corner of a room — a floor
  /// and two walls — and beyond that the remaining motion is small enough to
  /// abandon.
  ///
  /// Returns whether anything was in the way.
  bool _slide(Vector3 point, Vector3 vel, Vector3 delta) {
    var blocked = false;

    for (var pass = 0; pass < 3; pass++) {
      if (delta.x == 0.0 && delta.y == 0.0 && delta.z == 0.0) break;

      if (!world.sweep(
        shape,
        point,
        delta,
        _hit,
        ignore: collider,
        allow: solidFilter,
      )) {
        point.add(delta);
        delta.setZero();
        break;
      }

      blocked = true;
      _contacts++;

      final travel = math.max(0.0, _hit.fraction);
      point
        ..x += delta.x * travel + _hit.normal.x * _skin
        ..y += delta.y * travel + _hit.normal.y * _skin
        ..z += delta.z * travel + _hit.normal.z * _skin;

      // Keep only the part of the remaining motion that runs along the surface.
      final remaining = 1.0 - travel;
      delta.scale(remaining);
      final intoSurface = delta.dot(_hit.normal);
      if (intoSurface < 0.0) {
        delta.x -= _hit.normal.x * intoSurface;
        delta.y -= _hit.normal.y * intoSurface;
        delta.z -= _hit.normal.z * intoSurface;
      }

      // **A walkable face under the body is a slope being climbed, not a wall
      // being hit.** Stripping the into-surface component below is what turns a
      // horizontal push into motion up a ramp — and it puts that motion in the
      // *velocity* too, so the body ends the step travelling upwards. Nothing
      // told the ground probe the difference, and a probe that reads upward
      // speed as a jump left the body airborne the whole way up and launched it
      // off the top: a ramp was a ski jump.
      if (_hit.normal.y > _walkableNormalY) _climbed = true;

      // Speed into the surface is gone for good, or the player would keep
      // accelerating into a wall and shoot along it the moment it ended.
      final speedIntoSurface = vel.dot(_hit.normal);
      if (speedIntoSurface < 0.0) {
        vel.x -= _hit.normal.x * speedIntoSurface;
        vel.y -= _hit.normal.y * speedIntoSurface;
        vel.z -= _hit.normal.z * speedIntoSurface;
      }
    }

    return blocked;
  }

  /// Decides whether the player is standing on anything, and snaps them to it.
  void _probeGround() {
    // Spent here whatever happens, so that a body which really did leave is
    // not still carrying permission on some later step. One probe is the whole
    // window — see [suppressFloorSnap].
    final leftDeliberately = _snapSuppressed;
    _snapSuppressed = false;

    // Rising because a slope pushed the body up it, rather than because the
    // body left the ground on purpose. The two are indistinguishable from the
    // velocity alone, which is why [_slide] records it.
    final climbing = _climbed && !leftDeliberately;

    if (velocity.y > 0.0 && !climbing) {
      // On the way up nothing counts as ground, or a jump would be cancelled by
      // the floor it just left. **The exception is a climb**, and it has to be
      // an exception rather than a wider rule: a jump also rises with a floor
      // an inch below it, and grounding that is a player who cannot jump.
      _setAirborne();
      return;
    }

    // How far down to look. Past [MovementTuning.groundProbe] only to *keep* a
    // floor: the feet must have been on something as of last step, and must
    // not have chosen to leave it. A body that was already airborne gets the
    // short probe, so the long reach can never find ground the body was not
    // standing on — which is what stops a snap from being a body that cannot
    // fall.
    final reach = _grounded && !leftDeliberately
        ? math.max(tuning.groundProbe, tuning.floorSnapLength)
        : tuning.groundProbe;

    _probe.setValues(0.0, -reach, 0.0);
    // **`allow: solidFilter` is not optional here**, and it is easy to think
    // it is. The filter is how a game says which surfaces count for this body
    // — a platform that is a floor only from above, one it has just asked to
    // fall through, a phase state — and a reach this long without it stands
    // the body on a surface the game has refused. Not for ever: the step after
    // that, gravity sinks the box into the surface, and a sweep whose shape
    // starts inside a box reports no contact at all, so the fall resumes by
    // itself. One step of it is still a landing, a refilled coyote timer, and
    // [ground] naming a collider that is not supposed to be there.
    if (!world.sweep(
          shape,
          position,
          _probe,
          _hit,
          ignore: collider,
          allow: solidFilter,
        ) ||
        _hit.normal.y <= _walkableNormalY) {
      _setAirborne();
      return;
    }

    position.y += _probe.y * math.max(0.0, _hit.fraction) + _skin;
    velocity.y = 0.0;
    _grounded = true;
    // Whatever it is, recorded. It used to keep only kinematic bodies, on the
    // grounds that a brush needs no carrying and a reference to one would be
    // noise — true of carrying, and it threw away the answer to every other
    // question about the floor. [groundBody] still narrows it.
    _ground = _hit.collider;
    _coyote = tuning.coyoteTime;
  }

  void _setAirborne() {
    _grounded = false;
    _ground = null;
  }
}
