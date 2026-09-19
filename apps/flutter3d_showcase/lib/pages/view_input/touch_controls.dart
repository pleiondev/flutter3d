/// An on-screen stick: a knob that reports how far it was dragged from its
/// centre, clamped to a radius of one, and lets go the moment the finger
/// leaves.
///
/// **`flutter3d_game` is not a dependency of this app yet.** Its
/// `TouchStick` and `TouchButton` do this against a shared `InputState` that
/// feeds the rest of a game's input the same way a key or a gamepad axis
/// does; this page cannot import either (see the showcase's own report on
/// this row), so it reimplements the stick's own arithmetic against a plain
/// `Listener`.
///
/// Quoted by `touch_controls.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class TouchControlsDemo extends ShowcaseDemo {
  Vector2 knob = Vector2.zero();

  @override
  Scene build(DemoContext context) {
    final Material stone = Material(
      name: 'stone',
      baseColor: Vector4(0.5, 0.55, 0.65, 1.0),
      roughness: 0.7,
    );
    final MeshNode ball = MeshNode(
      DeviceMesh.upload(
        context.device,
        SphereShape(segments: 24, rings: 12).build(),
      ),
      stone,
      name: 'ball',
    );
    return Scene()
      ..add(ball)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  // #region drag
  /// The knob's own position, as a fraction of the stick's radius: length 1
  /// at the edge, whatever the actual drag distance in pixels was.
  Vector2 dragTo(Offset fromCentre, double radius) {
    if (radius <= 0.0) return Vector2.zero();
    final Vector2 offset = Vector2(fromCentre.dx, fromCentre.dy);
    if (offset.length <= radius) return offset / radius;
    return offset.normalized();
  }
  // #endregion drag

  // #region release
  /// A touch control lets go the moment the finger leaves it, rather than
  /// holding the last value: an axis frozen at full deflection because a
  /// screen transition covered the stick is the failure this exists to
  /// avoid.
  Vector2 release() => Vector2.zero();
  // #endregion release

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) {
    const double radius = 60.0;
    const Offset centre = Offset(80, 80);
    return Listener(
      onPointerDown: (PointerDownEvent event) =>
          knob = dragTo(event.localPosition - centre, radius),
      onPointerMove: (PointerMoveEvent event) =>
          knob = dragTo(event.localPosition - centre, radius),
      onPointerUp: (PointerUpEvent event) => knob = release(),
      onPointerCancel: (PointerCancelEvent event) => knob = release(),
      child: Container(
        color: const Color(0xFF14161A),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.topLeft,
        child: DefaultTextStyle(
          style: const TextStyle(color: Color(0xFFE8E8EC), fontSize: 16),
          child: Text(
            'flutter3d_game is not wired into this app. Drag anywhere in '
            'this panel to move the stand-in stick.\n\n'
            'knob: (${knob.x.toStringAsFixed(2)}, ${knob.y.toStringAsFixed(2)})',
          ),
        ),
      ),
    );
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the ball was not drawn');
    }
    // A drag well inside the radius reports its own fraction, not clamped.
    final Vector2 partial = dragTo(const Offset(30, 0), 60.0);
    if ((partial.length - 0.5).abs() > 1e-9) {
      throw StateError('a drag halfway to the edge should read as length 0.5');
    }
    // A drag past the radius clamps to length 1, never past it.
    final Vector2 past = dragTo(const Offset(600, 0), 60.0);
    if ((past.length - 1.0).abs() > 1e-9) {
      throw StateError('a drag past the radius should clamp to length 1');
    }
    // Releasing always zeroes the knob, regardless of where it was.
    if (release() != Vector2.zero()) {
      throw StateError('releasing the stick should zero it');
    }
  }
}
