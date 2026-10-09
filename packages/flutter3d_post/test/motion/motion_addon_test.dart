/// The motion family as plugins.
///
///     dart test test/motion_addon_test.dart
///
/// Each effect is a view plugin and the switch of its step; installing the
/// family moves nothing in the frame; switching one off takes its passes out
/// and says so, and switching it back on puts them back.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show PluginApiVersion, PluginTouches;
import 'package:flutter3d_post/motion.dart';
import 'package:test/test.dart';

import 'frame_stage.dart';

void main() {
  test('every effect is a view plugin on plugin API 1.0', () {
    for (final addon in motionAddons) {
      final manifest = addon.manifest;
      expect(manifest.idProblem, isNull, reason: manifest.id);
      expect(manifest.id, startsWith('flutter3d_addon_motion.'));
      expect(manifest.touches, PluginTouches.view, reason: manifest.id);
      expect(manifest.apiVersion, const PluginApiVersion(1, 0));
    }
    expect(const DepthOfFieldAddon().provides, <RenderStep>[
      RenderStep.depthOfField,
    ]);
    expect(const MotionBlurAddon().provides, <RenderStep>[
      RenderStep.motionBlur,
    ]);
    expect(const TemporalAntiAliasingAddon().provides, <RenderStep>[
      RenderStep.temporalAntiAliasing,
    ]);
  });

  test('installed, the frame does not move', () {
    final installed = FrameStage()..install(motionAddons);
    for (final settings in <RenderSettings>[
      const RenderSettings(),
      everything,
    ]) {
      expect(installed.plan(settings), FrameStage().plan(settings));
    }
  });

  test('without the resolve, the upscale that was asked for appears', () {
    final stage = FrameStage();
    final host = stage.install(motionAddons);
    expect(stage.passes(everything), contains('temporal resolve'));
    expect(stage.passes(everything), isNot(contains('spatial upscale')));

    host
      ..disable(const TemporalAntiAliasingAddon().id)
      ..applyPending(1);
    // The withdrawn step is the setting switched off, so the frame is the
    // one `without` draws, the upscale included. Mutation: withdraw a step
    // by suppressing its passes instead, and the upscale stays out.
    expect(
      stage.plan(everything),
      FrameStage().plan(
        everything.without(<RenderStep>{RenderStep.temporalAntiAliasing}),
      ),
    );
    expect(stage.passes(everything), isNot(contains('temporal resolve')));
    expect(stage.passes(everything), contains('spatial upscale'));

    host
      ..enable(const TemporalAntiAliasingAddon().id)
      ..applyPending(2);
    expect(stage.plan(everything), FrameStage().plan(everything));
  });
}
