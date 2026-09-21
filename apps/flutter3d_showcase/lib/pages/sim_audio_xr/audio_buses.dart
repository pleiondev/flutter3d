/// A group of sounds a player can turn down as one, and the mixer that reads
/// every bus's own volume against a shared master.
///
/// Quoted by `audio_buses.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/scene_kit.dart';
import 'package:vector_math/vector_math.dart';

final class AudioBusesDemo extends ShowcaseDemo {
  double musicVolume = 0.6;
  double masterVolume = 1.0;

  late final Mixer _mixer;
  late final BarGauge _music;
  late final BarGauge _sfx;
  late final BarGauge _out;

  @override
  Scene build(DemoContext context) {
    // #region mixer
    _mixer = Mixer();
    // #endregion mixer

    _music = BarGauge(
      context,
      'music',
      Vector4(0.45, 0.65, 0.95, 1.0),
      Vector3(-2.5, 0.0, 0.0),
      width: 1.0,
      vertical: true,
    );
    _sfx = BarGauge(
      context,
      'sfx',
      Vector4(0.95, 0.75, 0.3, 1.0),
      Vector3(0.0, 0.0, 0.0),
      width: 1.0,
      vertical: true,
    );
    _out = BarGauge(
      context,
      'master',
      Vector4(0.7, 0.4, 0.8, 1.0),
      Vector3(2.5, 0.0, 0.0),
      width: 1.0,
      vertical: true,
    );
    return sceneOf(<SceneNode>[
      floorNode(context, width: 10.0, depth: 5.0),
      ..._music.nodes,
      ..._sfx.nodes,
      ..._out.nodes,
    ]);
  }

  // #region set
  void _apply() {
    _mixer
      ..setVolume(AudioBus.music, musicVolume)
      ..setVolume(AudioBus.master, masterVolume);
  }
  // #endregion set

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 9.0
      ..pitch = 0.3
      ..yaw = 0.0;
    context.orbit.target.setValues(0.0, 1.5, 0.0);
  }

  @override
  void update(DemoContext context, double dt) {
    _apply();
    // #region read
    final musicGain = _mixer.gainFor(AudioBus.music);
    final sfxGain = _mixer.gainFor(AudioBus.sfx);
    // #endregion read
    _music.set(musicGain);
    _sfx.set(sfxGain);
    _out.set(masterVolume);
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
