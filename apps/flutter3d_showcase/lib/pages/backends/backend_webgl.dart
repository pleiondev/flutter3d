/// The browser path: WebGL2 over a canvas the browser composites, the
/// second implementation of `flutter3d_hardware`.
///
/// Quoted by `backend_webgl.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class BackendWebglDemo extends ShowcaseDemo {
  late final GraphicsDevice _device;

  @override
  Scene build(DemoContext context) {
    _device = context.device;
    final RenderMaterial stone = RenderMaterial(
      name: 'stone',
      baseColor: LinearColor.fromSrgb(0.4, 0.55, 0.7, 1.0),
      roughness: 0.6,
    );
    final MeshNode ball = MeshNode(
      DeviceMesh.upload(
        context.device,
        SphereShape(segments: 24, rings: 12).build(),
      ),
      stone,
      name: 'ball',
    );
    return Scene()
      ..add(ball)
      ..add(
        LightNode(name: 'sun', intensity: 3.0 * Photometric.legacyUnit)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  // #region fallback
  // On the web, `flutter3d_app`'s `openDevice` registers WebGL2 always and
  // WebGPU only when the build was compiled with
  // `--dart-define=FLUTTER3D_WEBGPU=true`. Either way it asks the shared
  // registry for a backend rather than choosing one by name:
  //
  //     final registry = DeviceRegistry();
  //     registerWebGlBackend(registry);
  //     if (tryWebGpu) registry.addBackend('WebGPU', openWebGpu);
  //     return registry.open(width: width, height: height, ...);
  //
  // A build that never asked for WebGPU never carries its code at all; a
  // canvas that only WebGL2 can open still draws.
  // #endregion fallback

  // #region settings
  @override
  RenderSettings settings(DemoContext context) =>
      const RenderSettings(wireframe: true);
  // #endregion settings

  // #region read
  String _report(GraphicsDevice device) =>
      'wireframe: ${device.features.has(DeviceFeature.wireframe)}\n'
      'offscreen MSAA: ${device.features.has(DeviceFeature.offscreenMultisample)}\n'
      'preferred samples: ${device.preferredSampleCount}\n'
      'max anisotropy: ${device.limits.maxSamplerAnisotropy}';
  // #endregion read

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) =>
      Container(
        color: const Color(0xFF14161A),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.topLeft,
        child: DefaultTextStyle(
          style: const TextStyle(color: Color(0xFFE8E8EC), fontSize: 16),
          child: Text(
            'WebGL2 has no glPolygonMode, so it answers false to wireframe the '
            'same way the software rasteriser does: drawing triangles as edges '
            'needs line primitives this API does not expose. Anisotropic '
            'filtering and multisampling both depend on extensions the browser '
            'may or may not hand back.\n\n'
            'What the device actually open right now answers:\n\n'
            '${_report(context.device)}',
          ),
        ),
      );

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the ball was not drawn');
    }
    if (frame.wireframeDeclined !=
        !_device.features.has(DeviceFeature.wireframe)) {
      throw StateError(
        'wireframeDeclined disagreed with supportsWireframe for the open '
        'device',
      );
    }
  }
}
