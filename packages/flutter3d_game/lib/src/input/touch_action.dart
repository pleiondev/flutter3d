import 'package:flutter3d_sim/flutter3d_sim.dart';

/// One labelled button on a touch screen.
final class TouchAction {
  const TouchAction(this.action, this.label);

  final GameAction action;

  /// What is written on it. Short — a word does not fit on a thumb.
  final String label;
}
