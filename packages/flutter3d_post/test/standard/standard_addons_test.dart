/// The `standard` preset: the six families in one list.
///
///     dart test test/standard_addons_test.dart
///
/// **The claim is that it changes nothing.** Installed, the frame is the one
/// a renderer with no addon plans, for the default settings and for every
/// step on, each step switched off alone and kept alone — the sweep
/// `flutter3d_cpu/test/goldens/frame_order.jsonl` holds the kernel to. Then
/// what it covers: every step outside the kernel has a provider, and none of
/// the kernel's has.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_post/standard.dart';
import 'package:test/test.dart';

import 'frame_stage.dart';

/// The steps the kernel keeps: the scene's own, the shadows, tone mapping
/// and the edge smoothing every frame needs.
const Set<RenderStep> _kernel = <RenderStep>{
  RenderStep.shadows,
  RenderStep.caustics,
  RenderStep.irradianceUpdate,
  RenderStep.renderTextures,
  RenderStep.decals,
  // The split around the glass, which follows content rather than a
  // setting, and the copy of the opaque half it reads: the scene's own.
  RenderStep.transparent,
  RenderStep.sceneColorCopy,
  RenderStep.hiZOcclusion,
  RenderStep.tonemap,
  RenderStep.spatialUpscale,
  RenderStep.edgeSmoothing,
  RenderStep.sharpening,
};

void main() {
  test('installs every family, each plugin once, dependencies first', () {
    final ids = <String>[for (final addon in standardAddons) addon.id];
    expect(ids.toSet(), hasLength(ids.length));
    expect(ids, hasLength(22));
    final host = FrameStage().install(standardAddons);
    // Mutation: drop a family from the list, and its steps have no
    // provider below.
    expect(host.statuses.every((s) => s.enabled), isTrue);
    expect(
      host.order.indexOf(const BloomAddon().id),
      lessThan(host.order.indexOf(const LensFlareAddon().id)),
    );
  });

  test('every step outside the kernel is provided, and none inside it', () {
    final stage = FrameStage()..install(standardAddons);
    final steps = stage.renderer.renderSteps;
    for (final step in RenderStep.values) {
      expect(
        steps.providerOf(step),
        _kernel.contains(step) ? isNull : isNotNull,
        reason: step.name,
      );
    }
    expect(steps.providerOf(skyStep), isNotNull);
    expect(steps.providerOf(outlinesStep), isNotNull);
  });

  test('installed, the frame does not move', () {
    final bare = FrameStage();
    final installed = FrameStage()..install(standardAddons);
    for (final (label, base) in <(String, RenderSettings)>[
      ('default', const RenderSettings()),
      ('everything', everything),
    ]) {
      expect(installed.plan(base), bare.plan(base), reason: label);
      for (final step in RenderStep.values) {
        // Mutation: have `RendererSteps._framed` return
        // `settings.without(withdrawn)` even when nothing is withdrawn, and
        // the record of `stepsOff` this builds differs from the bare one.
        final without = base.without(<RenderStep>{step});
        expect(
          installed.plan(without),
          bare.plan(without),
          reason: '$label without ${step.name}',
        );
        final only = base.only(<RenderStep>{step});
        expect(
          installed.plan(only),
          bare.plan(only),
          reason: '$label only ${step.name}',
        );
      }
    }
  });

  test('a renderer with no addon draws what the preset draws', () {
    // The 1.0 promise from the other side: nothing provided is nothing
    // withdrawn, so an application that never heard of addons sees no
    // change. Mutation: treat a step nobody provides as withdrawn, and
    // every effect disappears from the bare renderer.
    final bare = FrameStage();
    expect(bare.renderer.renderSteps.withdrawn, isEmpty);
    expect(bare.passes(everything), contains('bloom'));
  });
}
