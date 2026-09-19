/// A group of sounds a player can turn down as one, and the mixer that reads
/// every bus's own volume against a shared master.
///
/// Quoted by `audio_buses.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class AudioBusesDemo extends ShowcaseDemo {
  double musicVolume = 0.6;
  double masterVolume = 1.0;

  late final Mixer _mixer;

  @override
  Scene build(DemoContext context) {
    // #region mixer
    _mixer = Mixer();
    // #endregion mixer

    final material = Material(
      name: 'mixer',
      baseColor: Vector4(0.5, 0.9, 0.9, 1.0),
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

  // #region set
  void _apply() {
    _mixer
      ..setVolume(AudioBus.music, musicVolume)
      ..setVolume(AudioBus.master, masterVolume);
  }
  // #endregion set

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) {
    _apply();
    // #region read
    final musicGain = _mixer.gainFor(AudioBus.music);
    final sfxGain = _mixer.gainFor(AudioBus.sfx);
    // #endregion read
    return Container(
      color: const Color(0xFF14161A),
      padding: const EdgeInsets.all(24),
      alignment: Alignment.topLeft,
      child: DefaultTextStyle(
        style: const TextStyle(color: Color(0xFFE8E8EC), fontSize: 16),
        child: Text(
          'music plays at ${musicGain.toStringAsFixed(2)} of full volume\n'
          'sfx, never configured, plays at ${sfxGain.toStringAsFixed(2)} '
          '(unset buses stay full until a game turns them down)',
        ),
      ),
    );
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Music volume',
      min: 0,
      max: 1,
      value: () => musicVolume,
      onChanged: (double v) => musicVolume = v,
    ),
    SliderControl(
      'Master volume',
      min: 0,
      max: 1,
      value: () => masterVolume,
      onChanged: (double v) => masterVolume = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the mixer marker was not drawn');
    }
    _apply();
    if (_mixer.gainFor(AudioBus.sfx) != 1.0) {
      throw StateError('a bus nobody configured should stay at full volume');
    }
    masterVolume = 0.5;
    _apply();
    if ((_mixer.gainFor(AudioBus.music) - 0.3).abs() > 1e-9) {
      throw StateError(
        'music at 0.6 through a master turned to 0.5 should play at 0.3',
      );
    }
  }
}
