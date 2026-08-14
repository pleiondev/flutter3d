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
}
