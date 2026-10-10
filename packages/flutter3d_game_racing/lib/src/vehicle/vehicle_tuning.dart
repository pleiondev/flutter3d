/// The numbers that make one car feel different from another.
///
/// All in one place and all plain units, so that tuning a car is reading a
/// table rather than hunting through a step function — the same reason the
/// platformer's `MovementSettings` and `RunnerSettings` exist.
final class VehicleSettings {
  const VehicleSettings({
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
    this.impactShrugged = 6.0,
    this.impactCost = 0.017,
    this.powerLostWhenWrecked = 0.45,
    this.speedLostWhenWrecked = 0.25,
    this.groundStick = 0.45,
    this.suspensionRate = 18.0,
    this.slideAlignment = 2.2,
    this.wheelInertia = 0.25,
  });

  /// A copy with the given fields replaced.
  VehicleSettings copyWith({
    double? radius,
    double? rideHeight,
    double? maxSpeed,
    double? maxReverse,
    double? enginePush,
    double? brakeStrength,
    double? rollingDrag,
    double? rollingResistance,
    double? holdSpeed,
    double? holdSlope,
    double? airDrag,
    double? slipstream,
    double? maxSteer,
    double? steerFalloff,
    double? wheelBase,
    double? impactShrugged,
    double? impactCost,
    double? powerLostWhenWrecked,
    double? speedLostWhenWrecked,
    double? groundStick,
    double? suspensionRate,
    double? slideAlignment,
    double? wheelInertia,
  }) => VehicleSettings(
    radius: radius ?? this.radius,
    rideHeight: rideHeight ?? this.rideHeight,
    maxSpeed: maxSpeed ?? this.maxSpeed,
    maxReverse: maxReverse ?? this.maxReverse,
    enginePush: enginePush ?? this.enginePush,
    brakeStrength: brakeStrength ?? this.brakeStrength,
    rollingDrag: rollingDrag ?? this.rollingDrag,
    rollingResistance: rollingResistance ?? this.rollingResistance,
    holdSpeed: holdSpeed ?? this.holdSpeed,
    holdSlope: holdSlope ?? this.holdSlope,
    airDrag: airDrag ?? this.airDrag,
    slipstream: slipstream ?? this.slipstream,
    maxSteer: maxSteer ?? this.maxSteer,
    steerFalloff: steerFalloff ?? this.steerFalloff,
    wheelBase: wheelBase ?? this.wheelBase,
    impactShrugged: impactShrugged ?? this.impactShrugged,
    impactCost: impactCost ?? this.impactCost,
    powerLostWhenWrecked: powerLostWhenWrecked ?? this.powerLostWhenWrecked,
    speedLostWhenWrecked: speedLostWhenWrecked ?? this.speedLostWhenWrecked,
    groundStick: groundStick ?? this.groundStick,
    suspensionRate: suspensionRate ?? this.suspensionRate,
    slideAlignment: slideAlignment ?? this.slideAlignment,
    wheelInertia: wheelInertia ?? this.wheelInertia,
  );

  /// The body's collision radius. One sphere, because a car that is a box has
  /// corners, and a corner catching on a kerb at ninety metres a second is a
  /// car on its roof.
  final double radius;

  /// How far the body floats above the road.
  /// In metres.
  final double rideHeight;

  /// The fastest the wheels drive the car forwards, in metres per second.
  final double maxSpeed;

  /// The fastest they drive it backwards, in metres per second.
  final double maxReverse;

  /// How quickly the driven wheels spin up, in metres per second squared. Not
  /// the car's acceleration — how fast the *wheels* gain speed. What the car
  /// does about that is up to the tyres.
  final double enginePush;

  /// How quickly full brake slows the wheels, in metres per second squared.
  final double brakeStrength;

  /// How quickly the wheels fall back to the car's speed with nothing pressed:
  /// engine braking, near enough.
  /// In metres per second squared.
  final double rollingDrag;

  /// The air's drag on the car, per metre: the car loses airDrag · v² of
  /// speed a second at v metres a second — ½ρC_dA/m folded into one number,
  /// in standard air. It answers to the air the car drives through: in a
  /// world whose air is thinner or denser (`WorldProperties.airDensity`, or
  /// its medium's density), it scales by that density over the standard
  /// air's, so a race on a mountain pass runs freer.
  ///
  /// **Not what sets the top speed.** At [maxSpeed], 52 m/s, the default
  /// takes 1.6 m/s² — a tenth of what the engine pushes with — so the car
  /// reaches its top speed where the wheels stop being driven faster, which
  /// is the clamp in [maxSpeed]; drag shapes how it gets there and how hard
  /// a tow ([slipstream]) helps.
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
  /// spinning. **Not the physics core's coefficient**: the core's wheel
  /// (`F3D_WHEEL_ROLLING_DEFAULT`, 0.015) is a coefficient C_rr, a force
  /// over the load, which slows a car by C_rr · g — 0.29 m/s² at this
  /// game's 20 m/s², 0.15 on the Earth. This is the deceleration itself,
  /// and three times the core's at 20 m/s² because it stands for the
  /// driveline as well as the tyres. [airDrag] cannot stand in for it — drag goes as the square of the
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
  /// In metres per second.
  final double steerFalloff;

  /// Front axle to rear axle. Sets how quickly steering turns the car.
  /// In metres.
  final double wheelBase;

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
  /// In metres.
  final double groundStick;

  /// How quickly the body settles to its ride height. Stands in for suspension
  /// until there is suspension.
  /// A rate per second, eased over each step.
  final double suspensionRate;

  /// How strongly a slide pulls the nose round with it.
  ///
  /// A car sliding sideways is turned by the air and by its own tyres, and
  /// without something standing in for that the nose only ever moves where the
  /// steering puts it — which makes a spin impossible and a caught slide
  /// unsatisfying.
  /// Per second: radians per second of yaw for each radian of slip angle.
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
