/// Everything about a gamepad that does not need a gamepad.
///
///     flutter test
///
/// **The specification records that an earlier gamepad stub was deleted rather
/// than finished**, because a backend written without a controller in hand is
/// wrong in a way no test shows. That is true of the platform channel and false
/// of everything above it, and this file is the everything above it: the dead
/// zone, the snapshot, and the vocabulary that gets written into a player's
/// configuration file and has to mean the same thing for ever.
library;

import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride, kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:gamepad/gamepad.dart';
import 'package:gamepad/src/standard_mapping.dart';

/// A gamepad that does whatever a test says.
///
/// Modelled on `mouse_capture`'s fake, and for the reason that one gives: the
/// parts that are easy to get wrong live above the channel and would otherwise
/// only be reachable by running a game and waving a controller at it.
final class FakePad extends GamepadPlatform {
  final PadSnapshot state = PadSnapshot()..connected = true;
  final StreamController<PadConnection> _connections =
      StreamController<PadConnection>.broadcast();

  int reads = 0;

  @override
  bool get isSupported => true;

  @override
  Stream<PadConnection> get connectionChanges => _connections.stream;

  @override
  void read(PadSnapshot out) {
    reads++;
    out.copyFrom(state);
  }

  /// What a backend must do when a pad goes away: zero it, **then** say so.
  void unplug() {
    state.disconnect();
    _connections.add(PadConnection.disconnected);
  }

  @override
  Future<void> dispose() async => _connections.close();
}

void main() {
  group('the dead zone', () {
    test('a stick at rest is a stick at rest', () {
      // Every pad reports a stick a few hundredths off centre. A game that
      // believes it walks the player into a wall while nobody is touching the
      // controller.
      const zone = Deadzone(stick: 0.15);
      final xy = <double>[0.03, -0.04];
      zone.applyToStick(xy);

      expect(xy, <double>[0.0, 0.0]);
    });

    test('and leaving it starts from nothing, not from the zone', () {
      // **The mutation this exists for**: drop the rescale and a stick crossing
      // a 0.15 zone jumps straight to 0.15, which reads as the character
      // twitching into motion and looks like a physics bug.
      const zone = Deadzone(stick: 0.15);
      final justOutside = <double>[0.1501, 0.0];
      zone.applyToStick(justOutside);

      expect(justOutside[0], lessThan(0.01),
          reason: 'the first live value is ${justOutside[0]}, not nearly zero');
    });

    test('and full deflection is still full', () {
      // The other end of the rescale: a stick pushed all the way must ask for
      // all the speed, or the dead zone quietly becomes a speed limit.
      const zone = Deadzone(stick: 0.15);
      final full = <double>[0.0, 1.0];
      zone.applyToStick(full);

      expect(full[1], closeTo(1.0, 1e-9));
    });

    test('it is round, not square', () {
      // A per-axis dead zone carves a square hole out of a round stick, so a
      // stick pushed diagonally has to travel further to come alive than one
      // pushed along an axis.
      //
      // **The number has to be one the two disagree about, and my first attempt
      // was not.** 0.12 on each axis is 0.17 of magnitude — dead under a round
      // zone of 0.2 *and* dead under a square one, so the test passed with a
      // square dead zone in place. 0.15 each is 0.212 of magnitude: live when
      // measured radially, dead when measured per axis.
      const zone = Deadzone(stick: 0.2);
      final diagonal = <double>[0.15, 0.15];
      zone.applyToStick(diagonal);

      expect(diagonal[0], greaterThan(0.0),
          reason: 'a diagonal push of 0.212 was treated as rest, so the zone '
              'is being measured per axis');
    });

    test('and it keeps the direction it was given', () {
      const zone = Deadzone(stick: 0.1);
      final xy = <double>[0.6, -0.8];
      zone.applyToStick(xy);

      // Same heading, shorter: the ratio survives.
      expect(xy[0] / xy[1], closeTo(0.6 / -0.8, 1e-6));
    });

    test('a trigger rests at nought and travels one way', () {
      const zone = Deadzone(trigger: 0.06);

      expect(zone.applyToTrigger(0.04), 0.0);
      expect(zone.applyToTrigger(0.0601), lessThan(0.01));
      expect(zone.applyToTrigger(1.0), closeTo(1.0, 1e-9));
    });
  });

  group('a snapshot', () {
    test('an ordinary button that is down is fully pressed', () {
      // So a caller that does not care which buttons are analogue never has to
      // find out.
      final snapshot = PadSnapshot()
        ..connected = true
        ..setDown(PadButton.faceSouth, down: true);

      expect(snapshot.down(PadButton.faceSouth), isTrue);
      expect(snapshot.pressure(PadButton.faceSouth), 1.0);
      expect(snapshot.pressure(PadButton.faceEast), 0.0);
    });

    test('and a disconnected pad is holding nothing', () {
      // Not stale values. A controller whose battery dies mid-corner must not
      // leave the throttle where it was.
      final snapshot = PadSnapshot()
        ..connected = true
        ..setAxis(PadAxis.triggerRight, 1.0)
        ..setDown(PadButton.faceSouth, down: true);

      snapshot.disconnect();

      expect(snapshot.connected, isFalse);
      expect(snapshot.axis(PadAxis.triggerRight), 0.0);
      expect(snapshot.down(PadButton.faceSouth), isFalse);
    });
  });

  group('reading through the dead zone', () {
    test('a resting pad asks for nothing', () {
      final fake = FakePad()
        ..state.setAxis(PadAxis.leftStickX, 0.04)
        ..state.setAxis(PadAxis.leftStickY, 0.02);
      final pad = Gamepad(platform: fake);
      final out = PadSnapshot();

      pad.read(out);

      expect(out.connected, isTrue);
      expect(out.axis(PadAxis.leftStickX), 0.0);
      expect(out.axis(PadAxis.leftStickY), 0.0);
    });

    test('and the caller cannot forget to apply it', () {
      // The whole reason the dead zone lives in `read` rather than beside it:
      // three games would otherwise each remember, and one would not.
      final fake = FakePad()..state.setAxis(PadAxis.rightStickX, 0.05);
      final pad = Gamepad(platform: fake);
      final out = PadSnapshot();

      pad.read(out);

      expect(out.axis(PadAxis.rightStickX), 0.0);
      expect(fake.reads, 1);
    });

    test('a trigger keeps its magnitude, not just its bit', () {
      // Racing needs the proportion; the platformer needs a threshold. Both
      // read the same snapshot.
      final fake = FakePad()..state.setAxis(PadAxis.triggerRight, 0.42);
      final pad = Gamepad(platform: fake);
      final out = PadSnapshot();

      pad.read(out);

      expect(out.axis(PadAxis.triggerRight), closeTo(0.383, 0.01));
      expect(out.pressure(PadButton.triggerRight),
          closeTo(out.axis(PadAxis.triggerRight), 1e-9));
    });

    test('a widened dead zone takes effect without a relaunch', () {
      // It is a slider in a settings panel.
      final fake = FakePad()..state.setAxis(PadAxis.leftStickX, 0.3);
      final pad = Gamepad(platform: fake);
      final out = PadSnapshot();

      pad.read(out);
      expect(out.axis(PadAxis.leftStickX), greaterThan(0.0));

      pad.deadzone = const Deadzone(stick: 0.5);
      pad.read(out);
      expect(out.axis(PadAxis.leftStickX), 0.0);
    });

    test('and unplugging is zeroes first, then the news', () async {
      // A backend that announced the disconnection before zeroing would leave
      // one frame of a pad holding everything it held.
      final fake = FakePad()..state.setAxis(PadAxis.triggerRight, 1.0);
      final pad = Gamepad(platform: fake);
      final out = PadSnapshot();
      final seen = <PadConnection>[];
      final subscription = pad.connectionChanges.listen(seen.add);

      pad.read(out);
      expect(out.axis(PadAxis.triggerRight), closeTo(1.0, 1e-9));

      fake.unplug();
      pad.read(out);

      expect(out.connected, isFalse);
      expect(out.axis(PadAxis.triggerRight), 0.0);
      await Future<void>.delayed(Duration.zero);
      expect(seen, <PadConnection>[PadConnection.disconnected]);

      await subscription.cancel();
      await pad.dispose();
    });
  });

  group('the button vocabulary', () {
    test('names are positions, and they are what gets written down', () {
      // **This is a permanent decision.** These strings go into a player's
      // configuration file and are read back years later, possibly on a
      // different pad. Xbox's lower face button is `A`, PlayStation's is Cross,
      // and Nintendo swaps `A` and `B` — so a label would mean something
      // different on different hardware, and every binding would silently move.
      expect(PadButton.faceSouth.id, 'face.south');
      expect(PadButton.triggerRight.id, 'trigger.right');
      expect(PadButton.stickLeftClick.id, 'stick.left.click');

      for (final button in PadButton.known) {
        expect(button.id, matches(RegExp(r'^[a-z]+(\.[a-z]+)*$')),
            reason: '${button.id} is not lower case and dot separated');
      }
    });

    test('and equality is the name, so a backend may report an unknown one', () {
      // The same reason `GameAction` is a value class: a pad with a button
      // nobody here has named should not have to wait for this file to change.
      expect(const PadButton('face.south'), PadButton.faceSouth);
      expect(const PadButton('paddle.left'), isNot(PadButton.faceSouth));
    });
  });

  group('a build with no implementation', () {
    test('says so, and opens nothing', () {
      // Never try-and-see: asking the channel and catching the failure costs
      // every unsupported platform a `MissingPluginException` at first use.
      final pad = Gamepad(platform: UnsupportedGamepad());
      final out = PadSnapshot()..connected = true;

      expect(pad.isSupported, isFalse);
      pad.read(out);
      expect(out.connected, isFalse);
    });

    test('and the default is whichever this build actually has', () {
      // The conditional export plus the native whitelist is the whole of the
      // platform choice, so this is the test that notices when it stops
      // choosing. Run it both ways; the second compiles the browser backend:
      //
      //     flutter test
      //     flutter test --platform chrome
      //
      // **The platform has to be named, not inferred.** A `flutter test` on a
      // desktop reports itself as `TargetPlatform.android` — `flutter_test`'s
      // own default — so a test that simply asked would be asserting something
      // about the machine it happens to run on.
      if (kIsWeb) {
        expect(Gamepad().isSupported, isTrue, reason: 'the browser backend');
        return;
      }
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      for (final platform in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = platform;
        // The native platforms written today, and this is the list that has to
        // change the day another one is — which is the point: a platform table
        // nobody has to update is one that goes stale. Windows and Linux are
        // what is left, and neither has an XInput or an evdev side yet.
        const written = <TargetPlatform>{
          TargetPlatform.android,
          TargetPlatform.macOS,
          TargetPlatform.iOS,
        };
        expect(
          Gamepad().isSupported,
          written.contains(platform),
          reason: '$platform',
        );
      }
    });
  });

  group("the browser's standard mapping", () {
    // A pad reporting nothing, in the shape the browser reports it.
    List<double> axes([
      double x0 = 0.0,
      double y0 = 0.0,
      double x1 = 0.0,
      double y1 = 0.0,
    ]) =>
        <double>[x0, y0, x1, y1];
    List<bool> pressed() => List<bool>.filled(17, false);
    List<double> values() => List<double>.filled(17, 0.0);

    test('a trigger is a button with a value, not an axis', () {
      // **The single most likely way to ship this wrongly.** In the standard
      // mapping the triggers are buttons 6 and 7 with travel between nought and
      // one; they are not in the axis list at all, and a backend that looked for
      // them there would find the right stick and call it a pedal.
      final snapshot = PadSnapshot();
      final travel = values()..[7] = 0.42;
      StandardGamepad.apply(snapshot,
          axisValues: axes(), pressed: pressed(), values: travel);

      expect(snapshot.axis(PadAxis.triggerRight), closeTo(0.42, 1e-9));
      expect(snapshot.axis(PadAxis.rightStickX), 0.0);
      expect(snapshot.pressure(PadButton.triggerRight), closeTo(0.42, 1e-9));
    });

    test('and its bit is the browser\'s threshold, reported separately', () {
      // Both numbers are passed on because they are not the same question. The
      // game applies its own threshold — with hysteresis, which the browser has
      // none of — and needs the travel to do it.
      final snapshot = PadSnapshot();
      StandardGamepad.apply(snapshot,
          axisValues: axes(),
          pressed: pressed()..[6] = true,
          values: values()..[6] = 0.9);

      expect(snapshot.down(PadButton.triggerLeft), isTrue);
      expect(snapshot.pressure(PadButton.triggerLeft), closeTo(0.9, 1e-9));
    });

    test('the face buttons are positions, in the order the spec fixes', () {
      // The specification numbers them bottom, right, left, top — which is this
      // package's own vocabulary, and the reason no translation table is needed
      // between the two.
      for (final pair in const <List<Object>>[
        <Object>[0, PadButton.faceSouth],
        <Object>[1, PadButton.faceEast],
        <Object>[2, PadButton.faceWest],
        <Object>[3, PadButton.faceNorth],
      ]) {
        final snapshot = PadSnapshot();
        StandardGamepad.apply(snapshot,
            axisValues: axes(),
            pressed: pressed()..[pair[0] as int] = true,
            values: values());

        expect(snapshot.down(pair[1] as PadButton), isTrue,
            reason: 'button ${pair[0]} is not ${pair[1]}');
      }
    });

    test('the d-pad is four buttons, and 12 is up', () {
      // On some drivers a d-pad is a hat axis; under the standard mapping it
      // never is, and getting this range wrong swaps up with the stick click.
      final snapshot = PadSnapshot();
      StandardGamepad.apply(snapshot,
          axisValues: axes(), pressed: pressed()..[12] = true, values: values());

      expect(snapshot.down(PadButton.dpadUp), isTrue);
      expect(snapshot.down(PadButton.stickRightClick), isFalse);
    });

    test('the sticks are axes nought to three', () {
      final snapshot = PadSnapshot();
      StandardGamepad.apply(snapshot,
          axisValues: axes(0.1, 0.2, 0.3, 0.4),
          pressed: pressed(),
          values: values());

      expect(snapshot.axis(PadAxis.leftStickX), closeTo(0.1, 1e-9));
      expect(snapshot.axis(PadAxis.leftStickY), closeTo(0.2, 1e-9));
      expect(snapshot.axis(PadAxis.rightStickX), closeTo(0.3, 1e-9));
      expect(snapshot.axis(PadAxis.rightStickY), closeTo(0.4, 1e-9));
    });

    test('a pad with fewer buttons than the table is not an error', () {
      // Plenty of pads report sixteen, having no middle button. Reading past the
      // end would be a crash on the frame a player plugs one in.
      final snapshot = PadSnapshot();
      StandardGamepad.apply(snapshot,
          axisValues: <double>[0.0, 0.0],
          pressed: List<bool>.filled(11, false)..[9] = true,
          values: List<double>.filled(11, 0.0));

      expect(snapshot.down(PadButton.start), isTrue);
      expect(snapshot.down(PadButton.guide), isFalse);
      expect(snapshot.axis(PadAxis.rightStickY), 0.0);
    });

    test('and one with more is not either', () {
      // Paddles, a touchpad, adaptive triggers: everything past the standard
      // mapping is deliberately unnamed here, and must be ignored rather than
      // guessed at.
      final snapshot = PadSnapshot();
      StandardGamepad.apply(snapshot,
          axisValues: List<double>.filled(8, 0.5),
          pressed: List<bool>.filled(24, true),
          values: List<double>.filled(24, 1.0));

      expect(snapshot.down(PadButton.guide), isTrue);
      expect(snapshot.held.length, StandardGamepad.buttons.length);
    });

    test('and what was released last frame is not still down', () {
      // The snapshot is reused between frames, so a mapping that only ever added
      // would hold every button that had ever been pressed.
      //
      // This is the guard on the invariant rather than on a defensive clear:
      // `apply` writes every control it names on every call, and clearing first
      // as well would be a line no mutation can reach.
      final snapshot = PadSnapshot();
      StandardGamepad.apply(snapshot,
          axisValues: axes(), pressed: pressed()..[0] = true, values: values());
      expect(snapshot.down(PadButton.faceSouth), isTrue);

      StandardGamepad.apply(snapshot,
          axisValues: axes(), pressed: pressed(), values: values());

      expect(snapshot.down(PadButton.faceSouth), isFalse);
      expect(snapshot.connected, isTrue);
    });
  });
}
