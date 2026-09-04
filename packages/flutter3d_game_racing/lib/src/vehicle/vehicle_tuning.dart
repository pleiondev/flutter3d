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
    this.rollingResistance = 0.9,
    this.holdSpeed = 0.7,
    this.holdSlope = 1.2,
    this.airDrag = 0.0006,
    this.slipstream = 0.34,
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

  /// How much of the air drag a car in a perfect tow escapes, from nought to
  /// one.
  ///
  /// **A third, and that is a decision rather than a measurement.** A real
  /// slipstream is worth more than that and would make the tow irresistible:
  /// on a circuit where the cars are close, anything above about a half turns
  /// every straight into a rubber band and the driver in front cannot defend.
  /// A third is enough to be felt on a long straight and not enough to hand
  /// the place over.
  final double slipstream;

  /// How hard a coasting car slows down, in metres per second squared.
  ///
  /// Rolling resistance: tyres deforming, bearings turning, a transmission
  /// spinning. [airDrag] cannot stand in for it — drag goes as the square of the
  /// speed, so at walking pace it is almost nothing, and a car nudged to 3 m/s
  /// on the flat kept 2.9 of it.
  final double rollingResistance;

  /// Below this speed a coasting car on a gentle slope is held still, in metres
  /// per second.
  final double holdSpeed;

  /// The steepest slope that hold covers, as the acceleration along it in metres
  /// per second squared.
  ///
  /// **This pair is what a real car's handbrake, gearbox and static friction do
  /// between them**, and without it the starting grid was a hill nobody could
  /// park on: `ring.json` rises about one in fifty under the grid, so a driver
  /// who touched nothing rolled backwards and kept gaining — 4 m/s after ten
  /// seconds, which reads as the physics being broken rather than as a slope.
  ///
  /// 1.2 covers about one in eight. Past that a car left alone rolls, which it
  /// has to: a hold with no ceiling is a handbrake that is always on, and a
  /// circuit with a drop into a gully would have cars parked on its wall.
  final double holdSlope;

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
