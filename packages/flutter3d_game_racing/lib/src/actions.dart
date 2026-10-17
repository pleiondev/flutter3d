import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'headless.dart';

/// What a player asks a racing car for, as the genre reads it.
///
/// **The stick is the car**: [DualAxisAction.move] forward is the throttle,
/// back the brake, across the steering — see [RacingHeadlessGame] — and the
/// handbrake is the one button beside it. A game with pedals and a wheel of
/// its own declares those beside this set, as the racing demo does.
abstract final class RacingActions {
  /// The one button a driver has beside the stick.
  static const GameAction handbrake = RacingHeadlessGame.handbrake;

  /// What a racing game declares.
  static const ActionSet set = ActionSet('racing', <ActionDeclaration>[
    ActionDeclaration(DualAxisAction.move, label: 'drive', rebindable: false),
    ActionDeclaration(handbrake),
  ]);
}
