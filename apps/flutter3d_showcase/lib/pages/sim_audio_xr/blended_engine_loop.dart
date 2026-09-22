/// Several loops of the same engine, recorded at different revs, crossfaded
/// by one number so the change from one recording to the next is not heard.
///
/// Quoted by `blended_engine_loop.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class BlendedEngineLoopDemo extends ShowcaseDemo {
  double revs = 0.5;

  late final AudioScene _scene;
  late final BlendedLoop _engine;

  @override
  Scene build(DemoContext context) {
    _scene = AudioScene(backend: SilentBackend());

    // #region bands
    _engine = BlendedLoop(
      scene: _scene,
      bands: <LoopBand>[
        LoopBand(
          sound: const SoundDef(name: 'idle', asset: 'idle.wav', loop: true),
          centre: 0.2,
        ),
        LoopBand(
          sound: const SoundDef(name: 'mid', asset: 'mid.wav', loop: true),
          centre: 0.6,
        ),
        LoopBand(
          sound: const SoundDef(name: 'high', asset: 'high.wav', loop: true),
          centre: 1.0,
        ),
      ],
    );
    // #endregion bands

    final material = Material(
      name: 'engine',
      baseColor: Vector4(0.8, 0.3, 0.2, 1.0),
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

  // #region update
  @override
  void update(DemoContext context, double dt) {
    _engine.update(revs);
    _scene.update(AudioListener());
  }
  // #endregion update

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Engine revs',
      min: 0.0,
      max: 1.2,
      value: () => revs,
      onChanged: (double v) => revs = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the engine marker was not drawn');
    }
    // #region loudness
    // The bands are normalised, so the total weight is one wherever the
    // revs sit, including exactly between two bands.
    revs = 0.4;
    _engine.update(revs);
    var total = 0.0;
    for (var i = 0; i < 3; i++) {
      total += _engine.gainOf(i);
    }
    // #endregion loudness
    if ((total - 1.0).abs() > 1e-6) {
      throw StateError(
        'the bands should always sum to full loudness, '
        'summed to $total',
      );
    }
  }
}
