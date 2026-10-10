/// The reflections family as plugins.
///
///     dart test test/reflections_addon_test.dart
///
/// Each effect is a view plugin and the switch of its step; installing the
/// family moves nothing in the frame; switching one off takes its passes out
/// and says so, and switching it back on puts them back.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show PluginApiVersion, PluginTouches;
import 'package:flutter3d_post/reflections.dart';
import 'package:test/test.dart';

import 'frame_stage.dart';

void main() {
  test('every effect is a view plugin on plugin API 1.0', () {
    for (final addon in reflectionsAddons) {
      final manifest = addon.manifest;
      expect(manifest.idProblem, isNull, reason: manifest.id);
      expect(manifest.id, startsWith('flutter3d_addon_reflections.'));
      expect(manifest.touches, PluginTouches.view, reason: manifest.id);
      expect(manifest.apiVersion, const PluginApiVersion(1, 0));
    }
    expect(const ScreenSpaceReflectionsAddon().provides, <RenderStep>[
      RenderStep.reflections,
    ]);
    expect(const PlanarReflectionsAddon().provides, <RenderStep>[
      RenderStep.planarReflections,
    ]);
    expect(const ReflectionProbesAddon().provides, <RenderStep>[
      RenderStep.reflectionProbes,
    ]);
  });

  test('installed, the frame does not move', () {
    final installed = FrameStage()..install(reflectionsAddons);
    for (final settings in <RenderSettings>[
      const RenderSettings(),
      everything,
    ]) {
      expect(installed.plan(settings), FrameStage().plan(settings));
    }
  });

  test('switched off, each step is withdrawn and reported', () {
    final stage = FrameStage();
    final host = stage.install(reflectionsAddons);
    expect(
      stage.passes(everything),
      containsAll(<String>[
        'reflection probe 0',
        'planar reflections',
        'reflections',
      ]),
    );

    host
      ..disable(const ReflectionProbesAddon().id)
      ..disable(const PlanarReflectionsAddon().id)
      ..disable(const ScreenSpaceReflectionsAddon().id)
      ..applyPending(1);
    // Mutation: drop the `settings = renderSteps._framed(settings)` line from
    // `Renderer.planFrame`, and all three still run with their plugins off.
    final passes = stage.passes(everything);
    expect(passes, isNot(contains('reflection probe 0')));
    expect(passes, isNot(contains('planar reflections')));
    expect(passes, isNot(contains('reflections')));
    expect(
      stage.skips(everything),
      containsAll(<String>[
        'reflection probe 0: switched off',
        'planar reflections: switched off',
        'reflections: switched off',
      ]),
    );

    host
      ..enable(const ReflectionProbesAddon().id)
      ..enable(const PlanarReflectionsAddon().id)
      ..enable(const ScreenSpaceReflectionsAddon().id)
      ..applyPending(2);
    expect(stage.plan(everything), FrameStage().plan(everything));
  });
}
