/// How this game's jump feels, which is most of how the game feels.
final class RunnerTuning {
  const RunnerTuning({
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
