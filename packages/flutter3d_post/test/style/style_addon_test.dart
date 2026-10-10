/// The style family as plugins.
///
///     dart test test/style_addon_test.dart
///
/// Each effect is a view plugin and the switch of its step, the outlines'
/// being this package's own; installing the family moves nothing in the
/// frame; switching one off takes it out and says so, and switching it back
/// on puts it back.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show PluginApiVersion, PluginException, PluginTouches;
import 'package:flutter3d_post/style.dart';
import 'package:test/test.dart';

import 'frame_stage.dart';

void main() {
  test('every effect is a view plugin on plugin API 1.0', () {
    for (final addon in styleAddons) {
      final manifest = addon.manifest;
      expect(manifest.idProblem, isNull, reason: manifest.id);
      expect(manifest.id, startsWith('flutter3d_addon_style.'));
      expect(manifest.touches, PluginTouches.view, reason: manifest.id);
      expect(manifest.apiVersion, const PluginApiVersion(1, 0));
    }
    expect(const HighContrastAddon().provides, <RenderStep>[
      RenderStep.highContrast,
    ]);
    expect(const ViewportShadingAddon().provides, <RenderStep>[
      RenderStep.viewportShading,
    ]);
    expect(const OutlinesAddon().provides, <RenderStep>[outlinesStep]);
    expect(const OutlinesAddon().manifest.dependsOn, <String>[
      const HighContrastAddon().id,
    ]);
  });

  test('the outlines are switched by their width, and need the look', () {
    final on = const RenderSettings(
      highContrast: HighContrastSettings(enabled: true),
    );
    expect(outlinesStep.isOn(on), isTrue);
    // Mutation: switch the outlines off with the look itself, and switching
    // the rings off takes the whole look with them.
    final off = outlinesStep.switchOff(on);
    expect(off.highContrast.outlineWidth, 0.0);
    expect(off.highContrast.enabled, isTrue);
    expect(outlinesStep.isOn(const RenderSettings()), isFalse);
  });

  test('installed, the frame does not move', () {
    final installed = FrameStage()..install(styleAddons);
    for (final settings in <RenderSettings>[
      const RenderSettings(),
      everything,
    ]) {
      expect(installed.plan(settings), FrameStage().plan(settings));
    }
  });

  test('the look cannot be switched off under its outlines', () {
    final host = FrameStage().install(styleAddons);
    expect(
      () => host.disable(const HighContrastAddon().id),
      throwsA(isA<PluginException>()),
    );
  });

  test('switched off, the viewport shading is withdrawn and reported', () {
    final stage = FrameStage();
    final host = stage.install(styleAddons);
    expect(stage.passes(everything), contains('viewport shading'));

    host
      ..disable(const ViewportShadingAddon().id)
      ..applyPending(1);
    expect(stage.passes(everything), isNot(contains('viewport shading')));
    expect(stage.skips(everything), contains('viewport shading: switched off'));

    host
      ..enable(const ViewportShadingAddon().id)
      ..applyPending(2);
    expect(stage.plan(everything), FrameStage().plan(everything));
  });

  test('switched off, the outlines leave the look and are named', () {
    final stage = FrameStage();
    stage.install(styleAddons)
      ..disable(const OutlinesAddon().id)
      ..applyPending(1);
    expect(stage.renderer.renderSteps.withdrawn, <RenderStep>{outlinesStep});
    expect(stage.passes(everything), contains('high contrast'));
    expect(stage.drawnSkips(everything), contains('outlines: switched off'));
  });
}
