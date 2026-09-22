/// `gfx-19n`: the published pass order, held against a compiled frame.
///
///     flutter test test/pass_order_test.dart
///
/// **A document that drifts from the strings is worse than no document.**
/// `RenderSettings.disabledPasses` is typed against exact node names — the
/// graph rejects anything it does not recognise, which is the whole reason a
/// misspelling is not a switch that silently does nothing — so the list of
/// those names is API. Prose cannot be typed into a set, and a list of names
/// nobody compares with the engine is prose with quotes around it.
///
/// So this test does the comparison: it compiles a frame with everything
/// switched on and asks whether what the engine registered is what
/// `RenderSettings.passOrder` says it registers. A pass added without joining
/// the list fails here, which is the only place it can fail.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

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
      LightNode(intensity: 4.0, castsShadow: true)
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
Set<String> _registered(FrameResult result) => <String>{
  ...result.passes.map((p) => p.name),
  ...result.skipped.map((s) => s.name),
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

  test('every published name can actually be typed into disabledPasses', () {
    // **The claim the list exists to make.** Not that the strings look right,
    // but that each one is accepted where a caller would put it — the graph
    // refuses an unknown name, so this is the assertion that the list is a
    // key space rather than a description of one.
    for (final name in RenderSettings.passOrder) {
      if (RenderSettings.undisablePasses.contains(name)) continue;
      expect(
        () => _frame(
          settings: _everything.copyWith(disabledPasses: <String>{name}),
        ),
        returnsNormally,
        reason: '"$name" is published and was refused',
      );
    }
  });

  test('the three that cannot be switched off are the three published', () {
    // The compile enforces this and the list reports it, so the two have to
    // agree: a caller subtracting `undisablePasses` from `passOrder` must get
    // a set that works, and every name they subtracted must be one that would
    // have thrown.
    for (final name in RenderSettings.undisablePasses) {
      expect(
        () => _frame(
          settings: _everything.copyWith(disabledPasses: <String>{name}),
        ),
        throwsA(isA<Object>()),
        reason: '"$name" is published as undisableable and was accepted',
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

  test('the measurement set is drawn from the same key space', () {
    // `forMeasurement` subtracts names; if it subtracted a name nothing
    // registers, the graph would throw on every measurement frame. That it
    // has not is luck until this holds it.
    expect(
      RenderSettings.pixelAlteringPasses.difference(
        RenderSettings.passOrder.toSet(),
      ),
      isEmpty,
    );
  });
}
