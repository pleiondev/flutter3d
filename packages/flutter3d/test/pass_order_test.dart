/// `gfx-19n`: the published pass order, held against a compiled frame.
///
///     flutter test test/pass_order_test.dart
///
/// **A document that drifts from the strings is worse than no document.**
/// `FrameResult.passes` and `skipped` report exact node names, and each
/// `RenderStep` owns its passes by those names, so the list of them is API.
/// A list of names nobody compares with the engine is prose with quotes
/// around it.
///
/// So this test does the comparison: it compiles a frame with everything
/// switched on and asks whether what the engine registered is what
/// `RenderSettings.passOrder` says it registers. A pass added without joining
/// the list fails here, which is the only place it can fail.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Everything on, so nothing is missing from the frame for being switched off.
const RenderSettings _everything = RenderSettings(
  bloom: BloomSettings(intensity: 0.8),
  ambientOcclusion: AmbientOcclusionSettings(enabled: true, blurTaps: 4),
  reflections: ReflectionSettings(enabled: true),
  lightShafts: LightShaftSettings(enabled: true),
  depthOfField: DepthOfFieldSettings(enabled: true),
  antiAlias: AntiAliasSettings(enabled: true),
  autoExposure: AutoExposureSettings(enabled: true),
  shadows: ShadowSettings(enabled: true),
);

/// A frame with a caster, so the shadow passes are registered too.
FrameResult _frame({RenderSettings settings = _everything}) {
  final renderer = Renderer.create(device: FakeBackend());
  final scene = Scene()
    ..add(
      LightNode(intensity: 4.0 * Photometric.legacyUnit, castsShadow: true)
        ..setPosition(2.0, 3.0, 4.0)
        ..lookAt(Vector3.zero()),
    )
    ..add(CameraNode()..setPosition(0.0, 0.0, 4.0));
  return renderer.render(
    width: 64,
    height: 64,
    scene: scene,
    views: <RenderView>[RenderView(camera: scene.cameras.single)],
    settings: settings,
  );
}

/// Every pass the frame registered, run or not, in the order it ran them
/// followed by the ones that did not run.
///
/// `skipped` also names what the frame declined — multisampling, here,
/// since the occlusion reads the surface buffer — and those are requests
/// rather than passes, so they are left out.
Set<String> _registered(FrameResult result) => <String>{
  ...result.passes.map((p) => p.name),
  for (final skip in result.skipped)
    if (skip.reason != PassSkip.declined) skip.name,
};

void main() {
  test('every name the engine registers is in the published order', () {
    // The direction that catches a new pass: add one, forget the list, and
    // a caller reading `passOrder` gets a key space with a hole in it.
    final registered = _registered(_frame());

    expect(
      registered.difference(RenderSettings.passOrder.toSet()),
      isEmpty,
      reason:
          'a pass the engine registers and the published order does not name '
          'is a key a caller cannot discover',
    );
  });

  test('every published name is a pass the engine registers', () {
    // And the other direction, which catches a pass that was renamed or
    // removed while the list stayed: a name here that nothing registers is
    // rejected by the graph, so it would be a documented string that throws.
    final registered = _registered(_frame());

    expect(
      RenderSettings.passOrder.toSet().difference(registered),
      isEmpty,
      reason: 'a published name nothing registers is a documented throw',
    );
  });

  test('every pass a step owns is a published name', () {
    // **The claim the list exists to make.** A step switches its passes off
    // by name, so a step owning a name the frame does not register would
    // switch nothing off and report nothing, and a reader of `passOrder`
    // could not find what the step stands for.
    final published = RenderSettings.passOrder.toSet();
    for (final step in RenderStep.values) {
      expect(
        step.passes.difference(published),
        isEmpty,
        reason: '$step owns a pass the published order does not name',
      );
    }
  });

  test('the order is the order the frame runs them in', () {
    // **A list rather than a set, because the order is the version chain.**
    // Each pass reads what the ones before it left, which is what makes
    // "occlusion before bloom" a fact about the picture rather than about
    // this file. The passes that ran have to appear in the published order.
    final ran = _frame().passes.map((p) => p.name).toList();
    final expected = <String>[
      for (final name in RenderSettings.passOrder)
        if (ran.contains(name)) name,
    ];

    expect(ran.where(expected.contains).toList(), expected);
  });

  test('a probe is named by its index rather than by a constant', () {
    // The one registered pass the published list leaves out, and the reason
    // is that its count belongs to the scene. Checked by shape rather than by
    // rendering a probe, which needs a device that can make cubes.
    expect(RenderSettings.probePassName(0), 'reflection probe 0');
    expect(RenderSettings.probePassName(7), 'reflection probe 7');
    expect(
      RenderSettings.passOrder.where((n) => n.startsWith('reflection probe')),
      isEmpty,
    );
  });

  test('a measurement frame switches every pixel-altering step off', () {
    // `forMeasurement` goes through `without`; a step in the published set
    // that `without` left on would be a photograph of the numbers where the
    // numbers were asked for.
    expect(
      _everything.forMeasurement().switchedOffSteps,
      containsAll(RenderSettings.pixelAlteringSteps),
    );
  });
}
