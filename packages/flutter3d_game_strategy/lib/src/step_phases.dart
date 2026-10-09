import 'package:flutter3d_sim/flutter3d_sim.dart';

/// The strategy's own moments inside its step, where a game hangs a rule
/// on `StrategySimulation.systems` — as every genre has, with the two every
/// genre shares, `StepPhase.begin` and `StepPhase.end`.
///
/// **Points the step announces, in this order**, after `begin`: the orders
/// given are carried out, the crowd has worked and walked, the fight is
/// settled, and the halls have produced. The step's own order is the genre's
/// and a recorded match is that order, so a rule runs at one of these points
/// and never between them.
abstract final class StrategyPhases {
  /// The orders given since the last step have been obeyed: every unit knows
  /// what it is doing this step, and nothing has moved yet.
  static const StepPhase afterOrders = StepPhase('afterOrders');

  /// The crowd has worked its seams and walked: where a rule about where a
  /// unit stands belongs.
  static const StepPhase afterMoves = StepPhase('afterMoves');

  /// The shots of the step are fired (`StrategySimulation.shots`), the
  /// crowd shoved apart and the dead buried.
  static const StepPhase afterFight = StepPhase('afterFight');

  /// The halls have produced what they were making. Before the fog is
  /// refreshed, which is the last thing the step does.
  static const StepPhase afterProduction = StepPhase('afterProduction');
}
