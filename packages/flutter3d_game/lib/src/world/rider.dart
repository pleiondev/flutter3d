/// Something standing on something else.
///
/// ## The bug this exists to fix
///
/// A `Mover` refuses to move into a body: a door that closes on the player is
/// a door that kills them through no mistake of theirs. The test for that asked
/// whether any body overlaps where the mover is about to be — and a passenger
/// standing on a rising lift overlaps exactly there, every step, for ever.
///
/// So no lift in the repository could move while anybody rode it. A `Lift`
/// reversed the moment a foot touched it; a `Platform`, which stalls rather
/// than reversing, simply stopped. The comment in the simulation's step order
/// about clearing kinematic deltas — *"a lift that has not moved yet cannot
/// carry you"* — described a mechanism that could never engage, because the
/// lift never moved.
///
/// Being in the way and being carried are different relationships, and nothing
/// could tell them apart. This is what tells them apart: a body standing **on**
/// the mover is a passenger, and a passenger is not an obstruction.
///
/// An interface rather than a type test in the mover, for the same reason
/// `Damageable` and `Gift` are: a game with a third thing that rides — a
/// vehicle, a crate, a monster on a conveyor — says so by implementing this,
/// and nothing in `world/` grows a switch over the kinds of thing there are.
library;

import 'package:flutter3d_physics/flutter3d_physics.dart';

abstract interface class Rider {
  /// What this is standing on, or null when it is standing on the level, in
  /// the air, or on nothing that moves.
  Collider? get carriedBy;
}
