import 'package:vector_math/vector_math.dart';

import 'character_controller.dart';
import 'collider.dart';

/// Where a character's move ended, and what it met on the way.
///
/// **A class, not a record**: a [CharacterMover] written outside this
/// package builds one, and a field a later minor adds arrives here with a
/// default instead of breaking every mover.
final class CharacterMoved {
  /// Everything but [position], [grounded] and [velocity] defaults to
  /// nothing met: no wall, no ceiling, no step, no ground.
  CharacterMoved({
    required this.position,
    required this.grounded,
    required this.velocity,
    this.hitWall = false,
    this.hitCeiling = false,
    this.stepped = false,
    this.steppedUp = 0.0,
    Vector3? groundNormal,
    this.ground,
  }) : groundNormal = groundNormal ?? Vector3.zero();

  /// Where the move ended.
  final Vector3 position;

  /// Whether it ended on ground it can stand on.
  final bool grounded;

  /// Whether it met a wall on the way.
  final bool hitWall;

  /// Whether it met a ceiling on the way.
  final bool hitCeiling;

  /// Climbed a step to get there.
  final bool stepped;

  /// How far the step lifted it, m — a rise not travelled through, for a
  /// renderer to smooth; nought when it did not step.
  final double steppedUp;

  /// The velocity it moved with, less the speed into everything it met.
  final Vector3 velocity;

  /// The ground's normal, or zero in the air.
  final Vector3 groundNormal;

  /// What it stands on, or null in the air or on something the mover cannot
  /// name as a collider.
  final Collider? ground;
}

/// The geometry of a character's step, done elsewhere — P9: the physics core
/// moves a world's characters through what it mirrors of that world.
///
/// [CharacterController] keeps everything a step *decides* — speed,
/// friction, gravity, the jump, coyote time, being carried by a lift — and
/// hands one of these only the *where*: sliding along walls, climbing a
/// step, standing on a slope and keeping to the ground going down it. Set
/// on a world as `CollisionWorld.characterMover`, it moves every character
/// in it, except one whose `solidFilter` asks about each contact, which a
/// mover cannot answer and the controller's own sweeps can.
///
/// **Extended outside this package: an `abstract base class`** (decision 5
/// of `tasks/1.0-api-review.md`), so a member added in a minor arrives with a
/// default body and every implementation keeps compiling.
abstract base class CharacterMover {
  const CharacterMover();

  /// Moves the move's [CharacterMove.body] from where it is by its
  /// [CharacterMove.delta], as [CharacterMove] says.
  CharacterMoved move(CharacterMove move);
}

/// What [CharacterMover.move] is handed: move [body] from where it is by
/// [delta], sliding along what it meets and taking the speed into it out of
/// the body's velocity; standing on ground whose normal's height is at least
/// [walkableNormalY]; and, when [mayStep] — it stood on ground — climbing up
/// to [stepHeight] where that gets further than sliding does.
///
/// **One object, so a minor can hand a mover more** — a ceiling's height, a
/// slope's friction — without breaking a mover written against 1.0.
/// **Reused**: a controller owns one and sets it before every step, so a
/// step allocates nothing for it; a mover reads it during the call and does
/// not keep it.
final class CharacterMove {
  CharacterMove({
    required this.body,
    required this.delta,
    this.stepHeight = 0.0,
    this.walkableNormalY = 0.0,
    this.mayStep = false,
  });

  /// The character being moved.
  CharacterController body;

  /// How far it moves this step, m.
  Vector3 delta;

  /// The highest step it may climb, m.
  double stepHeight;

  /// The least height of a normal it can stand on.
  double walkableNormalY;

  /// Whether it may climb a step: it stood on ground.
  bool mayStep;
}
