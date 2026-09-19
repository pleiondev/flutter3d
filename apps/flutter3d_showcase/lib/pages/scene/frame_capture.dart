/// A frame recorded pass by pass, with the pixels each pass wrote.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class FrameCaptureDemo extends ShowcaseDemo {
  late final FrameCapture _capture;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 5.0
      ..pitch = 0.2
      ..yaw = 0.4;
  }

  @override
  Future<void> prepare(DemoContext context) async {
    // #region probe
    final Scene probe = Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3.all(1.2)).build(),
          ),
          Material(name: 'probe', baseColor: Vector4(0.85, 0.42, 0.18, 1.0)),
          name: 'probe cube',
        ),
      )
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -0.8, -0.3)),
      );
    final CameraNode probeCamera = CameraNode()
      ..setPosition(0.0, 0.0, 4.0)
      ..lookAt(Vector3.zero());
    probe.add(probeCamera);
    // #endregion probe

    // #region capture
    final Future<FrameCapture> pending = context.renderer.captureNextFrame();
    context.renderer.render(
      width: 96,
      height: 96,
      scene: probe,
      views: <RenderView>[RenderView(camera: probeCamera)],
      settings: const RenderSettings(),
    );
    _capture = await pending;
    // #endregion capture
  }

  @override
  Scene build(DemoContext context) {
    // #region scene
    final Scene scene = Scene()
      ..ambientColor = Vector3(0.42, 0.48, 0.64)
      ..ambientIntensity = 0.16
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            const TorusShape(radius: 1.0, tubeRadius: 0.4).build(),
          ),
          Material(
            name: 'torus',
            baseColor: Vector4(0.28, 0.62, 0.9, 1.0),
            roughness: 0.4,
          ),
          name: 'torus',
        ),
      )
      ..add(
        LightNode(name: 'sun', intensity: 3.2)
          ..setLocalForward(Vector3(-0.42, -0.8, -0.34)),
      );
    // #endregion scene
    return scene;
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    final CapturedPass? scenePass = _capture.passNamed('scene');
    final CapturedImage? colour = scenePass?.imageOf('hdr_colour');
    if (scenePass == null ||
        !scenePass.active ||
        colour == null ||
        colour.isBlack ||
        frame.drawCalls < 1) {
      throw StateError('the captured frame did not record a lit scene pass');
    }
    // #endregion check
  }
}
