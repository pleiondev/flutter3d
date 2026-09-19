/// The surface buffer: the world normal and view-axis depth the scene pass
/// writes for every screen-space effect to share, put on the screen raw.
///
/// Quoted by `surface_buffer.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/pages/post/post_stage.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class SurfaceBufferDemo extends ShowcaseDemo {
  bool show = true;

  late final bool _deviceCanMsaa;

  @override
  void configureView(DemoContext context) => PostStage.frame(context);

  @override
  Scene build(DemoContext context) {
    _deviceCanMsaa = context.device.supportsOffscreenMsaa;
    return PostStage.build(context).scene;
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region show
    showSurfaceBuffer: show,
    // #endregion show
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Show the buffer',
      value: () => show,
      onChanged: (bool v) => show = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region consumed
    // Asking to see the buffer is asking the scene pass to write it, which on
    // a device that can otherwise multisample costs the frame that
    // multisampling for exactly the reason `msaa` explains.
    final String? declined = frame.antiAliasing.msaaDeclined;
    if (!_deviceCanMsaa) {
      if (declined == null) {
        throw StateError('this device cannot multisample and did not say so');
      }
    } else if (show) {
      if (declined == null) {
        throw StateError('showing the buffer should have cost multisampling');
      }
    } else if (declined != null) {
      throw StateError('nothing here reads the buffer, and it still declined');
    }
    // #endregion consumed
  }
}
