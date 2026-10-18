import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// The strategy's own moments inside its step, where a game hangs a rule
/// through `StrategySimulation.addSystem`, as it does in every genre.
///
/// **Points the step announces, in this order**: the top of the step, the
/// orders given are carried out, the crowd has worked and walked, the fight
/// is settled, the halls have produced, and the bottom. The step's own order
/// is the genre's and a recorded match is that order, so a rule runs at one
/// of these points and never between them.
///
/// **Phases of the loop's kind** (`LoopPhase.step`), named for the genre, so
/// a system written for a loop phase is written the same way for one of
/// these: it is handed a `LoopContext` either way.
abstract final class StrategyPhases {
  /// The top of the step, before the orders are obeyed.
  static const LoopPhase begin = LoopPhase.step('strategy.begin');

  /// The orders given since the last step have been obeyed: every unit knows
  /// what it is doing this step, and nothing has moved yet.
  static const LoopPhase afterOrders = LoopPhase.step('strategy.afterOrders');

  /// The crowd has worked its seams and walked: where a rule about where a
  /// unit stands belongs.
  static const LoopPhase afterMoves = LoopPhase.step('strategy.afterMoves');

  /// The shots of the step are fired (`StrategySimulation.shots`), the
  /// crowd shoved apart and the dead buried.
  static const LoopPhase afterFight = LoopPhase.step('strategy.afterFight');

  /// The halls have produced what they were making. Before the fog is
  /// refreshed.
  static const LoopPhase afterProduction = LoopPhase.step(
    'strategy.afterProduction',
  );

  /// The bottom, after the fog and `StrategySimulation.afterStep`.
  static const LoopPhase end = LoopPhase.step('strategy.end');

  /// Every phase, in the order the step reaches them.
  static const List<LoopPhase> all = <LoopPhase>[
    begin,
    afterOrders,
    afterMoves,
    afterFight,
    afterProduction,
    end,
  ];
}
