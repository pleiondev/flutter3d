/// A sound placed somewhere in the world, heard louder or softer and panned
/// left or right depending on where the listener stands and faces.
///
/// A `SilentBackend` runs this page: it makes no sound and records every
/// voice it is asked for, which is what lets the numbers below be checked
/// without a speaker or a browser's audio stack.
///
/// Quoted by `positional_audio.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class PositionalAudioDemo extends ShowcaseDemo {
  late final String _report;

  @override
  Scene build(DemoContext context) {
    _report = _run();
    final material = Material(
      name: 'source',
      baseColor: Vector4(0.8, 0.7, 0.3, 1.0),
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

  static String _run() {
    // #region scene
    final backend = SilentBackend();
    final scene = AudioScene(backend: backend);
    const bell = SoundDef(name: 'bell', asset: 'bell.wav');
    // #endregion scene

    // #region play
    final emitter = scene.play(bell, Vector3(4.0, 0.0, 0.0));
    final listener = AudioListener()..aimAt(Vector3.zero(), 0.0);
    scene.update(listener);
    // #endregion play

    final farGain = emitter.audibleGain;
    final farPan = emitter.pan;

    // #region move
    // The listener turns to face the source directly and steps closer.
    listener.aimAt(Vector3(2.0, 0.0, 0.0), -1.5707963267948966);
    scene.update(listener);
    // #endregion move

    return 'four metres to the side: gain ${farGain.toStringAsFixed(3)}, '
        'pan ${farPan.toStringAsFixed(2)}\n'
        'two metres away and facing it: gain '
        '${emitter.audibleGain.toStringAsFixed(3)}, pan '
        '${emitter.pan.toStringAsFixed(2)}';
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
      throw StateError('the source marker was not drawn');
    }
    if (!_report.contains('pan 1.00')) {
      throw StateError(
        'a source straight to the right of the listener '
        'should pan hard right',
      );
    }
  }
}
