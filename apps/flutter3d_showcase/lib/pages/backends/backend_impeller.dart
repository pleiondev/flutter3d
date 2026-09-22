/// The desktop and mobile path: `flutter_gpu`, through Impeller, the first
/// backend `openDevice` tries on a native build.
///
/// Quoted by `backend_impeller.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class BackendImpellerDemo extends ShowcaseDemo {
  late final GraphicsDevice _device;

  @override
  Scene build(DemoContext context) {
    _device = context.device;
    final Material stone = Material(
      name: 'stone',
      baseColor: Vector4(0.72, 0.5, 0.32, 1.0),
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
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  // #region fallback
  // `flutter3d_app`'s native `openDevice` never names a backend. It asks
  // `flutter3d_hardware`'s registry to open one, having first made sure
  // Impeller and the software rasteriser have both registered themselves:
  //
  //     ensureGpuBackendRegistered();
  //     ensureCpuBackendRegistered();
  //     return openRegisteredDevice(width: width, height: height, ...);
  //
  // Impeller is tried first; the software device is what a native build
  // falls back to if flutter_gpu will not start.
  // #endregion fallback

  // #region settings
  @override
  RenderSettings settings(DemoContext context) =>
      const RenderSettings(wireframe: true);
  // #endregion settings

  // #region read
  String _report(GraphicsDevice device) =>
      'wireframe: ${device.supportsWireframe}\n'
      'blend constant: ${device.supportsBlendColor}\n'
      'max colour attachments: ${device.maxColorAttachments}\n'
      'max anisotropy: ${device.maxAnisotropy}';
  // #endregion read

  @override
  Widget? customBody(
    BuildContext buildContext,
    DemoContext context,
  ) => Container(
    color: const Color(0xFF14161A),
    padding: const EdgeInsets.all(24),
    alignment: Alignment.topLeft,
    child: DefaultTextStyle(
      style: const TextStyle(color: Color(0xFFE8E8EC), fontSize: 16),
      child: Text(
        'On Metal and Vulkan, Impeller answers true to wireframe and can '
        'open more than one colour attachment; on its OpenGL ES path a '
        'second attachment aborts the process outright, which is why '
        'nothing above this asks for one without asking maxColorAttachments '
        'first. It answers false to a blend constant on every platform, '
        'because flutter_gpu\'s own RenderPass has no setter for one.\n\n'
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
    // Wireframe is the one capability that differs across all three
    // backends. This page asks for it unconditionally; whether the frame
    // actually got it has to match what the device that opened said it
    // could do, whichever backend that turned out to be.
    if (frame.wireframeDeclined != !_device.supportsWireframe) {
      throw StateError(
        'wireframeDeclined disagreed with supportsWireframe for the open '
        'device',
      );
    }
  }
}
