/// The pad translated into actions, without a pad.
///
///     flutter test test/pad_input_test.dart
///
/// The device package draws the line: everything below the platform channel
/// needs a controller in hand and is checked by a person, and everything above
/// it is arithmetic and edges — which is all of this file. What it is guarding
/// is mostly the interaction between two devices, because that is where a
/// translator goes wrong in a way a player notices and a screenshot does not:
/// a pad that releases the keyboard's keys, a trigger that shadows `W` for the
/// rest of the process, a view that turns further on a slower machine.
library;

import 'dart:async';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamepad/gamepad.dart';
import 'package:vector_math/vector_math.dart';

/// A gamepad that does whatever the test says.
final class FakePad extends GamepadPlatform {
  final PadSnapshot state = PadSnapshot()..connected = true;
  final StreamController<PadConnection> _connections =
      StreamController<PadConnection>.broadcast();

  @override
  bool get isSupported => true;

  @override
  Stream<PadConnection> get connectionChanges => _connections.stream;

  @override
  void read(PadSnapshot out) => out.copyFrom(state);

  @override
  Future<void> dispose() async => _connections.close();
}

/// A pad with no dead zone, so a test can name the number it expects.
///
/// The dead zone has its own tests in the device package; mixing it in here
/// would mean every expectation below carried a rescale nobody asked about.
Gamepad _bare(FakePad fake) =>
    Gamepad(platform: fake, deadzone: const Deadzone(stick: 0.0, trigger: 0.0));

void main() {
  const dash = GameAction('dash');
  const throttle = GameAction('throttle');
  const steerLeft = GameAction('steerLeft');
  const steerRight = GameAction('steerRight');

  group('a stick', () {
    test('half over asks for half, not for everything', () {
      // `flutter3d_shooter`'s own test calls this "half a deflection is half a
      // wish": a stick pushed halfway walks, and a translator that ran it
      // through press/held would make it run.
      final fake = FakePad()..state.setAxis(PadAxis.leftStickY, -0.5);
      final input = InputState();
      PadInput(state: input, pad: _bare(fake)).tick(1 / 60);

      expect(input.moveAxis.y, closeTo(0.5, 1e-9));
    });

    test('and pushing it up walks forward', () {
      // A pad reports Y positive downwards — Apple's convention and the
      // browser's. The flip belongs in the open, and this is the test that says
      // which way round it goes.
      final fake = FakePad()..state.setAxis(PadAxis.leftStickY, -1.0);
      final input = InputState();
      PadInput(state: input, pad: _bare(fake)).tick(1 / 60);

      expect(input.moveAxis.y, closeTo(1.0, 1e-9));
    });

    test('plus the keyboard is one, not 1.41', () {
      // The oldest speed exploit there is, and the reason `_recomputeMoveAxis`
      // clamps. A player with a hand on each device must not go faster.
      final fake = FakePad()..state.setAxis(PadAxis.leftStickY, -1.0);
      final input = InputState()..press(GameAction.moveRight);
      PadInput(state: input, pad: _bare(fake)).tick(1 / 60);

      expect(input.moveAxis.length, closeTo(1.0, 1e-6));
    });

    test('and a stick routed to nothing never touches the axis', () {
      // A racing game steers with it. If the translator wrote the movement axis
      // anyway, the car would also be walking.
      final fake = FakePad()..state.setAxis(PadAxis.leftStickX, 1.0);
      final input = InputState();
      PadInput(
        state: input,
        pad: _bare(fake),
        routes: PadRoutes.driving(steerLeft: steerLeft, steerRight: steerRight),
      ).tick(1 / 60);

      expect(input.moveAxis.x, 0.0);
    });
  });

  group('the right stick', () {
    test('is a rate, so the view turns by the same amount either frame rate',
        () {
      // **The reason `tick` takes `dt` at all.** `addLook` accumulates a
      // displacement and a stick reports a speed, so somebody has to integrate,
      // and if nobody does the camera turns further on a faster machine — which
      // is the same class of bug the fixed step exists to prevent.
      final fake = FakePad()..state.setAxis(PadAxis.rightStickX, 1.0);
      final input = InputState();
      final routes = PadRoutes(lookRate: 1000.0);

      final whole = Vector2.zero();
      PadInput(state: input, pad: _bare(fake), routes: routes)
        ..tick(0.5)
        ..drainLook(whole);

      final halves = Vector2.zero();
      PadInput(state: input, pad: _bare(fake), routes: routes)
        ..tick(0.25)
        ..tick(0.25)
        ..drainLook(halves);

      expect(whole.x, closeTo(500.0, 1e-9));
      expect(halves.x, closeTo(whole.x, 1e-9));
    });

    test('and draining adds to the mouse rather than replacing it', () {
      // The asymmetry with `DesktopInput.drainLook`, which assigns. `GameLoop`
      // takes one callback and the application composes the two, so moving both
      // devices at once has to turn the view by the sum — a pad that assigned
      // would silently swallow the mouse.
      final fake = FakePad()..state.setAxis(PadAxis.rightStickX, 1.0);
      final pad = PadInput(
        state: InputState(),
        pad: _bare(fake),
        routes: const PadRoutes(lookRate: 100.0),
      )..tick(1.0);

      final out = Vector2(7.0, 3.0);
      pad.drainLook(out);

      expect(out.x, closeTo(107.0, 1e-9));
      expect(out.y, closeTo(3.0, 1e-9));
    });

    test('and what has been drained is gone', () {
      final fake = FakePad()..state.setAxis(PadAxis.rightStickX, 1.0);
      final pad = PadInput(
        state: InputState(),
        pad: _bare(fake),
        routes: const PadRoutes(lookRate: 100.0),
      )..tick(1.0);

      final first = Vector2.zero();
      final second = Vector2.zero();
      pad
        ..drainLook(first)
        ..drainLook(second);

      expect(first.x, closeTo(100.0, 1e-9));
      expect(second.x, 0.0);
    });
  });

  group('a button', () {
    test('presses and releases what it is bound to', () {
      final fake = FakePad();
      final input = InputState();
      final pad = PadInput(state: input, pad: _bare(fake));

      fake.state.setDown(PadButton.faceSouth, down: true);
      pad.tick(1 / 60);
      expect(input.pressed(GameAction.jump), isTrue);
      expect(input.held(GameAction.jump), isTrue);

      input.endStep();
      fake.state.setDown(PadButton.faceSouth, down: false);
      pad.tick(1 / 60);
      expect(input.released(GameAction.jump), isTrue);
      expect(input.held(GameAction.jump), isFalse);
    });

    test('and holding it is not pressing it again', () {
      // A held button re-pressed every frame fires an automatic weapon at the
      // frame rate instead of the weapon's rate — the same thing
      // `DesktopInput` refuses to do with a key repeat.
      final fake = FakePad()..state.setDown(PadButton.faceSouth, down: true);
      final input = InputState();
      final pad = PadInput(state: input, pad: _bare(fake))..tick(1 / 60);

      input.endStep();
      pad.tick(1 / 60);

      expect(input.pressed(GameAction.jump), isFalse);
      expect(input.held(GameAction.jump), isTrue);
    });

    test('and two buttons on one action release it once, at the end', () {
      // Ordinary: a shoulder and a trigger both firing. Letting go of the first
      // must not stop the shot, and the naive `release` on every button up
      // does exactly that.
      final fake = FakePad();
      final input = InputState();
      final bindings = Bindings()
        ..bind(InputSource.pad(PadButton.shoulderLeft.id), dash)
        ..bind(InputSource.pad(PadButton.shoulderRight.id), dash);
      final pad = PadInput(state: input, pad: _bare(fake), bindings: bindings);

      fake.state
        ..setDown(PadButton.shoulderLeft, down: true)
        ..setDown(PadButton.shoulderRight, down: true);
      pad.tick(1 / 60);
      expect(input.held(dash), isTrue);

      fake.state.setDown(PadButton.shoulderLeft, down: false);
      pad.tick(1 / 60);
      expect(input.held(dash), isTrue,
          reason: 'the other button is still down');

      fake.state.setDown(PadButton.shoulderRight, down: false);
      pad.tick(1 / 60);
      expect(input.held(dash), isFalse);
    });

    test('and an unbound button does nothing at all', () {
      final fake = FakePad()..state.setDown(PadButton.guide, down: true);
      final input = InputState();
      PadInput(state: input, pad: _bare(fake)).tick(1 / 60);

      // The middle button belongs to the operating system, and a game that
      // steals it is a game that cannot be left.
      expect(input.held(GameAction.jump), isFalse);
      expect(input.slotRequest, isNull);
    });
  });

  group('a slot button', () {
    test('asks once per press, not once per frame', () {
      final fake = FakePad();
      final input = InputState();
      final pad = PadInput(
        state: input,
        pad: _bare(fake),
        slotButtons: PadInput.dpadSlots,
      );

      fake.state.setDown(PadButton.dpadRight, down: true);
      pad.tick(1 / 60);
      expect(input.slotRequest, 1);

      input.endStep();
      pad.tick(1 / 60);
      expect(input.slotRequest, isNull,
          reason: 'a held d-pad re-selected the slot every frame');
    });

    test('and it wins over what the button was bound to', () {
      // The d-pad walks by default and selects in a game that says so, exactly
      // as `DesktopInput` resolves the number row before the letters.
      final fake = FakePad()..state.setDown(PadButton.dpadUp, down: true);
      final input = InputState();
      PadInput(
        state: input,
        pad: _bare(fake),
        slotButtons: PadInput.dpadSlots,
      ).tick(1 / 60);

      expect(input.slotRequest, 0);
      expect(input.held(GameAction.moveForward), isFalse);
    });

    test('and by default the d-pad walks instead', () {
      final fake = FakePad()..state.setDown(PadButton.dpadUp, down: true);
      final input = InputState();
      PadInput(state: input, pad: _bare(fake)).tick(1 / 60);

      expect(input.moveAxis.y, closeTo(1.0, 1e-9));
      expect(input.slotRequest, isNull);
    });
  });

  group('a trigger', () {
    Bindings pedal() => Bindings()
      ..bind(InputSource.pad(PadButton.triggerRight.id), throttle);

    test('carries a magnitude, not just a bit', () {
      // What racing needed and could not have: `VehicleInput.throttle` is a
      // double, and the input layer could only answer one or nothing.
      final fake = FakePad()..state.setAxis(PadAxis.triggerRight, 0.42);
      final input = InputState();
      PadInput(state: input, pad: _bare(fake), bindings: pedal())
          .tick(1 / 60);

      expect(input.value(throttle), closeTo(0.42, 1e-6));
    });

    test('and does not chatter at the threshold', () {
      // **The mutation this exists for**: one threshold instead of two, and a
      // trigger resting against it sends a press and a release every frame — a
      // weapon firing at the frame rate.
      final fake = FakePad();
      final input = InputState();
      final pad = PadInput(state: input, pad: _bare(fake), bindings: pedal());

      fake.state.setAxis(PadAxis.triggerRight, 0.55);
      pad.tick(1 / 60);
      expect(input.held(throttle), isTrue);

      input.endStep();
      fake.state.setAxis(PadAxis.triggerRight, 0.45);
      pad.tick(1 / 60);
      expect(input.held(throttle), isTrue,
          reason: 'a dip below the press threshold released it, so the gap '
              'between pressing and releasing is not being used');
      expect(input.released(throttle), isFalse);

      fake.state.setAxis(PadAxis.triggerRight, 0.3);
      pad.tick(1 / 60);
      expect(input.held(throttle), isFalse);
    });

    test('at rest gives the keyboard the action back', () {
      // **The subtle one, and the reason `clearActionValue` exists.** A
      // magnitude present is authoritative, so a trigger that came home and
      // wrote nought would shadow `W` for the rest of the process: hold `W`,
      // brush a trigger once, and the throttle is dead until relaunch.
      final fake = FakePad()..state.setAxis(PadAxis.triggerRight, 0.8);
      final input = InputState()..press(throttle); // as if a key were down
      final pad = PadInput(state: input, pad: _bare(fake), bindings: pedal());

      pad.tick(1 / 60);
      expect(input.value(throttle), closeTo(0.8, 1e-6),
          reason: 'the trigger is what the player is moving');

      fake.state.setAxis(PadAxis.triggerRight, 0.0);
      pad.tick(1 / 60);
      expect(input.value(throttle), 1.0,
          reason: 'the key is still down, so full throttle');
      expect(input.held(throttle), isTrue);
    });
  });

  group('a stick routed to a pair of actions', () {
    test('asks for each side with its own magnitude', () {
      final fake = FakePad()..state.setAxis(PadAxis.leftStickX, 0.6);
      final input = InputState();
      PadInput(
        state: input,
        pad: _bare(fake),
        routes: PadRoutes.driving(steerLeft: steerLeft, steerRight: steerRight),
      ).tick(1 / 60);

      expect(input.value(steerRight), closeTo(0.6, 1e-6));
      expect(input.value(steerLeft), 0.0);
      expect(input.held(steerRight), isTrue, reason: '0.6 is past the press');
      expect(input.held(steerLeft), isFalse);
    });

    test('and the other way for the other sign', () {
      final fake = FakePad()..state.setAxis(PadAxis.leftStickX, -1.0);
      final input = InputState();
      PadInput(
        state: input,
        pad: _bare(fake),
        routes: PadRoutes.driving(steerLeft: steerLeft, steerRight: steerRight),
      ).tick(1 / 60);

      expect(input.value(steerLeft), closeTo(1.0, 1e-6));
      expect(input.value(steerRight), 0.0);
    });
  });

  group('losing the pad', () {
    test('releases what the pad held and nothing else', () {
      // **Never `InputState.clear()`.** The keyboard's keys are genuinely still
      // down: nothing produced a key-up, and dropping them means a player with
      // a hand on `W` stops walking because a battery died.
      final fake = FakePad()
        ..state.setDown(PadButton.faceSouth, down: true)
        ..state.setAxis(PadAxis.leftStickY, -1.0);
      final input = InputState()..press(GameAction.moveForward);
      final pad = PadInput(state: input, pad: _bare(fake))..tick(1 / 60);
      expect(input.held(GameAction.jump), isTrue);

      fake.state.disconnect();
      input.endStep();
      pad.tick(1 / 60);

      expect(input.held(GameAction.jump), isFalse);
      expect(input.released(GameAction.jump), isTrue);
      expect(input.held(GameAction.moveForward), isTrue,
          reason: 'the keyboard was holding this one');
      expect(input.moveAxis.y, closeTo(1.0, 1e-9),
          reason: 'the stick let go, the key did not');
      expect(pad.isConnected, isFalse);
    });

    test('and lets go of the throttle rather than leaving it where it was', () {
      // A pad whose battery dies mid-corner must not leave the car at full
      // speed. Half of this is the device package zeroing before it announces
      // itself; this half is the translator withdrawing the number.
      final fake = FakePad()..state.setAxis(PadAxis.triggerRight, 1.0);
      final input = InputState();
      final bindings = Bindings()
        ..bind(InputSource.pad(PadButton.triggerRight.id), throttle);
      final pad = PadInput(state: input, pad: _bare(fake), bindings: bindings)
        ..tick(1 / 60);
      expect(input.value(throttle), closeTo(1.0, 1e-9));

      fake.state.disconnect();
      pad.tick(1 / 60);

      expect(input.value(throttle), 0.0);
      expect(input.held(throttle), isFalse);
    });

    test('and the view it had accumulated goes with it', () {
      final fake = FakePad()..state.setAxis(PadAxis.rightStickX, 1.0);
      final pad = PadInput(
        state: InputState(),
        pad: _bare(fake),
        routes: const PadRoutes(lookRate: 100.0),
      )..tick(1.0);

      fake.state.disconnect();
      pad.tick(1 / 60);

      final out = Vector2.zero();
      pad.drainLook(out);
      expect(out.x, 0.0);
    });

    test('and a pad that was never there touches nothing', () {
      // Every frame of every build without a controller runs this path. Zeroing
      // the movement axis unconditionally would fight a touch stick for a
      // device that does not exist.
      final fake = FakePad()..state.disconnect();
      final input = InputState()..setStickAxis(0.0, 1.0);
      PadInput(state: input, pad: _bare(fake)).tick(1 / 60);

      expect(input.moveAxis.y, closeTo(1.0, 1e-9));
    });
  });

  group('the default bindings', () {
    test('are written down by position and survive a round trip', () {
      // The whole reason the device package spells buttons `face.south`: this
      // string is in the player's file, and on a PlayStation pad the same
      // button is called Cross.
      final bindings = PadInput.addDefaultsTo(Bindings());
      final read = Bindings.fromJson(bindings.toJson());

      expect(read[InputSource.pad('face.south')], GameAction.jump);
      expect(read[InputSource.pad('stick.left.click')], GameAction.sprint);
    });

    test('and they join the keyboard in one table', () {
      // One file holds both, which is what `Bindings` was always for.
      final bindings = PadInput.addDefaultsTo(DesktopInput.defaultBindings());

      expect(bindings[InputSource.pad('face.south')], GameAction.jump);
      expect(bindings.sourcesFor(GameAction.jump).length, 2,
          reason: 'space and the south face button');
    });

    test('and each call hands out its own', () {
      // A shared default is rebound for the menu, the second window and the
      // next level by the first player who changes anything.
      PadInput.defaultBindings().unbind(InputSource.pad('face.south'));

      expect(PadInput.defaultBindings()[InputSource.pad('face.south')],
          GameAction.jump);
    });
  });

  group('settings', () {
    test('are read from the config, so three games spell them once', () {
      final config = GameConfig()
        ..setSetting('pad.look', 250.0)
        ..setSetting('pad.deadzone.stick', 0.3);
      final fake = FakePad();
      final pad = PadInput(state: InputState(), pad: Gamepad(platform: fake))
        ..applySettings(config);

      expect(pad.routes.lookRate, 250.0);
      expect(pad.pad.deadzone.stick, 0.3);
      expect(pad.pad.deadzone.trigger, const Deadzone().trigger,
          reason: 'a name the config does not carry keeps its default');
    });

    test('and go back, so a slider survives a relaunch', () {
      final fake = FakePad();
      final pad = PadInput(
        state: InputState(),
        pad: Gamepad(platform: fake, deadzone: const Deadzone(stick: 0.22)),
        routes: const PadRoutes(lookRate: 800.0),
      );
      final config = GameConfig();
      pad.storeSettings(config);

      expect(GameConfig.fromJson(config.toJson()).settingOf('pad.look', 0.0),
          800.0);
      expect(
          GameConfig.fromJson(config.toJson())
              .settingOf('pad.deadzone.stick', 0.0),
          0.22);
    });
  });

  group('a build with no gamepad implementation', () {
    test('is a translator that says nothing', () {
      final input = InputState()..press(GameAction.moveForward);
      final pad = PadInput(state: input, pad: Gamepad(platform: UnsupportedGamepad()))
        ..tick(1 / 60);

      expect(pad.isSupported, isFalse);
      expect(pad.isConnected, isFalse);
      expect(input.held(GameAction.moveForward), isTrue);
    });
  });
}
