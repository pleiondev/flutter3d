/// Photo mode's own keys: what it takes while it is open, and what it lets
/// through while it is not.
///
///     flutter test test/photo_mode_test.dart
///
/// The camera's tether and its sweep through the blocks are
/// `PhotoCamera`'s, and `flutter3d_sim`'s tests hold it to them; what is the
/// sandbox's is that a stopped world takes no dig, place or pour.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;
import 'package:flutter3d/flutter3d.dart' show PhotoFilter;
import 'package:flutter3d_demo_sandbox/src/photo_mode.dart';
import 'package:flutter3d_demo_sandbox/src/staging.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter_test/flutter_test.dart';

KeyDownEvent _down(LogicalKeyboardKey key) => KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.keyA,
  logicalKey: key,
  timeStamp: Duration.zero,
);

void main() {
  // Enter asks the keyboard whether Shift is down.
  TestWidgetsFlutterBinding.ensureInitialized();
  test('open, it takes every key; closed, it takes none', () {
    final run = SandboxRun.fresh(backend: const DartPhysics());
    final photo = sandboxPhotoMode();
    var captured = 0;
    KeyEventResult? press(LogicalKeyboardKey key) =>
        photo.key(_down(key), onCapture: (_) => captured++);

    expect(press(LogicalKeyboardKey.keyQ), isNull, reason: 'not open yet');

    photo.enter(
      world: run.physics,
      eye: run.eye,
      target: run.eye + run.gaze,
      anchor: run.walk.body.position,
    );
    // Mutation: letting the keys photo mode has no use for fall through
    // lets Q dig, E place and R pour into the world the picture stopped.
    for (final key in <LogicalKeyboardKey>[
      LogicalKeyboardKey.keyQ,
      LogicalKeyboardKey.keyE,
      LogicalKeyboardKey.keyR,
      LogicalKeyboardKey.keyF,
      LogicalKeyboardKey.digit2,
    ]) {
      expect(press(key), KeyEventResult.handled, reason: key.debugName);
    }

    expect(photo.filter, PhotoFilter.none);
    press(LogicalKeyboardKey.bracketRight);
    expect(photo.filter, PhotoFilter.all[1]);
    press(LogicalKeyboardKey.enter);
    expect(captured, 1);

    photo.leave();
    expect(press(LogicalKeyboardKey.keyQ), isNull);
  });
}
