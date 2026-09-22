/// Switching a pass off by its name, and asking the frame what became of it.
///
/// Quoted by `disabled_passes.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/pages/post/post_stage.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class DisabledPassesDemo extends ShowcaseDemo {
  // #region names
  /// The passes this scene turns on, in the order the frame runs them.
  static final List<String> switchable = <String>[
    for (final String name in RenderSettings.passOrder)
      if (const <String>{
        'directional shadows',
        'ssao',
        'contact shadows',
        'bloom',
        'antialias',
      }.contains(name))
        name,
  ];
  // #endregion names

  final Set<String> disabled = <String>{'bloom'};

  @override
  void configureView(DemoContext context) => PostStage.frame(context);

  @override
  Scene build(DemoContext context) =>
      PostStage.build(context, shadows: true).scene;

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    ambientOcclusion: const AmbientOcclusionSettings(
      enabled: true,
      radius: 0.8,
    ),
    contactShadows: const ContactShadowSettings(enabled: true),
    antiAlias: const AntiAliasSettings(enabled: true),
    bloom: const BloomSettings(intensity: 0.3),
    // #region disabled
    disabledPasses: <String>{...disabled},
    // #endregion disabled
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    for (final String name in switchable)
      ToggleControl(
        'Skip $name',
        value: () => disabled.contains(name),
        onChanged: (bool skip) =>
            skip ? disabled.add(name) : disabled.remove(name),
      ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region report
    for (final String name in disabled) {
      final PassSkip? why = frame.skipReasonOf(name);
      if (why != PassSkip.disabled) {
        throw StateError('"$name" was named and the frame says $why');
      }
    }
    // #endregion report
    if (!passRan(frame, 'composite')) {
      throw StateError('the composite pass is the frame and it did not run');
    }
  }
}
