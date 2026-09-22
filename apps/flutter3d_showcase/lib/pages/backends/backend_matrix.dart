/// A live table of what the device open right now can do, read straight off
/// `GraphicsDevice`, not off a name.
///
/// Quoted by `backend_matrix.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/capability_report.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class BackendMatrixDemo extends ShowcaseDemo {
  late final GraphicsDevice _device;
  late final CapabilityReport _atBuild;

  @override
  Scene build(DemoContext context) {
    _device = context.device;
    _atBuild = context.caps;
    final Material stone = Material(
      name: 'stone',
      baseColor: Vector4(0.5, 0.5, 0.55, 1.0),
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

  // #region rows
  List<(String, String)> _rows(GraphicsDevice device) => <(String, String)>[
    ('wireframe', '${device.supportsWireframe}'),
    ('cube textures', '${device.supportsCubeTextures}'),
    ('mip maps', '${device.supportsMipmaps}'),
    ('render into a mip level', '${device.supportsRenderToMip}'),
    ('a stencil buffer', '${device.supportsStencil}'),
    ('a blend constant', '${device.supportsBlendColor}'),
    ('offscreen MSAA', '${device.supportsOffscreenMsaa}'),
    ('max anisotropy', '${device.maxAnisotropy}'),
    ('max colour attachments', '${device.maxColorAttachments}'),
    ('preferred sample count', '${device.preferredSampleCount}'),
  ];
  // #endregion rows

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) =>
      Container(
        color: const Color(0xFF14161A),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.topLeft,
        child: DefaultTextStyle(
          style: const TextStyle(color: Color(0xFFE8E8EC), fontSize: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'What the device open right now answers to every capability '
                'question the engine asks. No name is read anywhere on this '
                'page; the table below is built entirely from the device.',
              ),
              const SizedBox(height: 16),
              for (final (String, String) row in _rows(context.device))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('${row.$1}: ${row.$2}'),
                ),
            ],
          ),
        ),
      );

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the ball was not drawn');
    }
    // #region stable
    // The capability report this page showed at build time has to still
    // agree with a fresh reading of the same device after a frame has run.
    // A backend's answers are a property of the device, not something a
    // frame could have changed.
    final CapabilityReport now = CapabilityReport.of(_device);
    if (!now.met.containsAll(_atBuild.met) ||
        !_atBuild.met.containsAll(now.met)) {
      throw StateError(
        'the device answered a capability differently after a frame',
      );
    }
    // #endregion stable
  }
}
