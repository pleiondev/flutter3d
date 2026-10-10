/// Switching steps of the frame off, and asking the frame what became of
/// their passes.
///
/// Quoted by `disabled_passes.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/pages/post/post_stage.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class DisabledPassesDemo extends ShowcaseDemo {
  // #region names
  /// The steps this scene turns on, in the order the frame runs them.
  static const List<RenderStep> switchable = <RenderStep>[
    RenderStep.shadows,
    RenderStep.ambientOcclusion,
    RenderStep.contactShadows,
    RenderStep.bloom,
    RenderStep.edgeSmoothing,
  ];
  // #endregion names

  final Set<RenderStep> off = <RenderStep>{RenderStep.bloom};

  @override
  void configureView(DemoContext context) => PostStage.frame(context);

  @override
  Scene build(DemoContext context) =>
      PostStage.build(context, shadows: true).scene;

  @override
  RenderSettings settings(DemoContext context) =>
      const RenderSettings(
        ambientOcclusion: AmbientOcclusionSettings(enabled: true, radius: 0.8),
        contactShadows: ContactShadowSettings(enabled: true),
        antiAlias: AntiAliasSettings(enabled: true),
        bloom: BloomSettings(intensity: 0.3),
      )
      // #region disabled
      .without(<RenderStep>{...off});
  // #endregion disabled

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    for (final RenderStep step in switchable)
      ToggleControl(
        'Skip ${step.name}',
        value: () => off.contains(step),
        onChanged: (bool skip) => skip ? off.add(step) : off.remove(step),
      ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region report
    for (final RenderStep step in off) {
      for (final String pass in step.passes) {
        final PassSkip? why = frame.skipReasonOf(pass);
        if (passRan(frame, pass) ||
            (why != null && why != PassSkip.switchedOff)) {
          throw StateError(
            '"$pass" of $step was switched off and the frame '
            'says ${why ?? 'it ran'}',
          );
        }
      }
    }
    // #endregion report
    if (!passRan(frame, 'composite')) {
      throw StateError('the composite pass is the frame and it did not run');
    }
  }
}
