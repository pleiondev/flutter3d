/// Viewport shading: normals, clay, outline and curvature, each read out of
/// the surface buffer instead of the materials.
///
/// Quoted by `viewport_shading.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/pages/post/post_stage.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class ViewportShadingDemo extends ShowcaseDemo {
  int mode = 1;

  static const List<ViewportShading> _modes = ViewportShading.values;

  @override
  void configureView(DemoContext context) => PostStage.frame(context);

  @override
  Scene build(DemoContext context) => PostStage.build(context).scene;

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region settings
    viewportShading: ViewportShadingSettings(mode: _modes[mode]),
    // #endregion settings
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ChoiceControl(
      'Mode',
      options: <String>[for (final ViewportShading m in _modes) m.name],
      index: () => mode,
      onChanged: (int i) => mode = i,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region ran
    final ViewportShading picked = _modes[mode];
    final bool ran = frame.passes.any(
      (FramePass p) => p.name == 'viewport shading',
    );
    if (picked == ViewportShading.off) {
      if (ran) throw StateError('off should not run the pass');
    } else if (!ran) {
      throw StateError('$picked did not run: ${frame.skipped}');
    }
    // #endregion ran
  }
}
