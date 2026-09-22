/// The fourth backend, tried before WebGL2 only when a web build asks for
/// it by name at compile time.
///
/// Quoted by `backend_webgpu.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class BackendWebgpuDemo extends ShowcaseDemo {
  late final GraphicsDevice _device;

  @override
  Scene build(DemoContext context) {
    _device = context.device;
    final Material stone = Material(
      name: 'stone',
      baseColor: Vector4(0.55, 0.4, 0.65, 1.0),
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

  // #region flag
  // Trying WebGPU is a build-time choice, not a runtime one, because
  // finding out whether a browser hands out an adapter means asking, and
  // asking means the WebGPU device, its encoder and its WGSL are all
  // reachable code the moment a build opts in:
  //
  //     flutter build web --dart-define=FLUTTER3D_WEBGPU=true
  //
  // An ordinary build never registers it, so a build that did not ask never
  // ships the bytes either.
  // #endregion flag

  // #region read
  String _report(GraphicsDevice device) =>
      'wireframe: ${device.supportsWireframe}\n'
      'blend constant: ${device.supportsBlendColor}\n'
      'max colour attachments: ${device.maxColorAttachments}';
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
        'WebGPU has a blend factor for a constant colour but no way to split '
        'it between colour and alpha the way this engine\'s blend states '
        'ask, and no polygon fill mode at all, so it declines a blend '
        'constant and wireframe by name rather than quietly doing nothing '
        'with either.\n\n'
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
    // A modern API opens several colour attachments in one pass; the one
    // capability this page names, maxColorAttachments, has to actually
    // answer more than the bare minimum on the device that opened.
    if (_device.maxColorAttachments < 2) {
      throw StateError(
        'the open device answers fewer colour attachments than this page '
        'claims a modern backend offers',
      );
    }
  }
}
