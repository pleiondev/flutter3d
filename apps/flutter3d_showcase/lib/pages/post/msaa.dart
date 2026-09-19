/// Automatic multisampling: smoothed edges from the scene pass itself, with
/// no extra pass and no texture read back.
///
/// Quoted by `msaa.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/pages/post/post_stage.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class MsaaDemo extends ShowcaseDemo {
  bool readSurface = false;

  late final bool _deviceCanMsaa;

  @override
  void configureView(DemoContext context) => PostStage.frame(context);

  @override
  Scene build(DemoContext context) {
    // #region ask
    _deviceCanMsaa = context.device.supportsOffscreenMsaa;
    // #endregion ask
    return PostStage.build(context).scene;
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region compete
    ambientOcclusion: AmbientOcclusionSettings(enabled: readSurface),
    // #endregion compete
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Ambient occlusion (reads the surface buffer)',
      value: () => readSurface,
      onChanged: (bool v) => readSurface = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region declined
    final String? declined = frame.antiAliasing.msaaDeclined;
    if (!_deviceCanMsaa) {
      if (declined == null) {
        throw StateError(
          'this device cannot multisample and the frame '
          'did not say so',
        );
      }
    } else if (readSurface) {
      if (declined == null || frame.antiAliasing.msaaSamples > 1) {
        throw StateError(
          'the surface buffer is in use and the scene pass '
          'still multisampled',
        );
      }
    } else {
      if (declined != null || frame.antiAliasing.msaaSamples <= 1) {
        throw StateError(
          'nothing stopped multisampling and the scene pass '
          'did not use it',
        );
      }
    }
    // #endregion declined
  }
}
