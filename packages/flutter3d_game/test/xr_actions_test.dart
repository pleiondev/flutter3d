/// A headset's controllers drive a game's actions through its action map,
/// as a pad and a keyboard do.
///
///     flutter test test/xr_actions_test.dart
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

const DualAxisAction _walk = DualAxisAction('walk');
const AxisAction _throttle = AxisAction('throttle');

final InputSource _trigger = InputSource.xr(XrHand.right, XrControl.trigger);
final InputSource _stick = InputSource.xr(XrHand.left, XrControl.thumbstick);
final InputSource _squeeze = InputSource.xr(XrHand.left, XrControl.squeeze);

/// The trigger jumps, the left stick walks, the left squeeze is a throttle.
ActionMap _map() {
  final map = ActionMap(
    actions: ActionSet.common,
    axes: <ActionBinding>[
      DualAxisBinding(_walk, _stick),
      AxisBinding(_throttle, _squeeze),
    ],
  );
  map.buttons.bind(_trigger, GameAction.jump);
  return map;
}

void main() {
  test('an XR control is spelled as the session writes it', () {
    // Mutation: spell it apart from `XrActionSource.sourceId`. A rebinding
    // saved from one would name a control the other never reports.
    expect(
      _trigger.id,
      XrActionSource.sourceId(XrHand.right, XrControl.trigger),
    );
    expect(_trigger.id, 'xr:right/trigger');
    expect(_trigger.device, 'xr');
  });

  test('a frame of controls presses, pushes and pulls the bound actions', () {
    final state = InputState();
    final input = ActionInput(state: state, map: _map());
    // Mutation: drop the button path from `xrControls`. The trigger walks
    // and pulls through the map and never jumps, since no device of this
    // package presses an XR control's buttons.
    input.xrControls(<String, XrControlReading>{
      _trigger.id: const XrControlReading(pressed: true, value: 1.0),
      _stick.id: const XrControlReading(x: 0.25, y: -0.5),
      _squeeze.id: const XrControlReading(value: 0.75),
      'xr:left/menu': const XrControlReading(pressed: true),
    });
    expect(state.held(GameAction.jump), isTrue);
    expect(state.pressed(GameAction.jump), isTrue);
    expect(state.dualAxis(_walk).x, 0.25);
    expect(state.dualAxis(_walk).y, -0.5);
    expect(state.axis(_throttle), 0.75);

    // Let go of the trigger: released on the edge, once.
    input.xrControls(<String, XrControlReading>{
      _trigger.id: const XrControlReading(),
    });
    expect(state.held(GameAction.jump), isFalse);
  });

  test('letting go releases what the controllers held', () {
    final state = InputState();
    final input = ActionInput(state: state, map: _map())
      ..xrControls(<String, XrControlReading>{
        _trigger.id: const XrControlReading(pressed: true),
        _stick.id: const XrControlReading(x: 1.0),
      });
    // Mutation: clear only the axes in `letGo`. A session that ends with
    // the trigger down leaves the player jumping for ever.
    input.letGo();
    expect(state.held(GameAction.jump), isFalse);
    expect(state.dualAxis(_walk).x, 0.0);
  });
}
