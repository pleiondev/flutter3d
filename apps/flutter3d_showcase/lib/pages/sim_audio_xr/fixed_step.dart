/// A simulation that always advances by the same amount, and a picture that
/// still moves smoothly when the display and the simulation disagree about
/// how fast time passes.
///
/// Quoted by `fixed_step.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class FixedStepDemo extends ShowcaseDemo {
  bool menuOpen = false;

  // #region clock
  final FixedStep _clock = FixedStep(stepSeconds: 1 / 60);
  final InterpolatedVector3 _position = InterpolatedVector3();
  int _stepsRun = 0;
  // #endregion clock

  late final MeshNode _ball;
  final Vector3 _drawn = Vector3.zero();

  @override
  Scene build(DemoContext context) {
    final material = Material(
      name: 'marker',
      baseColor: Vector4(0.8, 0.5, 0.2, 1.0),
      roughness: 0.6,
    );
    _ball = MeshNode(
      DeviceMesh.upload(context.device, SphereShape(segments: 24).build()),
      material,
      name: 'marker',
    );
    return Scene()
      ..add(_ball)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  // #region gate
  /// Whether the step should run at all this frame.
  ///
  /// `shouldPause` answers from facts about the player's attention, not from
  /// a device: a menu open is reason enough on its own, whatever pointer or
  /// pad is connected.
  bool get _paused => shouldPause(
    ready: true,
    menuOpen: menuOpen,
    pointerIsTheGate: false,
    pointerHeld: false,
    padConnected: false,
  );
  // #endregion gate

  @override
  void update(DemoContext context, double dt) {
    if (_paused) return;
    // #region advance
    final steps = _clock.advance(dt);
    for (var i = 0; i < steps; i++) {
      _stepsRun++;
      final x = (_stepsRun * _clock.stepSeconds * 1.5) % 2.0 - 1.0;
      _position.push(Vector3(x, 0.0, 0.0));
    }
    // #endregion advance

    // #region blend
    _position.read(_clock.alpha, _drawn);
    _ball.setPositionFrom(_drawn);
    // #endregion blend
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Menu open (pauses the step)',
      value: () => menuOpen,
      onChanged: (bool v) => menuOpen = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the marker was not drawn');
    }
    // One frame of exactly one step's worth of time runs exactly one step:
    // the accumulator starts empty and this page's step is 1/60 second.
    if (_stepsRun != 1) {
      throw StateError(
        'a 1/60s frame should have run exactly one fixed step, ran $_stepsRun',
      );
    }
  }
}
