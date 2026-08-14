/// The one file in this package that knows what a key is.
///
/// Two tests, not a table. Asserting that W maps to `moveForward` restates the
/// map it is reading and cannot fail for any reason worth knowing about; these
/// two cover the decisions the file makes *around* the map, both of which have
/// a comment explaining a bug they prevent.
library;

import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mouse_capture/mouse_capture.dart';

/// A pointer capture that does nothing and can be told to change its mind.
final class _FakeCapture extends MouseCapturePlatform {
  final StreamController<CaptureState> _states =
      StreamController<CaptureState>.broadcast();

  @override
  bool get isSupported => true;

  @override
  Stream<Offset> get deltas => const Stream<Offset>.empty();

  @override
  Stream<CaptureState> get stateChanges => _states.stream;

  @override
  Future<void> capture() async => _states.add(CaptureState.captured);

  @override
  Future<void> release() async => _states.add(CaptureState.released);

  @override
  Future<void> reset() async {}
}

KeyDownEvent _down(LogicalKeyboardKey key) => KeyDownEvent(
      logicalKey: key,
      physicalKey: PhysicalKeyboardKey.keyW,
      timeStamp: Duration.zero,
    );

KeyRepeatEvent _repeat(LogicalKeyboardKey key) => KeyRepeatEvent(
      logicalKey: key,
      physicalKey: PhysicalKeyboardKey.keyW,
      timeStamp: Duration.zero,
    );

void main() {
  late _FakeCapture platform;
  late InputState state;
  late DesktopInput input;

  setUp(() {
    platform = _FakeCapture();
    MouseCapturePlatform.instance = platform;
    state = InputState();
    input = DesktopInput(state: state, capture: MouseCapture(platform: platform));
  });

  tearDown(() => input.dispose());

  test('a held key repeating does not latch a second press', () {
    // The comment on `handleKeyEvent` names the bug: "treating the repeat as a
    // fresh press would fire an automatic weapon at the keyboard's repeat rate
    // instead of the weapon's".
    //
    // Mutation: handle `KeyRepeatEvent` the way `KeyDownEvent` is handled.
    // This fails.
    input.handleKeyEvent(_down(LogicalKeyboardKey.keyW));
    expect(state.pressed(GameAction.moveForward), isTrue);
    state.endStep();

    input.handleKeyEvent(_repeat(LogicalKeyboardKey.keyW));

    expect(state.pressed(GameAction.moveForward), isFalse,
        reason: 'the auto-repeat produced a fresh press, so a semi-automatic '
            'weapon fires at the keyboard repeat rate');
    expect(state.held(GameAction.moveForward), isTrue,
        reason: 'and the key is still down, which the repeat says');
  });

  test('losing the pointer drops everything that was held', () async {
    // A key that was down when the window went away never sends its key-up, so
    // without this the player keeps walking forward after alt-tabbing.
    //
    // Mutation: drop the `state.clear()` in `_onCaptureChanged`. This fails.
    // Captured first, because `MouseCapture` forwards a *change* of state and
    // starts uncaptured — releasing something never held says nothing, which
    // is correct and is not what this test is about.
    await platform.capture();
    await Future<void>.delayed(Duration.zero);

    input.handleKeyEvent(_down(LogicalKeyboardKey.keyW));
    expect(state.held(GameAction.moveForward), isTrue);

    await platform.release();
    await Future<void>.delayed(Duration.zero);

    expect(state.held(GameAction.moveForward), isFalse,
        reason: 'the player is still walking into a wall after alt-tabbing');
  });

  test('gaining the pointer does not clear anything', () async {
    // The other half, and the reason the handler tests for `released` rather
    // than reacting to every change: capturing mid-game must not eat the key
    // the player is already holding.
    input.handleKeyEvent(_down(LogicalKeyboardKey.keyW));

    await platform.capture();
    await Future<void>.delayed(Duration.zero);

    expect(state.held(GameAction.moveForward), isTrue,
        reason: 'capturing the pointer ate a key the player was holding');
  });
}
