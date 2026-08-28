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
    this.floorSnapLength = 0.0,
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

  /// How far the feet are pulled down to keep a floor they already had.
  ///
  /// **Zero, which is a body that lets go of the ground at every stair edge.**
  /// [groundProbe] is eight centimetres and a 0.2 m step is not, so walking
  /// down a staircase the body is in free fall for the first few frames of
  /// every tread: a measured run down forty 0.2 m steps spent 116 of its 600
  /// steps airborne. Airborne is not cosmetic — it means air acceleration
  /// instead of ground friction, no step-up when something is in the way, a
  /// coyote timer draining, and whatever the game hangs off [CharacterController.isGrounded]
  /// flickering sixty times a second.
  ///
  /// Set it and the probe reaches this far instead — but **only when the feet
  /// were already on something and did not deliberately leave it**, which is
  /// the whole safety of the mechanism. A reach that also *found* ground would
  /// be a body that cannot fall and cannot jump; this one can only keep a
  /// contact it already had, and one step of not having it is enough to fall
  /// for good.
  ///
  /// **The cost, plainly: a drop shorter than this stops being a drop.** Step
  /// off a ledge this high and the body is placed on the floor below rather
  /// than falling to it, so the figure has to stay well under the shallowest
  /// hole a level means as a hole. A third of a metre carries a 0.2 m
  /// staircase; the shallowest pit anything in this repository authors is two
  /// metres down, so there is an order of magnitude of room between the two.
  /// A game that wants a genuine hop down a kerb wants a *smaller* number than
  /// its stair rise, not a bigger one.
  final double floorSnapLength;

  /// The same numbers with a few changed.
  ///
  /// Wanted the moment two things have an opinion about how a body moves at
  /// once — a floor that is ice *and* a body that is crouching. Without it the
  /// second one has to restate all thirteen numbers and silently loses whatever
  /// the first one said.
  MovementTuning copyWith({
    double? walkSpeed,
    double? sprintSpeed,
    double? groundAcceleration,
    double? groundFriction,
    double? airAcceleration,
    double? gravity,
    double? terminalVelocity,
    double? jumpSpeed,
    double? stepHeight,
    double? coyoteTime,
    double? jumpBufferTime,
    double? groundProbe,
    double? floorSnapLength,
  }) => MovementTuning(
    walkSpeed: walkSpeed ?? this.walkSpeed,
    sprintSpeed: sprintSpeed ?? this.sprintSpeed,
    groundAcceleration: groundAcceleration ?? this.groundAcceleration,
    groundFriction: groundFriction ?? this.groundFriction,
    airAcceleration: airAcceleration ?? this.airAcceleration,
    gravity: gravity ?? this.gravity,
    terminalVelocity: terminalVelocity ?? this.terminalVelocity,
    jumpSpeed: jumpSpeed ?? this.jumpSpeed,
    stepHeight: stepHeight ?? this.stepHeight,
    coyoteTime: coyoteTime ?? this.coyoteTime,
    jumpBufferTime: jumpBufferTime ?? this.jumpBufferTime,
    groundProbe: groundProbe ?? this.groundProbe,
    floorSnapLength: floorSnapLength ?? this.floorSnapLength,
  );
}
