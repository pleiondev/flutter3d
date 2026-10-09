import 'package:flutter3d_sim/flutter3d_sim.dart';

/// What a strategy declares as actions: nothing, and on purpose.
///
/// **A strategy is played by orders, not by a stick.** A pointer selects and
/// a pointer sends, and what reaches the simulation is a `StrategyOrder`
/// through `OrderTunes`, recorded on an `OrderTape` — already a tape of
/// intents, with nothing device-shaped in it. The map camera is the view's,
/// moved by the pointer directly. So the set is empty, a rebinding screen
/// over it lists nothing, and the action map a strategy game builds holds
/// only what the game adds itself.
abstract final class StrategyActions {
  /// What a strategy game declares.
  static const ActionSet set = ActionSet('strategy', <ActionDeclaration>[]);
}
