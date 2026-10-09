/// `RenderSettings.without` and `FrameResult.skipped` — `gfx-37n`,
/// `gfx-38n` and `gfx-39n`, against a real `Renderer` rather than a bare
/// graph, because the claim is about frames and not about list arithmetic.
///
///     flutter test test/steps_off_test.dart
///
/// The graph-level cases live in `frame_graph_test.dart`, over `TestNode`,
/// where the version chain can be read directly. What can only be checked
/// here is that the engine's own nodes carry the names its steps own, and
/// that switching a step off reaches the same frame as switching it off
/// through its own settings object. Since 1.0 a step is the only way to
/// switch a pass off: `RenderSettings.disabledPasses`, a set of node names,
/// went.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';

FrameResult renderWith(RenderSettings settings) {
  final renderer = Renderer.create(device: FakeBackend());
  final scene = Scene()..add(CameraNode());
  return renderer.render(
    width: 64,
    height: 64,
    scene: scene,
    views: <RenderView>[RenderView(camera: scene.cameras.single)],
    settings: settings,
  );
}

List<String> ran(FrameResult result) =>
    result.passes.map((p) => p.name).toList();

void main() {
  group('a step switched off — gfx-37n', () {
    test('without bloom matches bloom off by its own setting', () {
      // **The row's whole claim in one assertion.** If these two frames
      // differ, the step is a second way to be almost off rather than the
      // same way, and every golden recorded against the settings flag stops
      // describing the frame a caller gets from `without`.
      final byFlag = renderWith(
        const RenderSettings(bloom: BloomSettings(enabled: false)),
      );
      final byStep = renderWith(
        const RenderSettings().without(<RenderStep>{RenderStep.bloom}),
      );

      expect(ran(byStep), ran(byFlag));
      expect(ran(byStep), isNot(contains('bloom')));
    });

    test('a default frame runs bloom, so the test above is not vacuous', () {
      expect(ran(renderWith(const RenderSettings())), contains('bloom'));
    });

    test('switching one step off leaves the rest of the chain running', () {
      // The version-skip semantics, seen from the outside: the composite reads
      // the scene colour and still runs, because an inactive link consumes no
      // version and the next reader binds what came before it.
      final result = renderWith(
        const RenderSettings().without(<RenderStep>{RenderStep.bloom}),
      );

      expect(ran(result), contains('composite'));
      expect(ran(result), contains('scene'));
    });

    test('every step off is still a frame', () {
      // The scene and the composite are the frame rather than steps of it,
      // so no set of steps can take them out: the names a caller could once
      // type and be refused are not in the vocabulary at all.
      final result = renderWith(const RenderSettings().only(<RenderStep>{}));

      expect(ran(result), contains('scene'));
      expect(ran(result), contains('composite'));
    });

    test('a step off takes the steps that need it with it, and says so', () {
      // Mutation: drop `withDependants` from `without`. The flare is drawn
      // from the glow, so it would be left on with nothing to draw from and
      // reported for its settings rather than for the step that took it.
      final settings = const RenderSettings().without(<RenderStep>{
        RenderStep.bloom,
      });

      expect(settings.switchedOffSteps, contains(RenderStep.lensFlare));
    });
  });

  group('reflections, registered like every other post node — gfx-38n', () {
    test('with reflections off the node is registered and skipped by name', () {
      // Until this row the renderer registered the node inside
      // `if (s.reflections.enabled)`, so with reflections off there was no
      // node to report on at all — `skipped` could not name it.
      final result = renderWith(const RenderSettings());

      expect(ran(result), isNot(contains('reflections')));
      expect(
        result.skipped.map((s) => s.name),
        contains('reflections'),
        reason: 'registered and inactive, not absent',
      );
    });

    test('reflections switched off as a step are reported as such', () {
      // Which needs the node registered: a step owning a pass nothing
      // registers would switch nothing off and report nothing.
      final result = renderWith(
        const RenderSettings(
          reflections: ReflectionSettings(enabled: true),
        ).without(<RenderStep>{RenderStep.reflections}),
      );

      expect(result.skipReasonOf('reflections'), PassSkip.switchedOff);
    });
  });

  group('why a pass did not run — gfx-39n', () {
    test('the answers are told apart on a real frame', () {
      // `culled` gives one answer where there are four. These are two a
      // caller of this engine actually meets: an effect whose own setting is
      // off, and one whose step they switched off.
      final result = renderWith(
        const RenderSettings(
          bloom: BloomSettings(enabled: false),
          antiAlias: AntiAliasSettings(enabled: true),
        ).without(<RenderStep>{
          RenderStep.edgeSmoothing,
          RenderStep.sharpening,
        }),
      );

      expect(result.skipReasonOf('bloom'), PassSkip.settings);
      expect(result.skipReasonOf('antialias'), PassSkip.switchedOff);
    });

    test('a pass that ran has no reason', () {
      final result = renderWith(const RenderSettings());
      for (final pass in result.passes) {
        expect(result.skipReasonOf(pass.name), isNull);
      }
    });

    test('a measurement frame says which passes it took out, and why', () {
      // `gfx-40n` through `gfx-39n`: the reason a measurement frame looks the
      // way it does is readable off the frame, rather than being six flags a
      // caller has to go and check.
      final result = renderWith(const RenderSettings().forMeasurement());

      for (final name in <String>[
        'bloom',
        'lens flare',
        'ssao',
        'contact shadows',
        'reflections',
        'spatial upscale',
        'local exposure',
        'antialias',
        'luminance',
        'light shafts',
        'volumetric fog',
        'depth of field',
        'motion blur',
      ]) {
        expect(
          result.skipReasonOf(name),
          PassSkip.switchedOff,
          reason: '"$name" alters pixels, so a measurement frame drops it',
        );
      }
      expect(ran(result), contains('composite'));
      expect(
        ran(result),
        contains('scene'),
        reason: 'a measurement frame is still a frame',
      );
    });

    test('an agent can be told the occlusion it asked for did not run', () {
      // The caller this row exists for. Ambient occlusion is off by default,
      // so a 256-pixel render an agent asked for has no occlusion in it and
      // the picture cannot say why. This can.
      final result = renderWith(const RenderSettings());

      expect(result.skipReasonOf('ssao'), isNotNull);
    });
  });
}
