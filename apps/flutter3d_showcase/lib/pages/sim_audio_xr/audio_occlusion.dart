/// What the world does to a sound between there and here, as a callback the
/// scene asks and never a wall test of its own.
///
/// Quoted by `audio_occlusion.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class AudioOcclusionDemo extends ShowcaseDemo {
  late final String _report;

  @override
  Scene build(DemoContext context) {
    _report = _run();
    final material = Material(
      name: 'wall',
      baseColor: Vector4(0.6, 0.5, 0.4, 1.0),
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

  // #region wall
  /// A wall at x = 2: a straight line that crosses it is half heard, and one
  /// that does not is heard clearly. The scene never learns what a wall is;
  /// it only asks this question.
  static double _occlusion(Vector3 from, Vector3 to) {
    final crossesWall = (from.x - 2.0).sign != (to.x - 2.0).sign;
    return crossesWall ? 0.5 : 1.0;
  }
  // #endregion wall

  static String _run() {
    // #region scene
    final scene = AudioScene(backend: SilentBackend(), occlusion: _occlusion);
    const bell = SoundDef(name: 'bell', asset: 'bell.wav', loop: true);
    final behindTheWall = scene.play(bell, Vector3(4.0, 0.0, 0.0));
    // #endregion scene

    // #region listen
    final listener = AudioListener(position: Vector3(0.0, 0.0, 0.0));
    scene.update(listener);
    final gainBehindWall = behindTheWall.audibleGain;
    final muffleBehindWall = behindTheWall.muffle;

    listener.position.setValues(5.0, 0.0, 0.0);
    scene.update(listener);
    final gainSameSide = behindTheWall.audibleGain;
    // #endregion listen

    return 'listener at 0, sound past the wall at 4: gain '
        '${gainBehindWall.toStringAsFixed(3)}, muffle '
        '${muffleBehindWall.toStringAsFixed(2)}\n'
        'listener moved to 5, same side as the sound now: gain '
        '${gainSameSide.toStringAsFixed(3)}';
  }

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) =>
      Container(
        color: const Color(0xFF14161A),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.topLeft,
        child: DefaultTextStyle(
          style: const TextStyle(color: Color(0xFFE8E8EC), fontSize: 16),
          child: Text(_report),
        ),
      );

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the wall marker was not drawn');
    }
    if (!_report.contains('muffle 0.50')) {
      throw StateError(
        'a sound heard through the wall should be muffled '
        'by half',
      );
    }
  }
}
