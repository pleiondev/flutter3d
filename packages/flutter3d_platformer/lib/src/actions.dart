import 'package:flutter3d_game/flutter3d_game.dart';

/// What a player asks for that only a platformer has.
///
/// One action, and it is the reason [GameAction] stopped being an enum: there
/// was no way to write this line without editing the engine.
abstract final class PlatformerActions {
  /// A burst along the ground or through the air, on the press edge.
  ///
  /// Not held. A dash you can hold is a second walk speed, and the whole point
  /// of it is that spending it costs something.
  static const GameAction dash = GameAction('dash');

  /// Fall through the one-way platform underfoot.
  ///
  /// Its own action rather than "down plus jump", because in a third-person
  /// game with a free camera there is no down: the stick is read against the
  /// camera and pushing it towards yourself means walking backwards. It is
  /// bound to the crouch key, which is where a player will look for it and
  /// which is what it becomes when crouching exists.
  static const GameAction dropThrough = GameAction('dropThrough');
}
