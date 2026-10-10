/// Photo mode's own keys: what it takes while it is open, and what it lets
/// through while it is not.
///
///     flutter test test/photo_mode_test.dart
///
/// The camera's tether and its sweep through the barriers are
/// `PhotoCamera`'s, and `flutter3d_sim`'s tests hold it to them; what is this
/// game's is that a stopped race takes no throttle, steering or tyre change
/// — a key let through would be held down in the car when the race resumes.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;
import 'package:flutter3d/flutter3d.dart'
    show PerspectiveProjection, PhotoFilter;
import 'package:flutter3d_demo_racing/src/photo_mode.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

KeyDownEvent _down(LogicalKeyboardKey key) => KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.keyA,
  logicalKey: key,
  timeStamp: Duration.zero,
);

void main() {
  // Enter asks the keyboard whether Shift is down.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('open, it takes every key; closed, it takes none', () {
    final photo = chasePhotoMode();
    var captured = 0;
    KeyEventResult? press(LogicalKeyboardKey key) =>
        photo.key(_down(key), onCapture: (_) => captured++);

    expect(press(LogicalKeyboardKey.keyW), isNull, reason: 'not open yet');
    expect(photo.gaze, isNull);

    photo.enter(
      world: CollisionWorld(),
      eye: Vector3(0.0, 2.0, 6.0),
      target: Vector3.zero(),
      anchor: Vector3.zero(),
      lens: const PerspectiveProjection(fovY: 1.05),
    );
    // Mutation: letting the keys photo mode has no use for fall through
    // drives the car the picture stopped.
    for (final key in <LogicalKeyboardKey>[
      LogicalKeyboardKey.keyW,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.keyT,
    ]) {
      expect(press(key), KeyEventResult.handled, reason: key.debugName);
    }
    // The fog is coloured along where the photo camera looks: from the
    // chase camera's eye towards the car.
    expect(
      photo.gaze!.dot(Vector3(0.0, -2.0, -6.0).normalized()),
      closeTo(1.0, 1e-6),
    );

    expect(photo.filter, PhotoFilter.none);
    press(LogicalKeyboardKey.bracketRight);
    expect(photo.filter, PhotoFilter.all[1]);
    press(LogicalKeyboardKey.enter);
    expect(captured, 1);

    photo.leave();
    expect(press(LogicalKeyboardKey.keyW), isNull);
    expect(photo.gaze, isNull);
  });
}
