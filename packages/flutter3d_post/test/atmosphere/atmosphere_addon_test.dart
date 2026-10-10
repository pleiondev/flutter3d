/// The atmosphere family as plugins.
///
///     dart test test/atmosphere_addon_test.dart
///
/// Each effect is a view plugin and the switch of its step, the sky's step
/// being this package's own; installing the family moves nothing in the
/// frame; switching one off takes it out and says so, and switching it back
/// on puts it back.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show PluginApiVersion, PluginTouches;
import 'package:flutter3d_post/atmosphere.dart';
import 'package:test/test.dart';

import 'frame_stage.dart';

void main() {
  test('every effect is a view plugin on plugin API 1.0', () {
    for (final addon in atmosphereAddons) {
      final manifest = addon.manifest;
      expect(manifest.idProblem, isNull, reason: manifest.id);
      expect(manifest.id, startsWith('flutter3d_addon_atmosphere.'));
      expect(manifest.touches, PluginTouches.view, reason: manifest.id);
      expect(manifest.apiVersion, const PluginApiVersion(1, 0));
    }
    expect(const FogAddon().provides, <RenderStep>[RenderStep.fog]);
    expect(const VolumetricFogAddon().provides, <RenderStep>[
      RenderStep.volumetricFog,
    ]);
    expect(const LightShaftsAddon().provides, <RenderStep>[
      RenderStep.lightShafts,
    ]);
    expect(const SkyAddon().adds, <RenderStep>[skyStep]);
    expect(const SkyAddon().provides, <RenderStep>[skyStep]);
  });

  test('the sky step is switched by the sky setting', () {
    // Mutation: switch the sky off by its intensity instead of `enabled`,
    // and a gradient sky survives its plugin.
    final on = const RenderSettings(sky: SkySettings(enabled: true));
    expect(skyStep.isOn(on), isTrue);
    expect(skyStep.switchOff(on).sky.enabled, isFalse);
    expect(skyStep.isBuiltIn, isFalse);
  });

  test('installed, the frame does not move, and the sky is a step', () {
    final installed = FrameStage()..install(atmosphereAddons);
    for (final settings in <RenderSettings>[
      const RenderSettings(),
      everything,
    ]) {
      expect(installed.plan(settings), FrameStage().plan(settings));
    }
    expect(installed.renderer.renderSteps.named('sky'), same(skyStep));
  });

  test('switched off, the volumetric fog is withdrawn and reported', () {
    final stage = FrameStage();
    final host = stage.install(atmosphereAddons);
    expect(stage.passes(everything), contains('volumetric fog'));

    host
      ..disable(const VolumetricFogAddon().id)
      ..applyPending(1);
    expect(stage.passes(everything), isNot(contains('volumetric fog')));
    expect(stage.skips(everything), contains('volumetric fog: switched off'));

    host
      ..enable(const VolumetricFogAddon().id)
      ..applyPending(2);
    expect(stage.plan(everything), FrameStage().plan(everything));
  });

  test('switched off, the sky and the fog are named in the frame', () {
    final stage = FrameStage();
    stage.install(atmosphereAddons)
      ..disable(const SkyAddon().id)
      ..disable(const FogAddon().id)
      ..applyPending(1);
    // Neither owns a pass, so only a drawn frame names them. Mutation: take
    // the step out of `withdrawn` when its `addStep` is cancelled, and the
    // sky is drawn again with its plugin off.
    expect(stage.renderer.renderSteps.withdrawn, <RenderStep>{
      skyStep,
      RenderStep.fog,
    });
    expect(
      stage.drawnSkips(everything),
      containsAll(<String>['sky: switched off', 'fog: switched off']),
    );
  });
}
