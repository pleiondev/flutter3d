/// Photo mode as a game holds it: which keys it takes, how the game's own
/// controls fly the camera, and the lens a picture is taken through.
///
///     flutter test test/photo_mode_test.dart
///
/// The camera's tether and its sweep through the walls are `PhotoCamera`'s,
/// and `flutter3d_sim`'s tests hold it to them.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_game_ui/photo_mode.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

KeyDownEvent _down(LogicalKeyboardKey key) => KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.keyA,
  logicalKey: key,
  timeStamp: Duration.zero,
);

KeyUpEvent _up(LogicalKeyboardKey key) => KeyUpEvent(
  physicalKey: PhysicalKeyboardKey.keyA,
  logicalKey: key,
  timeStamp: Duration.zero,
);

const GameAction _down1 = GameAction('photoTest.down');

PhotoMode _walking() => PhotoMode(
  controls: const ActionPhotoControls(
    up: GameAction.jump,
    down: _down1,
    sensitivity: 0.002,
  ),
);

void _open(PhotoMode mode, {Vector3? anchor, double? fieldOfView}) =>
    mode.enter(
      world: CollisionWorld()..update(),
      eye: Vector3(0.0, 2.0, 5.0),
      target: Vector3.zero(),
      anchor: anchor,
      fieldOfView: fieldOfView,
    );

void main() {
  // Enter asks the keyboard whether Shift is held.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('closed, it takes no key; busy, it takes them all', () {
    final mode = _walking();
    // Mutation: a closed photo mode answers `handled` — Enter and the
    // brackets are taken from the game while nobody is taking a picture.
    expect(
      mode.key(_down(LogicalKeyboardKey.enter), onCapture: (_) {}),
      isNull,
    );
    expect(mode.gaze, isNull);

    _open(mode);
    final asked = <int>[];
    mode.isBusy = true;
    // Mutation: drop the `busy` check. A second Enter while a 4x picture is
    // drawing starts another capture on the same renderer.
    expect(
      mode.key(_down(LogicalKeyboardKey.enter), onCapture: asked.add),
      KeyEventResult.handled,
    );
    expect(asked, isEmpty);
  });

  test('brackets step through the filters, wrapping, and Enter asks for '
      'a 2x picture', () {
    final mode = _walking();
    _open(mode);
    final asked = <int>[];
    mode.key(_down(LogicalKeyboardKey.bracketRight), onCapture: asked.add);
    expect(mode.filter, PhotoFilter.all[1]);
    mode
      ..key(_down(LogicalKeyboardKey.bracketLeft), onCapture: asked.add)
      ..key(_down(LogicalKeyboardKey.bracketLeft), onCapture: asked.add);
    expect(mode.filter, PhotoFilter.all.last);
    mode.key(_down(LogicalKeyboardKey.enter), onCapture: asked.add);
    expect(asked, <int>[2]);
  });

  test('only a mode that takes every key keeps the game\'s keys and their '
      'releases', () {
    final walking = _walking();
    _open(walking);
    // Mutation: answer `handled` for every key — a game that walks on W
    // never hears it was let go, and walks on out of the picture.
    expect(
      walking.key(_down(LogicalKeyboardKey.keyT), onCapture: (_) {}),
      isNull,
    );
    expect(
      walking.key(_up(LogicalKeyboardKey.keyT), onCapture: (_) {}),
      isNull,
    );

    final every = PhotoMode(
      controls: const KeyPhotoControls(
        up: LogicalKeyboardKey.keyE,
        down: LogicalKeyboardKey.keyQ,
      ),
      takesEveryKey: true,
    );
    _open(every);
    // Mutation: let the keys photo mode has no use for fall through, and the
    // car the picture stopped is driven by them.
    for (final key in <LogicalKeyboardKey>[
      LogicalKeyboardKey.keyW,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.keyT,
    ]) {
      expect(every.key(_down(key), onCapture: (_) {}), KeyEventResult.handled);
      expect(every.key(_up(key), onCapture: (_) {}), KeyEventResult.handled);
    }
  });

  test('the down action flies the camera down, and sprint flies it '
      'faster', () {
    double dropAfter(InputState input) {
      final mode = _walking();
      _open(mode);
      for (var i = 0; i < 30; i++) {
        mode.fly(1 / 60, input: input, look: Vector2.zero());
      }
      final node = CameraNode();
      mode.applyTo(node);
      return 2.0 - node.readPosition().y;
    }

    final slow = dropAfter(InputState()..press(_down1));
    // Mutation: the down axis read from `moveBack` — the game's down action
    // does nothing.
    expect(slow, greaterThan(0.0));
    final fast = dropAfter(
      InputState()
        ..press(_down1)
        ..press(GameAction.sprint),
    );
    // Mutation: drop the fast factor, and sprint is the same camera.
    expect(fast, greaterThan(slow * 2.0));
  });

  test('a look in pixels turns the camera by the sensitivity', () {
    final mode = _walking();
    _open(mode);
    final before = mode.gaze!.clone();
    mode.fly(1 / 60, input: InputState(), look: Vector2(100.0, 0.0));
    // Mutation: the look ignored without an intent — the mouse does nothing
    // while no key is held.
    expect(mode.gaze!.dot(before), lessThan(1.0 - 1e-6));
  });

  test('a busy mode does not turn under a drag', () {
    final mode = _walking();
    _open(mode);
    final before = mode.gaze!.clone();
    mode
      ..isBusy = true
      ..turn(80.0, 0.0, perPixel: 0.01);
    // Mutation: drop the `busy` check in `turn`, and the picture being drawn
    // in tiles is drawn from two places.
    expect(mode.gaze!.dot(before), closeTo(1.0, 1e-9));
    mode
      ..isBusy = false
      ..turn(80.0, 0.0, perPixel: 0.01);
    expect(mode.gaze!.dot(before), lessThan(1.0 - 1e-6));
  });

  test('the picture is taken through the game\'s lens, zoomed', () {
    final mode = PhotoMode(
      controls: const KeyPhotoControls(
        up: LogicalKeyboardKey.space,
        down: LogicalKeyboardKey.keyC,
      ),
      lens: const PerspectiveProjection(fovY: 1.05, far: 220.0),
    );
    _open(mode);
    final node = CameraNode();
    mode.applyTo(node);
    final projection = node.projection as PerspectiveProjection;
    // Mutation: a fresh `PerspectiveProjection` in `applyTo` — the game's far
    // plane is lost the moment photo mode opens.
    expect(projection.far, 220.0);
    expect(projection.fovY, closeTo(1.05, 1e-9));

    mode.key(_down(LogicalKeyboardKey.equal), onCapture: (_) {});
    mode.applyTo(node);
    expect((node.projection as PerspectiveProjection).fovY, lessThan(1.05));
  });

  test('enter takes a new lens, and a field of view over it', () {
    final mode = _walking();
    mode.enter(
      world: CollisionWorld()..update(),
      eye: Vector3(0.0, 2.0, 6.0),
      target: Vector3.zero(),
      anchor: Vector3.zero(),
      lens: const PerspectiveProjection(fovY: 0.8, near: 0.3),
    );
    final node = CameraNode();
    mode.applyTo(node);
    final projection = node.projection as PerspectiveProjection;
    // Mutation: ignore `lens` in `enter`, and a chase camera widened by speed
    // is photographed through the lens it started with.
    expect(projection.near, 0.3);
    expect(projection.fovY, closeTo(0.8, 1e-9));
    // The gaze runs from the eye towards the target.
    expect(
      mode.gaze!.dot(Vector3(0.0, -2.0, -6.0).normalized()),
      closeTo(1.0, 1e-6),
    );
    mode.leave();
    expect(mode.isActive, isFalse);
    expect(mode.gaze, isNull);
  });

  testWidgets('the bar shows the filter and the game\'s line of keys', (
    WidgetTester tester,
  ) async {
    final mode = PhotoMode(
      controls: const KeyPhotoControls(
        up: LogicalKeyboardKey.keyE,
        down: LogicalKeyboardKey.keyQ,
      ),
      keysHint: 'Q/E down and up',
    );
    _open(mode);
    mode.said = 'Saved to Pictures';
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(children: <Widget>[PhotoBar(mode: mode)]),
      ),
    );
    expect(
      find.text('Photo mode · filter: ${PhotoFilter.none.name}'),
      findsOneWidget,
    );
    // Mutation: the walking line written into the bar — the racing game
    // tells its player Space flies up.
    expect(find.text('Q/E down and up'), findsOneWidget);
    expect(find.text('Saved to Pictures'), findsOneWidget);

    mode.isBusy = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(children: <Widget>[PhotoBar(mode: mode)]),
      ),
    );
    expect(find.text('Taking the picture…'), findsOneWidget);
  });
}
