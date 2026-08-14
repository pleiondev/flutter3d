import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'collider.dart';
import 'collision_shape.dart';
import 'collision_world.dart';

/// Every number that decides how the player feels, in one place.
///
/// Collected rather than scattered because they are going to be changed
/// hundreds of times, always together, and always by feel. A tuning value
/// buried in the middle of the movement code is a tuning value nobody adjusts.
final class MovementTuning {
  const MovementTuning({
    this.walkSpeed = 6.0,
    this.sprintSpeed = 10.0,
    this.groundAcceleration = 70.0,
    this.groundFriction = 55.0,
    this.airAcceleration = 14.0,
    this.gravity = 24.0,
    this.terminalVelocity = 55.0,
    this.jumpSpeed = 8.0,
    this.stepHeight = 0.4,
    this.coyoteTime = 0.1,
    this.jumpBufferTime = 0.1,
    this.groundProbe = 0.08,
  });

  final double walkSpeed;
  final double sprintSpeed;

  /// How fast the player reaches the speed they asked for, in m/s².
  ///
  /// Finite rather than instant, because the answer to "with inertia" is here.
  /// High enough that the controls still feel immediate; low enough that a
  /// direction change costs something.
  final double groundAcceleration;

  /// How fast the player stops when they ask for nothing.
  final double groundFriction;

  /// Acceleration while airborne.
  ///
  /// A fraction of the ground figure, and no air friction at all: a jump should
  /// commit the player to roughly where they were going, but not strand them
  /// helplessly.
  final double airAcceleration;

  final double gravity;

  /// Ceiling on falling speed, so a long drop cannot outrun the sweep.
  final double terminalVelocity;

  final double jumpSpeed;

  /// The tallest lip the player walks over instead of into.
  final double stepHeight;

  /// How long after walking off an edge a jump still works.
  ///
  /// Without it the controls feel broken and the player blames themselves. It
  /// costs one timer, and every platformer worth playing has it.
  final double coyoteTime;

  /// How long before landing a jump can be asked for and still happen.
  ///
  /// The other half of the same problem: pressing jump a frame early should not
  /// silently do nothing.
  final double jumpBufferTime;

  /// How far below the feet still counts as standing on something.
  ///
  /// Not zero: on a staircase the player leaves the ground for a fraction of a
  /// step on every stair, and a controller that believes it is falling there
  /// cannot jump and plays footstep sounds wrong.
  final double groundProbe;
}

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
  })  : shape = shape ?? CollisionBox(Vector3(0.35, 0.9, 0.35)),
        position = position?.clone() ?? Vector3.zero() {
    // The body registers itself, so monsters see the player as an obstacle and
    // triggers see them walk in. A controller that only reads the world is a
    // controller nothing else can react to.
    collider = world.add(
      Collider(
        shape: this.shape,
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
  final CollisionShape shape;

  /// This body's entry in the world, kept in step with [position].
  late final Collider collider;

  /// Half the body's bounding box: radius in X and Z, half the height in Y.
  Vector3 get halfExtents => shape.boundsHalfExtents;

  final MovementTuning tuning;

  /// Centre of the box. The eye sits above this.
  final Vector3 position;

  final Vector3 velocity = Vector3.zero();

  bool _grounded = false;
  Collider? _groundBody;
  double _coyote = 0.0;
  double _jumpBuffer = 0.0;

  /// Whether the feet are on something as of the last step.
  bool get isGrounded => _grounded;

  /// What the feet are on, when it moves under its own power.
  Collider? get groundBody => _groundBody;

  /// How many separate surfaces the last step slid along.
  ///
  /// Exposed for debugging a corner that feels sticky: two means a proper
  /// wedge, three means the iteration limit was probably reached.
  int get contactsLastStep => _contacts;
  int _contacts = 0;

  /// Records that the player asked to jump.
  ///
  /// Buffered rather than acted on immediately, so the request survives the
  /// fraction of a second before landing.
  void requestJump() => _jumpBuffer = tuning.jumpBufferTime;

  /// Everything about this body that a snapshot has to carry.
  ///
  /// The four scalars beyond position and velocity are the ones whose absence
  /// is invisible for exactly one step and then wrong: a restore that forgot
  /// [isGrounded] gives the player a free coyote jump, and one that forgot the
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
    _readVector(from['at'], position);
    _readVector(from['velocity'], velocity);
    collider.position.setFrom(position);
    collider.refreshBounds();
    collider.clearDelta();
    _grounded = from['grounded'] == true;
    _groundBody = null;
    _coyote = _readNumber(from['coyote']);
    _jumpBuffer = _readNumber(from['jumpBuffer']);
  }

  static void _readVector(Object? value, Vector3 out) {
    if (value is! List || value.length < 3) return;
    out.setValues(
      (value[0] as num).toDouble(),
      (value[1] as num).toDouble(),
      (value[2] as num).toDouble(),
    );
  }

  static double _readNumber(Object? value) =>
      value is num ? value.toDouble() : 0.0;

  /// Places the player somewhere with no motion and no memory. For spawns and
  /// level changes.
  void teleport(Vector3 to) {
    position.setFrom(to);
    collider.position.setFrom(to);
    collider.refreshBounds();
    velocity.setZero();
    _grounded = false;
    _groundBody = null;
    _coyote = 0.0;
    _jumpBuffer = 0.0;
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

  /// How far to sit back from a surface after touching it.
  ///
  /// Resting exactly on a face leaves the next sweep starting on the boundary,
  /// where the slab test can go either way. A millimetre of clearance costs
  /// nothing visible and removes the whole class of jitter.
  static const double _skin = 0.001;

  /// Advances by [dt].
  ///
  /// [wishDirection] is where the player wants to go, in world space and
  /// horizontal; it need not be normalised, and its length scales the requested
  /// speed so an analogue stick works. [sprint] picks which top speed applies.
  void step(
    double dt, {
    required Vector3 wishDirection,
    bool sprint = false,
  }) {
    _contacts = 0;
    _coyote = math.max(0.0, _coyote - dt);
    _jumpBuffer = math.max(0.0, _jumpBuffer - dt);

    _carryWithGround();
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
  void _carryWithGround() {
    final body = _groundBody;
    if (body == null || !_grounded) return;
    position.add(body.delta);
  }

  void _resolveOverlap() {
    if (world.depenetrate(
      position,
      halfExtents,
      _correction,
      ignore: collider,
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

    if (wishLength < 1e-6) {
      // Nothing asked for: bleed off horizontal speed. Only on the ground —
      // stopping dead in mid-air is what makes a jump feel like a lift.
      if (!_grounded) return;
      final speed = math.sqrt(
        velocity.x * velocity.x + velocity.z * velocity.z,
      );
      if (speed <= 1e-6) {
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
    final speed = math.sqrt(
      velocity.x * velocity.x + velocity.z * velocity.z,
    );
    if (speed > requested && speed > 1e-6) {
      final scale = requested / speed;
      velocity.x *= scale;
      velocity.z *= scale;
    }
  }

  void _applyGravity(double dt) {
    if (_grounded && velocity.y <= 0.0) {
      // A small downward bias keeps the box pressed against the floor, so the
      // ground probe below keeps finding it on the way down a staircase.
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
    _groundBody = null;
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
    final plainProgress = (_plainPosition.x - position.x) * _delta.x +
        (_plainPosition.z - position.z) * _delta.z;
    final stepProgress = (_stepPosition.x - position.x) * _delta.x +
        (_stepPosition.z - position.z) * _delta.z;

    if (stepProgress > plainProgress + 1e-6) {
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
    if (!world.sweep(shape, point, _probe, _hit, ignore: collider)) {
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

      if (!world.sweep(shape, point, delta, _hit, ignore: collider)) {
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
    if (velocity.y > 0.0) {
      // On the way up nothing counts as ground, or a jump would be cancelled by
      // the floor it just left.
      _setAirborne();
      return;
    }

    _probe.setValues(0.0, -tuning.groundProbe, 0.0);
    if (!world.sweep(shape, position, _probe, _hit, ignore: collider) ||
        _hit.normal.y <= 0.5) {
      _setAirborne();
      return;
    }

    position.y += _probe.y * math.max(0.0, _hit.fraction) + _skin;
    velocity.y = 0.0;
    _grounded = true;
    // Only a body that moves is worth remembering: standing on a brush needs no
    // carrying, and holding a reference to one would just be noise.
    final ground = _hit.collider;
    _groundBody = ground != null && ground.kind == ColliderKind.kinematic
        ? ground
        : null;
    _coyote = tuning.coyoteTime;
  }

  void _setAirborne() {
    _grounded = false;
    _groundBody = null;
  }
}
