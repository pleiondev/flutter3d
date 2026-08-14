import 'package:flutter3d_physics/flutter3d_physics.dart';

/// What each collision bit means in a game of this shape.
///
/// The names live here and not in `flutter3d_physics` because a collision world
/// that knows what a monster is cannot be used by a game that has none. The
/// physics package keeps the rule — two colliders meet when each is in the
/// other's mask — and [Layers.all], which means the same thing everywhere.
///
/// **These five are a default, not a law.** A game with vehicles or water adds
/// bits six upwards, or declares its own set and ignores this one; nothing in
/// either package reads these names.
///
/// Two of the original six are absent. `projectile` and `solid` — the latter
/// being `world | player | monster` — had no user anywhere in the workspace, so
/// the extraction deleted them rather than carrying them across.
abstract final class CollisionLayers {
  /// Level geometry. Bit zero, which is also `Collider`'s default layer.
  static const int world = 1 << 0;

  /// The player's body. Bit one, which is also `CharacterController`'s default.
  static const int player = 1 << 1;

  static const int monster = 1 << 2;
  static const int pickup = 1 << 4;
  static const int trigger = 1 << 5;

  /// Every bit, forwarded so a call site needs only one of these two classes.
  static const int all = Layers.all;
}
