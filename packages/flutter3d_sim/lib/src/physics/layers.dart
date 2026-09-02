import 'package:flutter3d_physics/flutter3d_physics.dart';

/// What each collision bit means in a game of this shape.
///
/// The names live here and not in `flutter3d_physics` because a collision world
/// that knows what a monster is cannot be used by a game that has none. The
/// physics package keeps the rule — two colliders meet when each is in the
/// other's mask — and [Layers.all], which means the same thing everywhere.
///
/// **These five are a default, and thirteen places in this package read them.**
/// That sentence used to end "nothing in either package reads these names",
/// which stopped being true and was the most expensive kind of comment: it
/// invited a game to "declare its own set and ignore this one", and a game that
/// did would silently lose camera wall-avoidance ([CameraRig.wallMask]), the
/// push a mover gives what it carries ([Mover]), the ground an actor stands on
/// ([ActorSystem]) and the layer every unlabelled brush in every level is built
/// on (`levelCollision`) — four systems, all failing as "the physics feels
/// wrong" rather than as an error.
///
/// So: a game with vehicles or water **adds** bits, and the bits below stay
/// what they are. Bit three is free — see [reserved] — and a set of one's own
/// means passing `layer:` and `mask:` at every one of those thirteen places,
/// which is a thing to do deliberately rather than by ignoring a default.
///
/// Two of the original six are absent. `projectile` and `solid` — the latter
/// being `world | player | actor` — had no user anywhere in the workspace, so
/// the extraction deleted them rather than carrying them across.
abstract final class CollisionLayers {
  /// Level geometry. Bit zero, which is also `Collider`'s default layer.
  static const int world = 1 << 0;

  /// The player's body. Bit one, which is also `CharacterController`'s default.
  static const int player = 1 << 1;

  /// A body that is not the player's: a guard, a monster, a rival's car.
  ///
  /// **Called `actor` and not `monster`**, which it was until the word list in
  /// `test/no_genre_test.dart` was written and fired on this very file — whose
  /// own doc comment, four lines up, says that a collision world knowing what a
  /// monster is cannot be used by a game that has none. It knew. The bit is the
  /// same bit; what changed is that the engine now names the mechanism, and the
  /// fiction stays in `flutter3d_game_shooter`.
  static const int actor = 1 << 2;

  /// A volume that gives something up when it is walked into.
  ///
  /// Kept, deliberately, where `monster` was not: this names what the volume
  /// *does*, and every genre in the workspace has one. See the note on the word
  /// list about where that line is drawn.
  static const int pickup = 1 << 4;

  /// A volume that causes something when it is walked into.
  static const int trigger = 1 << 5;

  /// Bit three, which nothing uses.
  ///
  /// **Named because the gap was not.** The list jumps from `actor` at two to
  /// `pickup` at four, and the doc above tells an extender to add bits "six
  /// upwards" — so one person filling the hole and another following the
  /// instructions produce two different bits meaning two different things, and
  /// the collision they cause is between a pickup and a piece of scenery rather
  /// than in the source.
  ///
  /// It is a real free bit and it is available. Taking it is a change to this
  /// file, which is the point of it having a name.
  static const int reserved = 1 << 3;

  /// Every bit, forwarded so a call site needs only one of these two classes.
  static const int all = Layers.all;
}
