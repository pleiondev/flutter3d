/// The light family as plugins.
///
///     dart test test/light_addon_test.dart
///
/// Three claims. Each effect is a view plugin named for this package, and
/// the switch of the step it says. Installing the whole family moves nothing
/// in the frame. Switching one off takes its step, and whatever needs it,
/// out of the frame and says so, and switching it back on puts it back.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show PluginApiVersion, PluginTouches;
import 'package:flutter3d_post/light.dart';
import 'package:test/test.dart';

import 'frame_stage.dart';

void main() {
  group('the manifests', () {
    test('every effect is a view plugin on plugin API 1.0', () {
      for (final addon in lightAddons) {
        final manifest = addon.manifest;
        expect(manifest.idProblem, isNull, reason: manifest.id);
        expect(manifest.id, startsWith('flutter3d_addon_light.'));
        // Mutation: make `RenderStepAddon.manifest` a simulation plugin, and
        // a replay starts recording every bloom switched.
        expect(manifest.touches, PluginTouches.view, reason: manifest.id);
        expect(manifest.apiVersion, const PluginApiVersion(1, 0));
      }
      expect(lightAddons.map((a) => a.id).toSet(), hasLength(7));
    });

    test('each provides the step it is named for', () {
      expect(const BloomAddon().provides, <RenderStep>[RenderStep.bloom]);
      expect(const LensFlareAddon().provides, <RenderStep>[
        RenderStep.lensFlare,
      ]);
      expect(const AutoExposureAddon().provides, <RenderStep>[
        RenderStep.autoExposure,
      ]);
      expect(const LocalExposureAddon().provides, <RenderStep>[
        RenderStep.localExposure,
      ]);
      expect(const ColorGradeAddon().provides, <RenderStep>[
        RenderStep.colorGrade,
      ]);
      expect(const LensDistortionAddon().provides, <RenderStep>[
        RenderStep.lensDistortion,
      ]);
      expect(const VignetteAndGrainAddon().provides, <RenderStep>[
        RenderStep.vignetteAndGrain,
      ]);
    });

    test('the flare depends on the bloom it is drawn from', () {
      // Mutation: drop the flare's `dependsOn`, and installing it alone is
      // accepted with nothing to draw from.
      expect(const LensFlareAddon().manifest.dependsOn, <String>[
        const BloomAddon().id,
      ]);
    });
  });

  group('installed', () {
    test('the frame does not move', () {
      final bare = FrameStage();
      final installed = FrameStage()..install(lightAddons);
      for (final settings in <RenderSettings>[
        const RenderSettings(),
        everything,
      ]) {
        expect(installed.plan(settings), bare.plan(settings));
      }
      // Mutation: have `RendererSteps.provide` add the step to `withdrawn`
      // instead of taking it out, and every effect of the family is gone.
      expect(installed.renderer.renderSteps.withdrawn, isEmpty);
      for (final addon in lightAddons) {
        expect(
          installed.renderer.renderSteps.providerOf(addon.provides.single),
          'plugin "${addon.id}"',
        );
      }
    });

    test('switched off, a step is withdrawn and reported', () {
      final stage = FrameStage();
      final host = stage.install(lightAddons);
      expect(stage.passes(everything), containsAll(<String>['bloom']));

      host
        ..disable(const LensFlareAddon().id)
        ..disable(const BloomAddon().id)
        ..applyPending(1);
      // Mutation: forget to track the provide's registration, and the bloom
      // is still drawn with its plugin off.
      expect(stage.renderer.renderSteps.withdrawn, <RenderStep>{
        RenderStep.bloom,
        RenderStep.lensFlare,
      });
      expect(
        stage.passes(everything),
        isNot(anyOf(contains('bloom'), contains('lens flare'))),
      );
      expect(
        stage.skips(everything),
        containsAll(<String>['bloom: switched off', 'lens flare: switched off']),
      );

      host
        ..enable(const BloomAddon().id)
        ..enable(const LensFlareAddon().id)
        ..applyPending(2);
      expect(stage.renderer.renderSteps.withdrawn, isEmpty);
      expect(stage.plan(everything), FrameStage().plan(everything));
    });

    test(
      'the film is arithmetic in the composite, and switches all the same',
      () {
        final stage = FrameStage();
        stage.install(lightAddons)
          ..disable(const VignetteAndGrainAddon().id)
          ..applyPending(1);
        // No pass of its own disappears; the step is named switched off, as
        // `without` names it.
        expect(stage.passes(everything), FrameStage().passes(everything));
        expect(
          stage.drawnSkips(everything),
          contains('vignette and grain: switched off'),
        );
      },
    );
  });
}
