/// How this game's jump feels, which is most of how the game feels.
final class RunnerSettings {
  const RunnerSettings({
    this.jumpSpeed = 9.5,
    this.airJumpSpeed = 8.2,
    this.airJumps = 1,
    this.jumpCut = 0.45,
    this.coyoteTime = 0.12,
    this.slopeSpeed = 0.34,
    this.glideFall = 4.0,
    this.glideAfter = 0.2,
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
    this.grip = 0.68,
  });

  /// A copy with the given fields replaced.
  RunnerSettings copyWith({
    double? jumpSpeed,
    double? airJumpSpeed,
    int? airJumps,
    double? jumpCut,
    double? coyoteTime,
    double? slopeSpeed,
    double? glideFall,
    double? glideAfter,
    double? dropThroughTime,
    double? stompBounce,
    double? stompBounceHeld,
    double? crouchHeight,
    double? crouchSpeed,
    double? slideSpeed,
    double? slideTime,
    double? slideFriction,
    double? longJumpUp,
    double? longJumpPush,
    double? poundSpeed,
    double? jumpBufferTime,
    double? dashSpeed,
    double? dashCooldown,
    double? dashDrag,
    double? turnRate,
    double? wallProbe,
    double? wallSlideSpeed,
    double? wallJumpUp,
    double? wallJumpPush,
    double? wallCoyoteTime,
    double? mantleLow,
    double? mantleHigh,
    double? mantleReach,
    double? grip,
  }) => RunnerSettings(
    jumpSpeed: jumpSpeed ?? this.jumpSpeed,
    airJumpSpeed: airJumpSpeed ?? this.airJumpSpeed,
    airJumps: airJumps ?? this.airJumps,
    jumpCut: jumpCut ?? this.jumpCut,
    coyoteTime: coyoteTime ?? this.coyoteTime,
    slopeSpeed: slopeSpeed ?? this.slopeSpeed,
    glideFall: glideFall ?? this.glideFall,
    glideAfter: glideAfter ?? this.glideAfter,
    dropThroughTime: dropThroughTime ?? this.dropThroughTime,
    stompBounce: stompBounce ?? this.stompBounce,
    stompBounceHeld: stompBounceHeld ?? this.stompBounceHeld,
    crouchHeight: crouchHeight ?? this.crouchHeight,
    crouchSpeed: crouchSpeed ?? this.crouchSpeed,
    slideSpeed: slideSpeed ?? this.slideSpeed,
    slideTime: slideTime ?? this.slideTime,
    slideFriction: slideFriction ?? this.slideFriction,
    longJumpUp: longJumpUp ?? this.longJumpUp,
    longJumpPush: longJumpPush ?? this.longJumpPush,
    poundSpeed: poundSpeed ?? this.poundSpeed,
    jumpBufferTime: jumpBufferTime ?? this.jumpBufferTime,
    dashSpeed: dashSpeed ?? this.dashSpeed,
    dashCooldown: dashCooldown ?? this.dashCooldown,
    dashDrag: dashDrag ?? this.dashDrag,
    turnRate: turnRate ?? this.turnRate,
    wallProbe: wallProbe ?? this.wallProbe,
    wallSlideSpeed: wallSlideSpeed ?? this.wallSlideSpeed,
    wallJumpUp: wallJumpUp ?? this.wallJumpUp,
    wallJumpPush: wallJumpPush ?? this.wallJumpPush,
    wallCoyoteTime: wallCoyoteTime ?? this.wallCoyoteTime,
    mantleLow: mantleLow ?? this.mantleLow,
    mantleHigh: mantleHigh ?? this.mantleHigh,
    mantleReach: mantleReach ?? this.mantleReach,
    grip: grip ?? this.grip,
  );

  /// The coefficient of friction between the runner's soles and the floor:
  /// the most the feet can push along the ground is this times what presses
  /// them onto it.
  ///
  /// **The legs push no harder than the grip.** The controller accelerates
  /// at `MovementSettings.groundAcceleration`, 70 m/s² on plain ground, and a
  /// sole can only push along a floor what friction gives it, μ times the
  /// weight on it, or the foot slips. On dry ground that is μ g, and in
  /// water the weight on the feet is less by what the water holds up — the
  /// runner's `Runner.lift` — so the push is μ g (1 − lift). The controller
  /// accelerates at the smaller of the two.
  ///
  /// 0.68 is the lowest available coefficient of friction Pollard, Heberger
  /// and Dempsey measured for a boot sole on a dry walkway with an
  /// articulated-strut tribometer, the rest of their dry boot figures lying
  /// between 0.71 and beyond the instrument's 1.0 (Slip potential for
  /// commonly used inclined grated metal walkways, IIE Transactions on
  /// Occupational Ergonomics and Human Factors 3(2):115–126, 2015, table
  /// 1): the grip a level's floor can be counted on to give. Steady running
  /// uses far less, a utilised coefficient of 0.23 in running shoes (Lee,
  /// Kim, Kim, Kong and Lee, Acta of Bioengineering and Biomechanics
  /// 13(3):55–61, 2011), so what the grip limits is getting up to speed and
  /// turning, which is where the controller's 70 m/s² was.
  ///
  /// **This changes running on dry ground.** Under the run's gravity of
  /// 24 m/s², μ g is 16.3 m/s², less than a quarter of the controller's 70:
  /// a walk is reached in 0.37 s rather than 0.09 s and a sprint in 0.61 s
  /// rather than 0.14 s. A floor whose own acceleration is already lower —
  /// ice, at 12 — is unchanged. Zero or less leaves the controller's
  /// acceleration as it is, the old behaviour exactly.
  final double grip;

  /// How fast a jump leaves the ground, in metres per second.
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
  /// A 0..1 fraction the upward speed is multiplied by.
  final double jumpCut;

  /// How long after walking off a ledge a jump still counts.
  /// In seconds.
  final double coyoteTime;

  /// How much faster a runner goes straight downhill, and slower straight up,
  /// as a fraction of its speed on the flat.
  ///
  /// **Slopes were walkable and made no difference.** The controller refuses
  /// anything too steep to stand on and treats everything else as level, so a
  /// ramp cost nothing to climb and gave nothing back coming down — which is
  /// most of what a ramp is for.
  ///
  /// **Speed rather than a push, and that is not a shortcut.** The first
  /// version added an acceleration along the surface and moved the runner
  /// exactly nowhere: the controller bleeds unrequested horizontal speed off
  /// at [CharacterTuning.groundFriction], which is several times any push a
  /// walkable slope could justify. That is right — a person does not slide
  /// down a ramp they can stand on — and it means a slope in a platformer has
  /// to be about how hard it is to *run* up, which is what it is about
  /// anyway.
  ///
  /// Scaled by how tilted the ground is and by how directly the runner is
  /// going up or down it, so traversing a slope sideways costs nothing. A
  /// third at the steepest walkable ramp is noticeable without turning a hill
  /// into a wall. Zero is the old behaviour exactly.
  final double slopeSpeed;

  /// The fastest a runner falls while gliding, in metres a second. Zero
  /// switches gliding off.
  ///
  /// **Held, and only on the way down.** The jump is already cut short by
  /// releasing the button ([jumpCut]), so holding it on the way *up* means
  /// "the full jump" and cannot also mean "glide" without the two fighting.
  /// After the apex the button is free to mean something else, which is what
  /// every platformer that has both does.
  ///
  /// Four is about a third of terminal velocity: slow enough to cross a gap
  /// that a jump cannot, fast enough that a player still has to aim.
  final double glideFall;

  /// How long after leaving the ground a glide may begin, in seconds.
  ///
  /// **Not immediately**, or a held jump button turns every jump into a float
  /// and the arc of a jump — the thing a platformer is made of — stops
  /// existing. A fifth of a second is past the apex of a short hop and well
  /// inside a long one.
  final double glideAfter;

  /// How long before landing a jump can be asked for and still happen.
  /// In seconds.
  final double jumpBufferTime;

  /// How fast a dash throws the runner, in metres per second.
  final double dashSpeed;

  /// How long before the next dash, in seconds.
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

  /// How fast a wall jump throws the runner upwards, in metres per second.
  final double wallJumpUp;

  /// How hard a wall jump throws the runner away from the wall.
  ///
  /// Away is not optional. A wall jump that only goes up lets a player climb
  /// one wall for ever by holding into it, which turns a chimney into a ladder
  /// and every level's ceiling into a suggestion.
  /// In metres per second.
  final double wallJumpPush;

  /// How long after leaving a wall a wall jump still counts. Coyote time again,
  /// for the same reason: the player pressed jump when they were on the wall.
  /// In seconds.
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

  /// The bounce while holding jump, in metres per second, as [stompBounce] is.
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
  /// In metres per second.
  final double crouchSpeed;

  /// The speed a slide starts at, whatever the runner was doing.
  ///
  /// Faster than a sprint, or nobody would slide; short-lived, or it would
  /// replace running.
  /// In metres per second.
  final double slideSpeed;

  /// How long a slide lasts before it becomes an ordinary crouch.
  /// In seconds.
  final double slideTime;

  /// How quickly a slide bleeds off. Low: a slide that stops in its own length
  /// is a stumble.
  /// A deceleration, in metres per second squared.
  final double slideFriction;

  /// Up and along, for the jump a slide can be cancelled into.
  ///
  /// Deliberately a low arc and a long one: the long jump crosses gaps a normal
  /// jump cannot and reaches ledges a normal jump can, which is what makes it
  /// worth learning rather than strictly better.
  /// Both in metres per second.
  final double longJumpUp;

  /// The speed along, in metres per second.
  final double longJumpPush;

  /// How fast a ground pound drives the runner down.
  ///
  /// Well past terminal velocity for a fall, because the point is that it
  /// arrives *now* and lands hard enough to break something.
  /// In metres per second.
  final double poundSpeed;

  /// The tallest ledge the runner can pull up onto.
  ///
  /// Deliberately under a single jump's 1.88 m: a mantle is for the ledge you
  /// *just* missed, and one that beat a jump outright would make jumping the
  /// slower way up.
  /// In metres above the runner's feet.
  final double mantleHigh;

  /// How far past the wall to look for the ledge's floor.
  /// In metres.
  final double mantleReach;
}
