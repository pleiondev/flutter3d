import 'package:flutter3d_game/flutter3d_game.dart';

/// What a player asks for that only a shooter has.
///
/// [GameAction] keeps the ones every game needs — moving, jumping, sprinting,
/// using the thing in front of you. `fire` was in there too, as a member of an
/// enum, which meant the engine's input layer knew that games shoot. It does
/// not any more: a platformer declares `dash` the same way this declares
/// `fire`, and neither of them has to ask the other's permission.
abstract final class ShooterActions {
  /// Held for automatic weapons, and its press edge drives the semi-automatic
  /// ones.
  static const GameAction fire = GameAction('fire');

  /// The other trigger, for a weapon that has one.
  ///
  /// **Its own action rather than a modifier on [fire]**, for the reason [fire]
  /// is its own action rather than a member of the engine's list: a player
  /// binds the two separately, and a pad puts them on two triggers that are
  /// both held at once. A weapon with one trigger simply never answers it —
  /// see `Arsenal.canFireAlternate`.
  static const GameAction altFire = GameAction('altFire');

  /// Fills the magazine, for a weapon that has one.
  ///
  /// Bound whether or not a game's weapons reload: `Arsenal.canReload` is
  /// false for every weapon without a magazine, so the action is simply never
  /// answered and a game does not have to know which of its weapons are which.
  static const GameAction reload = GameAction('reload');

  /// Held to crouch. Released to stand, if there is room to.
  ///
  /// This game's own rather than the engine's, for the reason the whole file
  /// exists: a racing game has no use for it, and `GameAction.jump` is in the
  /// engine only because every game with a body in it has one.
  static const GameAction crouch = GameAction('crouch');
}
