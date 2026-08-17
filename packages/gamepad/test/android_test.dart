/// The Android backend, without an Android device.
///
///     flutter test test/android_test.dart
///
/// **This file is the argument for how the Android backend is built.** The
/// specification says a gamepad backend written without a controller in hand is
/// wrong in a way no test shows, and it says so because one was deleted here for
/// exactly that. The way past the rule is not to be braver — it is to leave the
/// native side with nothing in it worth testing.
///
/// So the native side forwards raw events and an inventory of what the device
/// admits to having, and every decision is here: which axis a trigger is on,
/// whether the d-pad is a hat, what happens when a second pad moves its stick,
/// what a pad that is still attached does while the application is in the
/// background. All of that is reachable from a plain unit test, and all of it is
/// where the mistakes are.
///
/// What still needs a device and a person: whether the events arrive at all.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamepad/gamepad.dart';
import 'package:gamepad/src/android_mapping.dart';
import 'package:gamepad/src/gamepad_method_channel.dart';

/// One motion event, in the shape the plugin sends it.
Float64List motion(int device, Map<int, double> axes) {
  final out = Float64List(1 + axes.length * 2);
  out[0] = device.toDouble();
  var at = 1;
  axes.forEach((int axis, double value) {
    out[at++] = axis.toDouble();
    out[at++] = value;
  });
  return out;
}

KeyEvent down(LogicalKeyboardKey key) => KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.gameButton1,
      logicalKey: key,
      timeStamp: Duration.zero,
    );

KeyEvent up(LogicalKeyboardKey key) => KeyUpEvent(
      physicalKey: PhysicalKeyboardKey.gameButton1,
      logicalKey: key,
      timeStamp: Duration.zero,
    );

/// A pad with the axes an ordinary controller reports.
AndroidPadState connected({
  int device = 7,
  List<int> axes = const <int>[
    AndroidAxis.x,
    AndroidAxis.y,
    AndroidAxis.z,
    AndroidAxis.rz,
    AndroidAxis.hatX,
    AndroidAxis.hatY,
    AndroidAxis.leftTrigger,
    AndroidAxis.rightTrigger,
  ],
}) =>
    AndroidPadState()..connect(deviceId: device, axes: axes);

void main() {
  group('the sticks', () {
    test('arrive as they are, positive downwards', () {
      // Android reports Y positive downwards, which is this package's own
      // convention, so nothing is flipped here and the flip happens where a game
      // decides what forward means.
      final state = connected();
      state.noteMotion(motion(7, <int, double>{
        AndroidAxis.x: 0.5,
        AndroidAxis.y: -1.0,
        AndroidAxis.z: -0.25,
        AndroidAxis.rz: 0.75,
      }));

      final out = PadSnapshot();
      state.fill(out);

      expect(out.axis(PadAxis.leftStickX), closeTo(0.5, 1e-9));
      expect(out.axis(PadAxis.leftStickY), closeTo(-1.0, 1e-9));
      expect(out.axis(PadAxis.rightStickX), closeTo(-0.25, 1e-9));
      expect(out.axis(PadAxis.rightStickY), closeTo(0.75, 1e-9));
    });

    test('and a second pad moving its stick is not this pad', () {
      // "One pad at a time" is a decision this package made and has to keep:
      // reading every device would let a controller nobody is holding fight the
      // one somebody is.
      final state = connected();
      state
        ..noteMotion(motion(7, <int, double>{AndroidAxis.x: 0.5}))
        ..noteMotion(motion(9, <int, double>{AndroidAxis.x: -1.0}));

      final out = PadSnapshot();
      state.fill(out);

      expect(out.axis(PadAxis.leftStickX), closeTo(0.5, 1e-9));
    });
  });

  group('a trigger, which is on one of two axes', () {
    test('is `AXIS_LTRIGGER` where the driver offers it', () {
      final state = connected();
      state.noteMotion(motion(7, <int, double>{
        AndroidAxis.leftTrigger: 0.4,
        AndroidAxis.rightTrigger: 0.9,
      }));

      final out = PadSnapshot();
      state.fill(out);

      expect(out.axis(PadAxis.triggerLeft), closeTo(0.4, 1e-9));
      expect(out.axis(PadAxis.triggerRight), closeTo(0.9, 1e-9));
    });

    test("and the wheel's axes where it does not", () {
      // **The trap this group exists for.** Plenty of drivers report the same two
      // physical controls as `AXIS_BRAKE` and `AXIS_GAS`, and a backend that only
      // knew the first pair would give that hardware two triggers that never
      // move. Which pair to read is chosen per device from what it says it has.
      final state = connected(axes: <int>[AndroidAxis.brake, AndroidAxis.gas]);
      state.noteMotion(motion(7, <int, double>{
        AndroidAxis.brake: 0.3,
        AndroidAxis.gas: 0.8,
      }));

      final out = PadSnapshot();
      state.fill(out);

      expect(out.axis(PadAxis.triggerLeft), closeTo(0.3, 1e-9));
      expect(out.axis(PadAxis.triggerRight), closeTo(0.8, 1e-9));
    });

    test('and the preferred pair wins when a device reports both', () {
      final state = connected(axes: <int>[
        AndroidAxis.leftTrigger,
        AndroidAxis.rightTrigger,
        AndroidAxis.brake,
        AndroidAxis.gas,
      ]);
      state.noteMotion(motion(7, <int, double>{
        AndroidAxis.leftTrigger: 0.1,
        AndroidAxis.brake: 1.0,
      }));

      final out = PadSnapshot();
      state.fill(out);

      expect(out.axis(PadAxis.triggerLeft), closeTo(0.1, 1e-9));
    });

    test('and a pad with no trigger axis at all still has a trigger', () {
      // A few report neither pair and offer only the digital `L2`/`R2` buttons.
      // Nought or one is the truth about what that hardware said, and a game
      // reading the proportion gets it rather than a smoothed guess.
      final state = connected(axes: <int>[AndroidAxis.x, AndroidAxis.y]);
      state.noteKey(down(LogicalKeyboardKey.gameButtonRight2));

      final out = PadSnapshot();
      state.fill(out);

      expect(out.axis(PadAxis.triggerRight), 1.0);
      expect(out.down(PadButton.triggerRight), isTrue);
      expect(out.axis(PadAxis.triggerLeft), 0.0);
    });
  });

  group('the d-pad, which is a hat or it is arrow keys', () {
    test('a hat becomes the four buttons it stands for', () {
      final state = connected();
      state.noteMotion(motion(7, <int, double>{
        AndroidAxis.hatX: -1.0,
        AndroidAxis.hatY: 1.0,
      }));

      final out = PadSnapshot();
      state.fill(out);

      expect(out.down(PadButton.dpadLeft), isTrue);
      expect(out.down(PadButton.dpadDown), isTrue);
      expect(out.down(PadButton.dpadRight), isFalse);
      expect(out.down(PadButton.dpadUp), isFalse);
    });

    test('and centring it lets go', () {
      final state = connected();
      state.noteMotion(motion(7, <int, double>{AndroidAxis.hatY: -1.0}));
      state.noteMotion(motion(7, <int, double>{AndroidAxis.hatY: 0.0}));

      final out = PadSnapshot();
      state.fill(out);

      expect(out.down(PadButton.dpadUp), isFalse);
    });

    test('and a hat that reports a continuum still counts', () {
      // A few drivers report a hat as a proportional axis. A threshold of one
      // exactly would be a d-pad that does nothing on that hardware.
      final state = connected();
      state.noteMotion(motion(7, <int, double>{AndroidAxis.hatX: 0.7}));

      final out = PadSnapshot();
      state.fill(out);

      expect(out.down(PadButton.dpadRight), isTrue);
    });

    test('and arrow keys are deliberately not a d-pad', () {
      // **The limitation, and it is a decision rather than an oversight.** A pad
      // without a hat sends `KEYCODE_DPAD_*`, which Flutter maps to the arrow
      // keys — and a `KeyEvent` does not say which device it came from, so those
      // are indistinguishable from a keyboard's arrows. Claiming `pad:dpad.up`
      // for them would write a lie into a player's permanent config file. On such
      // a pad the d-pad works as arrow keys, which every game here binds to
      // walking anyway.
      final state = connected();
      final claimed = state.noteKey(down(LogicalKeyboardKey.arrowUp));

      final out = PadSnapshot();
      state.fill(out);

      expect(claimed, isFalse, reason: 'an arrow key is not the pad\'s to take');
      expect(out.down(PadButton.dpadUp), isFalse);
    });
  });

  group('the buttons, which arrive through Flutter', () {
    test('are positions, in Android\'s own numbering', () {
      // Android's `BUTTON_A` is the lower face button, `BUTTON_B` the right one —
      // the same physical numbering the browser's standard mapping uses, and the
      // reason neither needs a translation table beyond this one.
      final state = connected();
      state
        ..noteKey(down(LogicalKeyboardKey.gameButtonA))
        ..noteKey(down(LogicalKeyboardKey.gameButtonB));

      final out = PadSnapshot();
      state.fill(out);

      expect(out.down(PadButton.faceSouth), isTrue);
      expect(out.down(PadButton.faceEast), isTrue);
      expect(out.down(PadButton.faceWest), isFalse);
    });

    test('and going up lets go', () {
      final state = connected();
      state
        ..noteKey(down(LogicalKeyboardKey.gameButtonA))
        ..noteKey(up(LogicalKeyboardKey.gameButtonA));

      final out = PadSnapshot();
      state.fill(out);

      expect(out.down(PadButton.faceSouth), isFalse);
    });

    test('and a keyboard key is left alone', () {
      // The handler that feeds this is attached to Flutter's keyboard, so it sees
      // every key in the application. Answering "not mine" is what keeps the game
      // playable from the keyboard at the same time.
      final state = connected();

      expect(state.noteKey(down(LogicalKeyboardKey.keyW)), isFalse);
      expect(state.noteKey(down(LogicalKeyboardKey.gameButtonA)), isTrue);
    });

    test('and every name in the table is one this package knows', () {
      // A typo here would be a button that is reported and can never be bound,
      // because nothing else in the package would ever mention it.
      for (final button in AndroidPadState.buttonsByKey.values) {
        expect(PadButton.known, contains(button), reason: button.id);
      }
    });
  });

  group('losing the player, and losing the pad', () {
    test('going to the background lets go without disconnecting', () {
      // The controller is still there; the player is not. Everything downstream
      // releases through the ordinary path once the buttons stop being down.
      final state = connected();
      state
        ..noteMotion(motion(7, <int, double>{AndroidAxis.y: -1.0}))
        ..noteKey(down(LogicalKeyboardKey.gameButtonA))
        ..relax();

      final out = PadSnapshot();
      state.fill(out);

      expect(out.connected, isTrue);
      expect(out.axis(PadAxis.leftStickY), 0.0);
      expect(out.down(PadButton.faceSouth), isFalse);
    });

    test('and unplugging leaves nothing held', () {
      final state = connected();
      state
        ..noteMotion(motion(7, <int, double>{AndroidAxis.rightTrigger: 1.0}))
        ..disconnect();

      final out = PadSnapshot();
      state.fill(out);

      expect(out.connected, isFalse);
      expect(out.axis(PadAxis.triggerRight), 0.0);
    });

    test('and a different pad does not inherit the last one\'s stick', () {
      // Swapping controllers mid-game: the one that went away may have been
      // holding its stick over when its battery died.
      final state = connected();
      state.noteMotion(motion(7, <int, double>{AndroidAxis.x: 1.0}));

      state.connect(deviceId: 9, axes: <int>[AndroidAxis.x]);
      state.fill(PadSnapshot());

      final out = PadSnapshot();
      state.fill(out);
      expect(out.axis(PadAxis.leftStickX), 0.0);
    });
  });

  group('the channel it all arrives on', () {
    // The binding, because a mock messenger needs one. Everything above this
    // group is plain arithmetic and needs nothing.
    TestWidgetsFlutterBinding.ensureInitialized();

    late MethodChannelGamepad pad;

    setUp(() {
      // A `flutter test` on a desktop reports itself as Android, which is what
      // makes this reachable at all — and is also why nothing subscribes in a
      // constructor. See `MethodChannelGamepad._ensureListening`.
      expect(defaultTargetPlatform, TargetPlatform.android);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('dev.flutter3d/gamepad/events'),
        (MethodCall call) async => null,
      );
      pad = MethodChannelGamepad();
    });

    tearDown(() async => pad.dispose());

    test('says nothing until a device is announced', () {
      final out = PadSnapshot()..connected = true;
      pad.read(out);

      expect(pad.isSupported, isTrue);
      expect(out.connected, isFalse);
    });

    test('and a device announcement carries the axes it has', () {
      pad
        ..handleEvent(<String, Object?>{
          'event': 'connected',
          'device': 3,
          'name': 'Xbox Wireless Controller',
          'axes': <int>[AndroidAxis.brake, AndroidAxis.gas],
        })
        ..handleEvent(motion(3, <int, double>{AndroidAxis.gas: 0.6}));

      final out = PadSnapshot();
      pad.read(out);

      expect(out.connected, isTrue);
      expect(out.axis(PadAxis.triggerRight), closeTo(0.6, 1e-9),
          reason: 'the inventory reached the mapping');
    });

    test('and announces connection and disconnection', () async {
      final seen = <PadConnection>[];
      final subscription = pad.connectionChanges.listen(seen.add);

      pad
        ..handleEvent(<String, Object?>{
          'event': 'connected',
          'device': 3,
          'axes': <int>[AndroidAxis.x],
        })
        ..handleEvent(<String, Object?>{'event': 'disconnected'});

      await Future<void>.delayed(Duration.zero);
      expect(seen, <PadConnection>[
        PadConnection.connected,
        PadConnection.disconnected,
      ]);
      await subscription.cancel();
    });

    test('and a message it does not understand changes nothing', () {
      // A newer native side talking to an older Dart one. Throwing here would
      // take out the frame that read the pad.
      pad
        ..handleEvent(<String, Object?>{
          'event': 'connected',
          'device': 3,
          'axes': <int>[AndroidAxis.x],
        })
        ..handleEvent(<String, Object?>{'event': 'rumble', 'strength': 0.5})
        ..handleEvent('nonsense');

      final out = PadSnapshot();
      pad.read(out);
      expect(out.connected, isTrue);
    });
    // Skipped in a browser, where this class is not the backend and there are no
    // channels for it to talk over. The mapping above is checked there too, and
    // is the half that could be got wrong.
  }, skip: kIsWeb ? 'the browser has its own backend' : null);
}
