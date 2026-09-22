/// The software rasteriser: no driver, no shading language, no command
/// buffer, and no GPU underneath any of it.
///
/// Quoted by `backend_cpu.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class BackendCpuDemo extends ShowcaseDemo {
  late final GraphicsDevice _device;

  @override
  Scene build(DemoContext context) {
    _device = context.device;
    final Material stone = Material(
      name: 'stone',
      baseColor: Vector4(0.6, 0.6, 0.65, 1.0),
      roughness: 0.7,
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

  // #region read
  String _report(GraphicsDevice device) =>
      'preferred sample count: ${device.preferredSampleCount}\n'
      'offscreen MSAA: ${device.supportsOffscreenMsaa}\n'
      'wireframe: ${device.supportsWireframe}\n'
      'stencil: ${device.supportsStencil}\n'
      'mip maps: ${device.supportsMipmaps}';
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
        'This build asked flutter3d_hardware\'s registry for a backend and '
        'got the software rasteriser: no driver, no shading language, no '
        'command buffer, so a backend agreeing with the hardware ones proves '
        'something.\n\n${_report(context.device)}',
      ),
    ),
  );

  // #region verify
  void _checkNoMultisampling() {
    if (_device.preferredSampleCount != 1 || _device.supportsOffscreenMsaa) {
      throw StateError(
        'the software rasteriser answering anything but "no multisampling" '
        'would be a silent difference from the picture a hardware backend '
        'draws',
      );
    }
  }
  // #endregion verify

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the ball was not drawn');
    }
    _checkNoMultisampling();
  }
}
