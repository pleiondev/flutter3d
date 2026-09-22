/// `LightNode.channels` against `SceneNode.lightChannels`: a light reaches an
/// object only when the two bit masks share a bit.
///
/// Quoted by `light_channels.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class LightChannelsDemo extends ShowcaseDemo {
  bool sameChannel = false;

  late final LightNode _redLight;
  late final MeshNode _redBall;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 6.0
      ..pitch = 0.15;
  }

  @override
  Scene build(DemoContext context) {
    final DeviceMesh sphere = DeviceMesh.upload(
      context.device,
      SphereShape(segments: 32, rings: 16).build(),
    );

    // #region channels
    // Channel 0 for the near ball and its own light, channel 1 for the far
    // one: the mask a light and a node meet on decides whether it reaches it,
    // never distance or anything the shader has to guess about.
    _redBall = MeshNode(
      sphere,
      Material(baseColor: Vector4(0.8, 0.8, 0.8, 1.0)),
      name: 'near ball',
    )..lightChannels = LightChannels.only(0);
    final MeshNode farBall =
        MeshNode(
            sphere,
            Material(baseColor: Vector4(0.8, 0.8, 0.8, 1.0)),
            name: 'far ball',
          )
          ..setPosition(2.4, 0.0, 0.0)
          ..lightChannels = LightChannels.only(1);

    _redLight = LightNode(name: 'red', type: LightType.point, intensity: 6.0)
      ..color.setValues(1.0, 0.25, 0.2)
      ..channels = LightChannels.only(0)
      ..setPosition(0.0, 1.6, 1.2);
    // #endregion channels

    final LightNode fill = LightNode(name: 'fill', intensity: 1.2)
      ..setLocalForward(Vector3(-0.3, -0.6, -0.6));

    return Scene()
      ..add(_redBall)
      ..add(farBall)
      ..add(_redLight)
      ..add(fill);
  }

  @override
  void update(DemoContext context, double dt) {
    // #region live
    // With the toggle on, the near ball opens its second bit too and the
    // light starts reaching it exactly as it always reached the far one.
    _redBall.lightChannels = sameChannel
        ? (LightChannels.only(0) | LightChannels.only(1))
        : LightChannels.only(0);
    // #endregion live
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Near ball also on channel 1',
      value: () => sameChannel,
      onChanged: (bool v) => sameChannel = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (!LightBuffer.reaches(_redLight, _redBall.lightChannels)) {
      throw StateError('the red light does not reach the ball it lights');
    }
    if (_redLight.channels == LightChannels.all) {
      throw StateError('the light was never restricted to a channel');
    }
    if (frame.drawCalls < 2) {
      throw StateError('not every ball was drawn');
    }
    // #endregion check
  }
}
