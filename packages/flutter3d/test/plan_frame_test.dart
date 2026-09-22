/// `gfx-41n`: what a frame would do, worked out without drawing it.
///
///     flutter test test/plan_frame_test.dart
///
/// **The test that matters is the agreement one.** A dry run is worth nothing
/// unless it answers what the drawn frame answers, and the way to be sure is
/// not to read both implementations but to run them against the same scene and
/// compare — which is what most of this file does, over the settings that
/// change the shape of the graph.
///
/// The second claim is that it needs no device to be able to draw. A fake
/// backend that records passes can still plan; so, in principle, can a device
/// that would refuse every one of them, which is how an application answers
/// "would this scene get occlusion here" during start-up instead of after the
/// first frame.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A scene with a caster, a point light and geometry: enough that the shadow
/// passes, the atlas and the scene pass are all real.
Scene _scene() => Scene()
  ..add(
    LightNode(intensity: 4.0, castsShadow: true)
      ..setPosition(3.0, 4.0, 5.0)
      ..lookAt(Vector3.zero()),
  )
  ..add(
    LightNode(type: LightType.point, intensity: 3.0, castsShadow: true)
      ..setPosition(-2.0, 1.0, 0.0),
  )
  ..add(CameraNode()..setPosition(0.0, 0.0, 5.0));

List<RenderView> _views(Scene scene) => <RenderView>[
  RenderView(camera: scene.cameras.single),
];

/// The names a plan says would run, and the names a drawn frame ran.
({List<String> planned, List<String> drawn}) _both(RenderSettings settings) {
  final renderer = Renderer.create(device: FakeBackend());
  final scene = _scene();
  final views = _views(scene);

  final plan = renderer.planFrame(
    scene: scene,
    views: views,
    settings: settings,
  );
  final drawn = renderer.render(
    width: 64,
    height: 64,
    scene: scene,
    views: views,
    settings: settings,
  );

  return (
    planned: plan.order.map((n) => n.name).toList(),
    drawn: drawn.passes.map((p) => p.name).toList(),
  );
}

void main() {
  group('the plan agrees with the frame', () {
    test('on a default frame', () {
      final both = _both(const RenderSettings());
      expect(both.planned, both.drawn);
      expect(both.drawn, isNotEmpty, reason: 'otherwise this compares nothing');
    });

    test('with every effect switched on', () {
      // The settings that change the *shape* of the graph rather than the
      // numbers in it: each of these adds a node and three of them add a
      // reader of the surface buffer.
      final both = _both(
        const RenderSettings(
          bloom: BloomSettings(intensity: 0.8),
          ambientOcclusion: AmbientOcclusionSettings(
            enabled: true,
            blurTaps: 4,
          ),
          reflections: ReflectionSettings(enabled: true),
          lightShafts: LightShaftSettings(enabled: true),
          depthOfField: DepthOfFieldSettings(enabled: true),
          antiAlias: AntiAliasSettings(enabled: true),
          autoExposure: AutoExposureSettings(enabled: true),
        ),
      );
      expect(both.planned, both.drawn);
      expect(both.drawn, contains('ssao'));
    });

    test('with a pass switched off by name', () {
      final both = _both(
        const RenderSettings(
          bloom: BloomSettings(intensity: 0.8),
          disabledPasses: <String>{'bloom'},
        ),
      );
      expect(both.planned, both.drawn);
      expect(both.drawn, isNot(contains('bloom')));
    });

    test('with shadows off, which takes three passes with it', () {
      final both = _both(
        const RenderSettings(shadows: ShadowSettings(enabled: false)),
      );
      expect(both.planned, both.drawn);
      expect(both.drawn, isNot(contains('directional shadows')));
    });
  });

  group('the plan says why, not only what', () {
    test('a pass switched off by name is reported as disabled', () {
      final renderer = Renderer.create(device: FakeBackend());
      final scene = _scene();
      final plan = renderer.planFrame(
        scene: scene,
        views: _views(scene),
        settings: const RenderSettings(
          bloom: BloomSettings(intensity: 0.8),
          disabledPasses: <String>{'bloom'},
        ),
      );

      expect(<String, PassSkip>{
        for (final s in plan.skipped) s.name: s.reason,
      }, containsPair('bloom', PassSkip.disabled));
    });

    test('and a pass the device cannot run is reported as unsupported', () {
      // `gfx-50n`'s reason, reaching a caller before a frame is drawn — which
      // is the case this row is most worth having for: an application can find
      // out at start-up that occlusion will never run on this device, rather
      // than shipping a settings screen offering it.
      final renderer = Renderer.create(
        device: FakeBackend(maxColorAttachments: 1),
      );
      final scene = _scene();
      final plan = renderer.planFrame(
        scene: scene,
        views: _views(scene),
        settings: const RenderSettings(
          ambientOcclusion: AmbientOcclusionSettings(enabled: true),
        ),
      );

      expect(<String, PassSkip>{
        for (final s in plan.skipped) s.name: s.reason,
      }, containsPair('ssao', PassSkip.unsupported));
    });
  });

  group('planning changes nothing', () {
    test('a frame drawn after a plan is the frame drawn without one', () {
      // **The claim that makes the allocations worth it.** The plan runs its
      // own light buffer and its own shadow-slot allocator; if it used the
      // renderer's, a plan would hand out atlas rows to a frame that is never
      // drawn and the next real frame would find its bookkeeping moved.
      List<String> drawnAfter({required bool planFirst}) {
        final renderer = Renderer.create(device: FakeBackend());
        final scene = _scene();
        final views = _views(scene);
        const settings = RenderSettings(
          shadows: ShadowSettings(enabled: true),
          bloom: BloomSettings(intensity: 0.8),
        );
        if (planFirst) {
          renderer.planFrame(scene: scene, views: views, settings: settings);
        }
        return renderer
            .render(
              width: 64,
              height: 64,
              scene: scene,
              views: views,
              settings: settings,
            )
            .passes
            .map((p) => p.name)
            .toList();
      }

      expect(drawnAfter(planFirst: true), drawnAfter(planFirst: false));
    });

    test('a plan draws nothing at all', () {
      // Measured on the fake, which records every pass anybody opens: a dry
      // run that opened one would be a frame with extra steps.
      final device = FakeBackend();
      final renderer = Renderer.create(device: device);
      final scene = _scene();
      final before = device.passes.length;

      renderer.planFrame(scene: scene, views: _views(scene));

      expect(device.passes.length, before);
    });

    test('planning twice answers the same thing twice', () {
      // A plan that moved state would drift, and drifting is exactly what
      // would not be noticed in a diagnostic somebody calls once.
      final renderer = Renderer.create(device: FakeBackend());
      final scene = _scene();
      final views = _views(scene);

      final first = renderer.planFrame(scene: scene, views: views);
      final second = renderer.planFrame(scene: scene, views: views);

      expect(
        second.order.map((n) => n.name),
        first.order.map((n) => n.name).toList(),
      );
    });
  });

  test('a plan needs a view, like a frame does', () {
    final renderer = Renderer.create(device: FakeBackend());
    expect(
      () => renderer.planFrame(scene: _scene(), views: const <RenderView>[]),
      throwsArgumentError,
    );
  });
}
