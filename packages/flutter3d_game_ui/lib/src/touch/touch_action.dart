import 'package:flutter3d_sim/flutter3d_sim.dart';

/// One labelled button on a touch screen.
final class TouchAction {
  const TouchAction(this.action, this.label);

  /// A button for [action] labelled as [actions] declares it — so the word
  /// on the thumb and the word in the rebinding screen are one word.
  factory TouchAction.declared(ActionSet actions, GameAction action) =>
      TouchAction(
        action,
        actions.declarationOf(action)?.displayName ?? action.name,
      );

  final GameAction action;

  /// What is written on it. Short — a word does not fit on a thumb.
  final String label;
}
