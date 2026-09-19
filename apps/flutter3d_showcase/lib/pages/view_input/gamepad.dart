/// The shape a gamepad arrives in, and the dead zone every stick needs
/// before its numbers are worth reading.
///
/// **`pad_input` is not a dependency of this app yet.** It reads a physical
/// pad as a `PadSnapshot` (buttons named by position, two sticks and two
/// triggers) once a frame and applies a `Deadzone` to each stick. This page
/// cannot import that package (see the showcase's own report on this row),
/// so it reimplements the one piece of maths that matters, radial dead
/// zoning, against a stand-in stick driven by the arrow keys, and is honest
/// about the difference in the guide below.
///
/// Quoted by `gamepad.md` and shown whole in the Source tab.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class GamepadDemo extends ShowcaseDemo {
  double threshold = 0.2;

  @override
  Scene build(DemoContext context) {
    final Material stone = Material(
      name: 'stone',
      baseColor: Vector4(0.5, 0.6, 0.4, 1.0),
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

  // #region raw
  /// The arrow keys read as a stick: -1, 0 or 1 on each axis, the same shape
  /// `PadSnapshot.leftStick` reports for a physical stick pushed to a corner.
  Vector2 _rawStick() {
    final Set<LogicalKeyboardKey> down =
        HardwareKeyboard.instance.logicalKeysPressed;
    double x = 0.0;
    double y = 0.0;
    if (down.contains(LogicalKeyboardKey.arrowLeft)) x -= 1.0;
    if (down.contains(LogicalKeyboardKey.arrowRight)) x += 1.0;
    if (down.contains(LogicalKeyboardKey.arrowUp)) y -= 1.0;
    if (down.contains(LogicalKeyboardKey.arrowDown)) y += 1.0;
    return Vector2(x, y);
  }
  // #endregion raw

  // #region deadzone
  /// A stick rarely rests at exactly zero, so any reading under [threshold]
  /// is thrown away, and what remains is rescaled to still reach 1 at the
  /// stick's own edge. This is the radial dead zone `pad_input`'s `Deadzone`
  /// applies to every stick before a game ever sees its value.
  Vector2 _applyDeadzone(Vector2 raw, double threshold) {
    final double magnitude = raw.length;
    if (magnitude <= threshold) return Vector2.zero();
    final double rescaled = (magnitude - threshold) / (1.0 - threshold);
    return raw.normalized() * rescaled.clamp(0.0, 1.0);
  }
  // #endregion deadzone

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) {
    final Vector2 raw = _rawStick();
    final Vector2 shaped = _applyDeadzone(raw, threshold);
    return Focus(
      autofocus: true,
      onKeyEvent: (FocusNode node, KeyEvent event) => KeyEventResult.ignored,
      child: Container(
        color: const Color(0xFF14161A),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.topLeft,
        child: DefaultTextStyle(
          style: const TextStyle(color: Color(0xFFE8E8EC), fontSize: 16),
          child: Text(
            'pad_input is not wired into this app. Hold the arrow keys as a '
            'stand-in stick; the numbers below are the same shape a '
            'PadSnapshot reports, before and after the dead zone.\n\n'
            'raw: (${raw.x.toStringAsFixed(2)}, ${raw.y.toStringAsFixed(2)})\n'
            'dead-zoned: (${shaped.x.toStringAsFixed(2)}, '
            '${shaped.y.toStringAsFixed(2)})',
          ),
        ),
      ),
    );
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Dead zone',
      min: 0.0,
      max: 0.6,
      value: () => threshold,
      onChanged: (double v) => threshold = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the ball was not drawn');
    }
    // A stick pushed only just past centre reads as nothing once the dead
    // zone is applied.
    final Vector2 small = _applyDeadzone(Vector2(0.1, 0.0), 0.2);
    if (small.length != 0.0) {
      throw StateError('a reading under the threshold should zero out');
    }
    // A stick pushed all the way to a corner still reads as length 1 after
    // the dead zone rescales it, not shrunk by the zone it passed through.
    final Vector2 full = _applyDeadzone(Vector2(1.0, 0.0), 0.2);
    if ((full.length - 1.0).abs() > 1e-9) {
      throw StateError('a stick at its edge should still read as length 1');
    }
  }
}
