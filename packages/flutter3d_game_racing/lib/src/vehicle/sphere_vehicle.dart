import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import '../layers.dart';
import '../track_field.dart';
import 'tire_model.dart';
import 'tyres.dart';
import 'vehicle_controller.dart';

/// The numbers that make one car feel different from another.
///
/// All in one place and all plain units, so that tuning a car is reading a
/// table rather than hunting through a step function — the same reason the
/// platformer's `MovementTuning` and `RunnerTuning` exist.
final class VehicleTuning {
  const VehicleTuning({
    this.radius = 0.7,
    this.rideHeight = 0.55,
    this.maxSpeed = 52.0,
    this.maxReverse = 12.0,
    this.enginePush = 14.0,
    this.brakeStrength = 26.0,
    this.rollingDrag = 3.0,
    this.airDrag = 0.0006,
    this.maxSteer = 0.62,
    this.steerFalloff = 26.0,
    this.wheelBase = 2.7,
    this.gravity = 20.0,
    this.impactShrugged = 6.0,
    this.impactCost = 0.017,
    this.powerLostWhenWrecked = 0.45,
    this.speedLostWhenWrecked = 0.25,
    this.groundStick = 0.45,
    this.suspensionRate = 18.0,
    this.slideAlignment = 2.2,
    this.wheelInertia = 0.25,
  });

  /// The body's collision radius. One sphere, because a car that is a box has
  /// corners, and a corner catching on a kerb at ninety metres a second is a
  /// car on its roof.
  final double radius;

  /// How far the body floats above the road.
  final double rideHeight;

  final double maxSpeed;
  final double maxReverse;

  /// How quickly the driven wheels spin up, in metres per second squared. Not
  /// the car's acceleration — how fast the *wheels* gain speed. What the car
  /// does about that is up to the tyres.
  final double enginePush;

  final double brakeStrength;

  /// How quickly the wheels fall back to the car's speed with nothing pressed:
  /// engine braking, near enough.
  final double rollingDrag;

  /// Drag per unit of speed squared. What gives the car a top speed without one
  /// having to be enforced.
  final double airDrag;

  /// How far the wheels turn at a standstill, in radians.
  final double maxSteer;

  /// The speed at which the steering has closed to half of [maxSteer].
  ///
  /// Without this the car is undriveable fast and unturnable slow: full lock at
  /// a hundred and eighty kilometres an hour asks the tyres for a corner they
  /// cannot hold, and the car simply spins every time.
  final double steerFalloff;

  /// Front axle to rear axle. Sets how quickly steering turns the car.
  final double wheelBase;

  /// Deliberately above the real figure. Arcade cars jump, and a jump under
  /// real gravity hangs long enough to feel like a bug.
  final double gravity;

  /// How much speed an impact can take out of the car, in metres per second,
  /// before it counts as damage at all.
  ///
  /// Six, which is a car nudging a kerb or leaning on a barrier through a
  /// corner. A racing line that touches things is a racing line, and a game
  /// that charged for it would be a game about not racing.
  final double impactShrugged;

  /// How much damage each metre per second past [impactShrugged] does.
  ///
  /// A wreck at one. So a forty-mile-an-hour shunt — eighteen metres a second
  /// gone in one step — costs a fifth of the car, and it takes five of those to
  /// finish it. Enough to change a race, not enough to end one on a mistake.
  final double impactCost;

  /// How much of the engine a fully wrecked car has lost.
  final double powerLostWhenWrecked;

  /// How much of its top speed. Less than the power: a broken car should take
  /// longer to get going rather than stop being a car.
  final double speedLostWhenWrecked;

  /// How far below the car the ground still counts as under it.
  final double groundStick;

  /// How quickly the body settles to its ride height. Stands in for suspension
  /// until there is suspension.
  final double suspensionRate;

  /// How strongly a slide pulls the nose round with it.
  ///
  /// A car sliding sideways is turned by the air and by its own tyres, and
  /// without something standing in for that the nose only ever moves where the
  /// steering puts it — which makes a spin impossible and a caught slide
  /// unsatisfying.
  final double slideAlignment;

  /// How much the tyre's grip holds the driven wheels back, as a fraction of
  /// what it does to the car.
  ///
  /// The engine spins the wheels up and the road drags them back, and this is
  /// the second half of that. Without it the wheels are driven in a vacuum, and
  /// then the car — pushed by tyres that answer the resulting slip — can
  /// accelerate harder than the wheels turning it ever do, which is not a car.
  ///
  /// Well below one because a wheel is light and a car is not: the wheels win,
  /// and the surplus is what appears as wheelspin on a loose surface.
  final double wheelInertia;
}

/// A car that is one sphere, with the body drawn on top of it.
///
/// ## Why a sphere
///
/// This is the shape an arcade racer usually is, and it is chosen for what it
/// refuses to do rather than what it does. A sphere has no corners to catch on
/// a kerb, no orientation to solve for, and no way to end up on its roof. The
/// car's *body* — where its nose points, how it leans through a banked corner —
/// is carried alongside as [headingYaw] and [visualBasis] and is not what
/// collides. The result is a car that goes where it is pointed, which is what
/// an arcade game wants, and the price is that it cannot roll over, which an
/// arcade game does not want anyway.
///
/// The four-ray model with springs, which can do those things, goes behind the
/// same [VehicleController] interface later.
///
/// ## Why it is kinematic
///
/// The car integrates its own forces and moves itself by sweeping, exactly as
/// the platformer's character controller does, and for the same reason the
/// physics package states outright: something driven by the player through a
/// solver slides, jitters, and is different at a different frame rate. Sweeping
/// also means a car at ninety metres a second cannot pass through a wall, which
/// a body handed to a solver without continuous collision certainly can.
///
/// What is *not* the car — cones, barrels, crates — stays with `Dynamics` and
/// is shoved by the car on purpose, never by leftover velocity.
///
/// ## Three states, not one
///
/// The whole feel comes from keeping three things apart that a simpler model
/// would fuse: where the car is going ([velocity]), where it is pointing
/// ([headingYaw]), and how fast its wheels are turning (the transmission). Slip
/// angle is the gap between the first two; slip ratio is the gap between the
/// first and the third. Fuse any pair and the corresponding way of losing grip
/// stops existing.
final class SphereVehicle implements VehicleController {
  SphereVehicle({
    required this.world,
    required this.ground,
    required Vector3 position,
    double headingYaw = 0.0,
    this.tuning = const VehicleTuning(),
    Tyres? tyres,
    int layer = RacingLayers.vehicle,
    int mask = Layers.all,
    Object? userData,
  })  : tyres = tyres ?? Tyres.road,
        // ignore: prefer_initializing_formals
        _headingYaw = headingYaw,
        collider = Collider(
          shape: CollisionSphere(tuning.radius),
          position: position,
          kind: ColliderKind.kinematic,
          layer: layer,
          mask: mask,
          userData: userData,
        ) {
    world.add(collider);
    _ground.s = 0.0;
  }

  /// Puts a different set of tyres on, if the car is standing still.
  ///
  /// Returns whether they went on. [pitStop] is this and the repairs together,
  /// which is what the game offers a player; this is the half of it a test — or
  /// a game that wants to charge for the two separately — can call on its own.
  bool fitTyres(Tyres set) {
    if (speed > 0.5) return false;
    tyres = set;
    return true;
  }

  final CollisionWorld world;

  /// Where the car asks what is underneath it. A track, usually; a flat plane
  /// in most of the tests, which is the reason it is an interface.
  final GroundField ground;

  final VehicleTuning tuning;

  /// What the car is standing on the road with.
  ///
  /// Not final: a set of tyres is the one part of a car a driver is allowed to
  /// change without building another car, and changing them is a decision the
  /// game can put a price on. Nothing here is stateful — a [Tyres] is a table
  /// of numbers — so swapping one for another mid-race is exactly as safe as
  /// having started on it.
  Tyres tyres;

  /// How broken the car is, from nought to one.
  ///
  /// **Not a health bar with a death at the end of it.** A car that stopped
  /// existing would take the race with it; what this does is make the car
  /// slower, so a crash costs the thing a race is actually made of. Every car
  /// carries it, including the ones nobody is driving — a rival that hit the
  /// wall on lap one should be catchable on lap three.
  double damage = 0.0;

  /// The curve, from the tyres that are on it.
  TireModel get tires => tyres.model;

  /// What each surface is worth to the tyres that are on it.
  GripTable get grips => tyres.grips;

  @override
  final Collider collider;

  @override
  Vector3 get position => collider.position;

  @override
  final Vector3 velocity = Vector3.zero();

  @override
  double get headingYaw => _headingYaw;
  double _headingYaw;

  @override
  double get speed => velocity.length;

  @override
  double get slipAngle => _slipAngle;
  double _slipAngle = 0.0;

  @override
  double get slipRatio => _slipRatio;
  double _slipRatio = 0.0;

  @override
  bool get grounded => _grounded;
  bool _grounded = false;

  @override
  double get rpm => (_wheelSpeed.abs() / tuning.maxSpeed).clamp(0.0, 1.0);

  @override
  double get trackDistance => _ground.s;

  /// What the last step found underneath the car. Read by whoever wants to know
  /// which surface the tyres are on, or how far off the racing line the car is.
  GroundSample get groundSample => _ground;

  @override
  Matrix3 get visualBasis {
    // Rebuilt on demand rather than kept: only the part of the game that draws
    // the car wants it, and that runs once a frame rather than once a step.
    _basis.setValues(
      _right.x, _right.y, _right.z, //
      _up.x, _up.y, _up.z, //
      _forward.x, _forward.y, _forward.z,
    );
    return _basis;
  }

  /// How fast the driven wheels are turning, as the speed the car would be
  /// doing if they were not slipping.
  double get wheelSpeed => _wheelSpeed;
  double _wheelSpeed = 0.0;

  /// Advances one step.
  ///
  /// The order below is the whole model, and it is an order rather than a set:
  ///
  /// 1.  ask the ground what is underneath, from where the car was last time —
  ///     that hint is what keeps a hairpin from teleporting the car up the road;
  /// 2.  work out how much grip this surface and this slope allow;
  /// 3.  turn the nose, from the steering and from any slide already happening;
  /// 4.  turn the wheels, from the throttle, the brakes and the handbrake;
  /// 5.  measure both slips — the gap between where the car points and where it
  ///     goes, and between the wheels and the road;
  /// 6.  ask the tyres what that is worth, and hold the two answers inside one
  ///     circle, which is what makes braking cost cornering;
  /// 7.  add gravity, down the slope when on the ground and straight down when
  ///     not;
  /// 8.  sweep the body along its velocity, sliding off whatever it meets;
  /// 9.  hold the car inside any barrier the track has here;
  /// 10. settle the body onto its ride height.
  @override
  void step(double dt, VehicleInput input) {
    _scraped = 0.0;
    _struck = 0.0;
    final found = ground.sample(position, _ground.s, _ground);
    _readGround(found);
    _buildFrame();

    final limit = _gripLimit();

    if (_grounded) {
      _steer(dt, input);
    }
    _drive(dt, input);

    final forwardSpeed = velocity.dot(_forward);
    final lateralSpeed = velocity.dot(_right);
    _measureSlip(forwardSpeed, lateralSpeed);

    if (_grounded) {
      _applyTires(dt, limit, forwardSpeed);
    }
    _applyGravityAndDrag(dt);
    _move(dt);
    _holdInsideBarrier();
    _settle(dt, found);
  }

  @override
  void placeAt(Vector3 position, double headingYaw, {double? trackDistance}) {
    collider.position.setFrom(position);
    velocity.setZero();
    _headingYaw = headingYaw;
    _wheelSpeed = 0.0;
    _slipAngle = 0.0;
    _slipRatio = 0.0;
    _grounded = false;
    if (trackDistance != null) _ground.s = trackDistance;
    _buildFrame();
  }

  /// Everything about this car that a lap is made of.
  ///
  /// **Not the tuning and not the grips**: those are what the game is, not what
  /// the race is, and a save that carried them would restore a car built by an
  /// older balance patch into a game that has since been tuned. The same rule
  /// the level format keeps — a snapshot restores into the world it was taken
  /// in, and the world says what a car weighs.
  ///
  /// The wheel speed is here and it is not decoration: it is the difference
  /// between the wheels and the road, which is what the tyre model reads. Drop
  /// it and a restored car at a hundred miles an hour has wheels that are not
  /// turning, which is a car that spends the next second locked up in a slide
  /// it never made.
  @override
  Map<String, Object?> save() => <String, Object?>{
        'at': <double>[position.x, position.y, position.z],
        'velocity': <double>[velocity.x, velocity.y, velocity.z],
        'yaw': _headingYaw,
        'wheelSpeed': _wheelSpeed,
        'slipAngle': _slipAngle,
        'slipRatio': _slipRatio,
        'grounded': _grounded,
        'underPower': _underPower,
        // Where the car is round the lap. Worked out by the ground field every
        // step, and restored anyway: the first step after a restore reads it
        // before it writes it, and a car that starts the lap at nought is a car
        // that has just driven backwards past the finish line.
        'trackDistance': _ground.s,
        // **Saved, or a restored race hands every wreck back its engine.** The
        // shooter's own snapshot test caught exactly this about a recoil the
        // day it was added; a car is no different.
        'damage': damage,
        'tyres': tyres.name,
      };

  @override
  void restore(Map<String, Object?> from) {
    from.vectorInto('at', collider.position);
    from.vectorInto('velocity', velocity);
    _headingYaw = from.number('yaw', _headingYaw);
    _wheelSpeed = from.number('wheelSpeed');
    _slipAngle = from.number('slipAngle');
    _slipRatio = from.number('slipRatio');
    _grounded = from.flag('grounded');
    _underPower = from.flag('underPower');
    _ground.s = from.number('trackDistance', _ground.s);
    damage = from.number('damage');
    // A name this build no longer ships reads as the set every car starts on,
    // rather than as a crash on the launch after an update.
    tyres = Tyres.named(from['tyres'] as String?);
    // The basis is derived, not saved: it follows from the heading and the
    // ground's normal, and rebuilding it is how a restored car is drawn the
    // right way up on the first frame rather than the second.
    _buildFrame();
  }

  // --- the step, in the order above ------------------------------------------

  void _readGround(bool found) {
    if (!found) {
      _grounded = false;
      return;
    }
    final rideTarget = _ground.height + tuning.rideHeight;
    _grounded = position.y <= rideTarget + tuning.groundStick;
  }

  /// The car's own set of axes: where it points, flattened onto whatever it is
  /// standing on.
  void _buildFrame() {
    if (_grounded) {
      _normal.setFrom(_ground.normal);
    } else {
      // In the air the car keeps the attitude it left the ground with, near
      // enough: levelling it out mid-jump would look like a car righting itself
      // on nothing.
      _normal.setValues(0.0, 1.0, 0.0);
    }

    _forward.setValues(math.sin(_headingYaw), 0.0, math.cos(_headingYaw));
    // Flatten the heading onto the surface, so that a car on a slope drives
    // along it rather than into it.
    _forward.addScaled(_normal, -_forward.dot(_normal));
    final length = _forward.length;
    if (length < 1e-6) {
      _forward.setValues(math.sin(_headingYaw), 0.0, math.cos(_headingYaw));
    } else {
      _forward.scale(1.0 / length);
    }

    _right
      ..setFrom(_normal)
      ..crossInto(_forward, _right);
    final rightLength = _right.length;
    if (rightLength > 1e-6) _right.scale(1.0 / rightLength);

    _forward.crossInto(_right, _up);
  }

  /// What the tyres can do here, in metres per second squared.
  ///
  /// Mass is absent on purpose — see [TireModel]. The slope enters through how
  /// much of the car's weight is pressing into the road: a wall would take
  /// none.
  double _gripLimit() {
    final grip = grips.gripFor(_ground.surface);
    final lean = _normal.y.clamp(0.2, 1.0);
    return grip * tyres.limit * tuning.gravity * lean;
  }

  void _steer(double dt, VehicleInput input) {
    final forwardSpeed = velocity.dot(_forward);

    // Full lock at a standstill closes towards nothing at speed. The falloff is
    // by speed rather than by a table, so there is no seam at a gear change.
    final authority = tuning.steerFalloff / (tuning.steerFalloff + speed);

    // Negated, and this is the sign the whole game is hung on. Heading counts
    // anticlockwise seen from above — `forward` is `(sin yaw, cos yaw)`, so a
    // rising yaw swings the nose towards +x, and +x is the driver's *left*
    // (right is `forward × up`, which for a car facing +z is −x). So a driver
    // asking for right, which `VehicleInput.steer` documents as positive, is
    // asking for the yaw to come down.
    //
    // Getting this backwards is not subtle to play and is nearly invisible to
    // read: everything downstream stays self-consistent, the car drives, the AI
    // gets round, every test passes, and the only thing wrong is that the wheel
    // steers the other way.
    final angle = -tuning.maxSteer * input.steer.clamp(-1.0, 1.0) * authority;

    // The bicycle model: the car turns about a point out to the side, at a rate
    // set by how fast it is going and how far the wheels are turned.
    var yawRate = forwardSpeed / tuning.wheelBase * math.tan(angle);

    // And a slide drags the nose round with it. Without this the nose only goes
    // where it is steered, which means a car can never spin and a caught slide
    // never rewards catching it.
    yawRate += _slipAngle * tuning.slideAlignment * _slideStrength();

    _headingYaw += yawRate * dt;
  }

  /// How much of the sliding term applies: nothing at a standstill, all of it
  /// once the car is properly moving.
  double _slideStrength() => (speed / 8.0).clamp(0.0, 1.0);

  /// The transmission: what the wheels are doing, which is not what the car is
  /// doing.
  void _drive(double dt, VehicleInput input) {
    final forwardSpeed = velocity.dot(_forward);
    final throttle = input.throttle.clamp(0.0, 1.0);
    final brake = input.brake.clamp(0.0, 1.0);

    _underPower = !input.handbrake && brake <= 0.0 && throttle > 0.0;

    if (input.handbrake) {
      // Locked. The wheels stop; the car does not. Everything that follows from
      // that — the grip budget going to the locked wheels, the back coming
      // round — is the tyre model's doing and not a special case here.
      _wheelSpeed = approach(_wheelSpeed, 0.0, tuning.brakeStrength * 2.0 * dt);
      return;
    }

    if (brake > 0.0) {
      final target = forwardSpeed > 0.5 ? 0.0 : -tuning.maxReverse;
      _wheelSpeed =
          approach(_wheelSpeed, target, tuning.brakeStrength * brake * dt);
      return;
    }

    if (throttle > 0.0) {
      // A broken car is a slower car, which is the only place damage is felt.
      // Both of these are the engine's side of it: what the tyres can do with
      // the power is unchanged, so a wreck still corners and still stops — it
      // simply cannot get down the straight any more.
      _wheelSpeed +=
          tuning.enginePush * (1.0 - damage * tuning.powerLostWhenWrecked) *
              throttle * dt;
      _wheelSpeed = _wheelSpeed.clamp(
        -tuning.maxReverse,
        tuning.maxSpeed * (1.0 - damage * tuning.speedLostWhenWrecked),
      );
      return;
    }

    // Coasting: the wheels fall back to whatever the road is doing.
    _wheelSpeed = approach(_wheelSpeed, forwardSpeed, tuning.rollingDrag * dt);
  }

  void _measureSlip(double forwardSpeed, double lateralSpeed) {
    // The floors matter. Both slips are ratios against how fast the car is
    // going, and a car that is barely moving would otherwise report enormous
    // slip from a millimetre of drift — and then be thrown across the road by
    // tyres answering it.
    _slipAngle = math.atan2(lateralSpeed, math.max(forwardSpeed.abs(), 1.5));
    _slipRatio = ((_wheelSpeed - forwardSpeed) /
            math.max(forwardSpeed.abs(), 3.0))
        .clamp(-1.0, 1.0);
  }

  void _applyTires(double dt, double limit, double forwardSpeed) {
    _force.setValues(
      tires.longitudinalAt(_slipRatio) * limit,
      // Negated: the tyre pushes back against the way the car is sliding.
      -tires.lateralAt(_slipAngle) * limit,
    );
    TireModel.clampToCircle(_force, limit);

    velocity
      ..addScaled(_forward, _force.x * dt)
      ..addScaled(_right, _force.y * dt);

    // And the same push, back through the tyre into the wheels that made it.
    // This is what turns a surface the tyres cannot use into wheelspin rather
    // than into speed: on ice the road takes back far less than the engine puts
    // in, and the surplus is wheels going nowhere.
    _wheelSpeed -= _force.x * tuning.wheelInertia * dt;

    // Under power, the wheels never turn slower than the road beneath them —
    // only a brake can drag a wheel back. Checked against the speed the car
    // leaves the step with rather than the one it arrived at, because that is
    // the pair anybody outside this method can see, and comparing across the
    // update lets the car finish a step ahead of the wheels that drove it.
    final leaving = velocity.dot(_forward);
    if (_underPower && _wheelSpeed < leaving) _wheelSpeed = leaving;
  }

  void _applyGravityAndDrag(double dt) {
    if (_grounded) {
      // Down the slope, not down the world: the part of gravity that would push
      // the car into the road is held by the road.
      _gravity.setValues(0.0, -tuning.gravity, 0.0);
      _gravity.addScaled(_normal, -_gravity.dot(_normal));
      velocity.addScaled(_gravity, dt);

      // And nothing into or out of the surface, which is what stops a car
      // gaining height across a crest and then falling back onto it.
      final into = velocity.dot(_normal);
      if (into < 0.0) velocity.addScaled(_normal, -into);
    } else {
      velocity.y -= tuning.gravity * dt;
    }

    final speedNow = speed;
    if (speedNow > 0.0) {
      velocity.addScaled(velocity, -tuning.airDrag * speedNow * dt);
    }
  }

  /// Moves the body, sliding along whatever it meets.
  ///
  /// Swept rather than stepped: at fifty metres a second a step covers most of a
  /// metre, and a car that moves in jumps that size goes through walls.
  void _move(double dt) {
    _delta
      ..setFrom(velocity)
      ..scale(dt);

    // Three attempts. Each contact takes the motion into the wall out of the
    // delta and lets the rest continue, which is what turns a head-on scrape
    // into sliding down the barrier rather than stopping dead against it.
    for (var attempt = 0; attempt < 3; attempt++) {
      if (_delta.length2 < 1e-12) break;
      _hit.reset();
      if (!world.sweep(collider.shape, position, _delta, _hit,
          ignore: collider)) {
        collider.position.add(_delta);
        break;
      }

      collider.position.addScaled(_delta, _hit.fraction);
      _delta.scale(1.0 - _hit.fraction);

      final into = _delta.dot(_hit.normal);
      if (into < 0.0) _delta.addScaled(_hit.normal, -into);

      final speedInto = velocity.dot(_hit.normal);
      if (speedInto < 0.0) {
        velocity.addScaled(_hit.normal, -speedInto);
        // **What the sweep used to throw away.** The speed driven into a wall
        // was taken out of the car and nothing was told: a scrape down a track
        // barrier threw sparks, and hitting one of the pillars the circuit is
        // measured against was silent and free. The car reports it and the game
        // decides what it looks like, which is the division `scrapedThisStep`
        // already keeps.
        _struck = math.max(_struck, -speedInto);
        _hurt(-speedInto);
      }
    }
  }

  /// Keeps the car on the track where the track says there is a wall.
  ///
  /// The barrier is the track's own, not a piece of geometry — see
  /// `TrackSpline`. A level that builds real walls out of brushes gets those
  /// through the sweep above instead, and a track may do both.
  /// How hard the barrier pushed back this step, in metres per second taken
  /// out of the car sideways. Zero on a clean lap.
  ///
  /// A step edge, so it is cleared at the top of every step and never saved:
  /// it says what happened, not what is. The game turns it into sparks and a
  /// scrape; the car only reports it, which is the same division `slipRatio`
  /// keeps.
  double get scrapedThisStep => _scraped;
  double _scraped = 0.0;

  /// How hard the car hit something solid this step, in metres per second taken
  /// out of it head-on. Zero on a clean lap.
  ///
  /// A step edge like [scrapedThisStep], and the other half of the same
  /// question: that one is the track's own barrier pushing the car back into
  /// the road, this one is geometry — a pillar, a wall a level built out of
  /// brushes, another car.
  double get struckThisStep => _struck;
  double _struck = 0.0;

  /// The harder of the two, which is what a game asks for.
  @override
  double get impactThisStep => math.max(_scraped, _struck);

  /// Adds the damage an impact of [speed] metres per second does.
  ///
  /// Public because the barrier is dealt with somewhere else and a game may
  /// have its own reasons to break a car; clamped here so that no caller can
  /// invent a car more than wrecked or less than fresh.
  void hurt(double speed) => _hurt(speed);

  void _hurt(double speed) {
    final past = speed - tuning.impactShrugged;
    if (past <= 0.0) return;
    damage = (damage + past * tuning.impactCost).clamp(0.0, 1.0);
  }

  /// Puts the car back together and puts the next set of tyres on it, if it is
  /// standing still.
  ///
  /// Returns whether it happened. **One idea rather than two**: a car that has
  /// stopped for repairs is a car that gets tyres, and a game with a key for
  /// each would be a game asking a driver to press two.
  ///
  /// The standstill is the whole price. Nothing about swapping a table of
  /// numbers mid-corner would go wrong mechanically, which is exactly the
  /// problem — a driver who could do it at speed would hold slicks down the
  /// straight and knobbly tyres through the gravel, and repair the car for
  /// free on the way past. Stopping costs the seconds that make it a choice.
  ///
  /// Half a metre a second rather than nought, because a car resting against a
  /// kerb is never quite still and a rule a player cannot satisfy is a rule
  /// they think is broken.
  bool pitStop(Tyres set) {
    if (speed > 0.5) return false;
    tyres = set;
    damage = 0.0;
    return true;
  }

  void _holdInsideBarrier() {
    if (!_ground.barrier || _ground.halfWidth <= 0.0) return;

    final over = _ground.lateral.abs() - _ground.halfWidth;
    if (over <= 0.0) return;

    final inward = _ground.lateral > 0.0 ? -1.0 : 1.0;
    collider.position.addScaled(_ground.lateralAxis, over * inward);
    _ground.lateral -= over * -inward;

    final into = velocity.dot(_ground.lateralAxis) * -inward;
    if (into > 0.0) {
      _scraped = into;
      velocity.addScaled(_ground.lateralAxis, into * inward);
      // The same speed taken out of a car by the same kind of wall. A barrier
      // that only threw sparks while a pillar broke the car would say the two
      // are different things, and to a driver arriving at either they are not.
      _hurt(into);
    }
  }

  /// Brings the body down to its ride height.
  ///
  /// Eased rather than snapped, so that a crest or a kerb is a movement and not
  /// a teleport. Frame-rate independent, which is not decoration: a suspension
  /// that settles faster on a faster machine is a car that grips differently on
  /// a faster machine.
  void _settle(double dt, bool found) {
    if (!found || !_grounded) return;
    final target = _ground.height + tuning.rideHeight;
    final blend = easeFactor(tuning.suspensionRate, dt);
    collider.position.y += (target - collider.position.y) * blend;
  }

  bool _underPower = false;
  final GroundSample _ground = GroundSample();
  final Vector3 _forward = Vector3(0.0, 0.0, 1.0);
  final Vector3 _right = Vector3(1.0, 0.0, 0.0);
  final Vector3 _up = Vector3(0.0, 1.0, 0.0);
  final Vector3 _normal = Vector3(0.0, 1.0, 0.0);
  final Vector3 _gravity = Vector3.zero();
  final Vector3 _delta = Vector3.zero();
  final Vector2 _force = Vector2.zero();
  final SweepHit _hit = SweepHit();
  final Matrix3 _basis = Matrix3.identity();
}
