import 'package:vector_math/vector_math.dart';

import 'character_controller.dart';
import 'collider.dart';

/// Where a character's move ended, and what it met on the way.
typedef CharacterMoved = ({
  Vector3 position,
  bool grounded,
  bool hitWall,
  bool hitCeiling,

  /// Climbed a step to get there.
  bool stepped,

  /// How far the step lifted it, m — a rise not travelled through, for a
  /// renderer to smooth; nought when it did not step.
  double steppedUp,

  /// The velocity it moved with, less the speed into everything it met.
  Vector3 velocity,

  /// The ground's normal, or zero in the air.
  Vector3 groundNormal,

  /// What it stands on, or null in the air or on something the mover cannot
  /// name as a collider.
  Collider? ground,
});

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

  /// Moves [body] from where it is by [delta], sliding along what it meets
  /// and taking the speed into it out of the body's velocity; standing on
  /// ground whose normal's height is at least [walkableNormalY]; and, when
  /// [mayStep] — it stood on ground — climbing up to [stepHeight] where that
  /// gets further than sliding does.
  CharacterMoved move(
    CharacterController body,
    Vector3 delta, {
    required double stepHeight,
    required double walkableNormalY,
    required bool mayStep,
  });
}
