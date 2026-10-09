/// The shading family as plugins.
///
///     dart test test/shading_addon_test.dart
///
/// Each effect is a view plugin and the switch of its step; installing the
/// family moves nothing in the frame; switching one off takes its passes out
/// and says so, and switching it back on puts them back.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show PluginApiVersion, PluginTouches;
import 'package:flutter3d_post/shading.dart';
import 'package:test/test.dart';

import 'frame_stage.dart';

void main() {
  test('every effect is a view plugin on plugin API 1.0', () {
    for (final addon in shadingAddons) {
      final manifest = addon.manifest;
      expect(manifest.idProblem, isNull, reason: manifest.id);
      expect(manifest.id, startsWith('flutter3d_addon_shading.'));
      expect(manifest.touches, PluginTouches.view, reason: manifest.id);
      expect(manifest.apiVersion, const PluginApiVersion(1, 0));
    }
    // Mutation: give the contact shadows the occlusion's step, and the two
    // plugins switch the same passes.
    expect(const AmbientOcclusionAddon().provides, <RenderStep>[
      RenderStep.ambientOcclusion,
    ]);
    expect(const ContactShadowsAddon().provides, <RenderStep>[
      RenderStep.contactShadows,
    ]);
  });

  test('installed, the frame does not move', () {
    final installed = FrameStage()..install(shadingAddons);
    for (final settings in <RenderSettings>[
      const RenderSettings(),
      everything,
    ]) {
      expect(installed.plan(settings), FrameStage().plan(settings));
    }
  });

  test('switched off, the occlusion is withdrawn and reported', () {
    final stage = FrameStage();
    final host = stage.install(shadingAddons);
    expect(
      stage.passes(everything),
      containsAll(<String>['ssao', 'ssao blur']),
    );

    host
      ..disable(const AmbientOcclusionAddon().id)
      ..applyPending(1);
    // Mutation: apply the withdrawn steps in `render` alone, not in
    // `planFrame`, and the plan still runs the occlusion.
    expect(stage.passes(everything), isNot(contains('ssao')));
    expect(stage.passes(everything), isNot(contains('ssao blur')));
    expect(stage.skips(everything), contains('ssao: switchedOff'));
    // The other effect of the family is untouched.
    expect(stage.passes(everything), contains('contact shadows'));

    host
      ..enable(const AmbientOcclusionAddon().id)
      ..applyPending(2);
    expect(stage.plan(everything), FrameStage().plan(everything));
  });
}
