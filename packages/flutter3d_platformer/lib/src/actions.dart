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
}
