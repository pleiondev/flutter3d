/// What the player has already told the operating system, read as a default
/// for a camera's own involuntary movement.
///
/// **`flutter3d_game`'s real `Accommodations` is not a dependency of this
/// app.** It is nine lines wrapping `MediaQuery.maybeDisableAnimationsOf`;
/// this page reimplements exactly that shape and calls the same real
/// Flutter API, so the numbers below answer to this device's actual
/// reduce-motion setting, not a stand-in for it.
///
/// Quoted by `accommodations.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

// #region value
/// A default, never an override: a game reads this where the player has not
/// said otherwise, and a slider they moved themselves still wins.
final class _Accommodations {
  const _Accommodations({this.reduceMotion = false});

  factory _Accommodations.of(BuildContext context) => _Accommodations(
    reduceMotion: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
  );

  final bool reduceMotion;

  /// Nought when the player has asked for less movement: a camera that
  /// shakes on every landing is exactly what the system setting is about.
  double get cameraMotion => reduceMotion ? 0.0 : 1.0;

  /// The same fallback for a full-screen flash, kept separate because a
  /// flash is a photosensitivity question and a moving camera is a
  /// vestibular one.
  double get screenFlash => reduceMotion ? 0.0 : 1.0;
}
// #endregion value

final class AccommodationsDemo extends ShowcaseDemo {
  @override
  Scene build(DemoContext context) {
    final material = Material(
      name: 'ball',
      baseColor: Vector4(0.8, 0.6, 0.4, 1.0),
    );
    final node = MeshNode(
      DeviceMesh.upload(context.device, SphereShape(segments: 16).build()),
      material,
    );
    return Scene()
      ..add(node)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) {
    // #region read
    final accommodations = _Accommodations.of(buildContext);
    // #endregion read
    return Container(
      color: const Color(0xFF14161A),
      padding: const EdgeInsets.all(24),
      alignment: Alignment.topLeft,
      child: DefaultTextStyle(
        style: const TextStyle(color: Color(0xFFE8E8EC), fontSize: 16),
        child: Text(
          'this device asks for reduced motion: '
          '${accommodations.reduceMotion}\n'
          'a camera rig would default its own motion to '
          '${accommodations.cameraMotion}\n'
          'a full-screen flash would default to '
          '${accommodations.screenFlash}',
        ),
      ),
    );
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the ball was not drawn');
    }
    // #region compare
    const off = _Accommodations();
    const on = _Accommodations(reduceMotion: true);
    // #endregion compare
    if (off.cameraMotion != 1.0 || on.cameraMotion != 0.0) {
      throw StateError(
        'reduced motion should zero the camera motion '
        'default and nothing else should',
      );
    }
  }
}
