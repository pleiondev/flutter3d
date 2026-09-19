/// How many sounds may play at once, and which ones win when more than that
/// are asking to be heard.
///
/// Quoted by `voice_limit.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class VoiceLimitDemo extends ShowcaseDemo {
  late final String _report;

  @override
  Scene build(DemoContext context) {
    _report = _run();
    final material = Material(
      name: 'crowd',
      baseColor: Vector4(0.7, 0.4, 0.7, 1.0),
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
    // A scene with room for three voices, asked for five.
    final scene = AudioScene(backend: SilentBackend(), maxVoices: 3);
    const footstep = SoundDef(name: 'footstep', asset: 'step.wav', priority: 0);
    const shout = SoundDef(name: 'shout', asset: 'shout.wav', priority: 10);
    // #endregion scene

    // #region crowd
    for (var i = 0; i < 4; i++) {
      scene.play(footstep, Vector3(i.toDouble(), 0.0, 0.0));
    }
    final loudOne = scene.play(shout, Vector3(0.0, 0.0, 3.0));
    const requested = 5;
    scene.update(AudioListener());
    // #endregion crowd

    // #region read
    // A one-shot that lost the vote for a voice is dropped on the same
    // update that decided it, which is why what is left over answers both
    // questions at once.
    final gotVoice = scene.voiceCount;
    final shoutWon = loudOne.audibleGain > 0.0;
    // #endregion read

    return '$gotVoice of $requested requested sounds got a voice; '
        'the rest, being one-shots, are already gone\n'
        'the higher-priority shout is one of them: $shoutWon';
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
      throw StateError('the crowd marker was not drawn');
    }
    if (!_report.contains('3 of 5 requested sounds got a voice')) {
      throw StateError(
        'a scene limited to three voices should give exactly '
        'three of five sounds one',
      );
    }
    if (!_report.contains('is one of them: true')) {
      throw StateError(
        'a higher-priority sound should win a voice over a '
        'lower-priority one',
      );
    }
  }
}
