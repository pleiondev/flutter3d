import 'game_action.dart';

/// One labelled button on a touch screen.
final class TouchAction {
  const TouchAction(this.action, this.label);

  final GameAction action;

  /// What is written on it. Short — a word does not fit on a thumb.
  final String label;
}
