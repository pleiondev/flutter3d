/// `RenderSettings.disabledPasses` and `FrameResult.skipped` — `gfx-37n`,
/// `gfx-38n` and `gfx-39n`, against a real `Renderer` rather than a bare
/// graph, because the claim is about frames and not about list arithmetic.
///
///     flutter test test/disabled_passes_test.dart
///
/// The graph-level cases live in `frame_graph_test.dart`, over `TestNode`,
/// where the version chain can be read directly. What can only be checked
/// here is that the engine's own nodes carry the names a caller is expected
/// to type, and that switching one off by name reaches the same frame as
/// switching it off through its own settings object.
library;

import 'package:flutter3d_core/src/engine/render/frame_graph.dart';
import 'package:flutter3d_core/src/engine/render/render_view.dart';
import 'package:flutter3d_core/src/engine/render/renderer.dart';
import 'package:flutter3d_core/src/engine/scene/camera_node.dart';
import 'package:flutter3d_core/src/engine/scene/scene.dart';
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
  group('a pass switched off by name — gfx-37n', () {
    test('disabling "bloom" by name matches disabling it by its own setting', () {
      // **The row's whole claim in one assertion.** If these two frames differ,
      // the toggle is a second way to be almost off rather than the same way,
      // and every golden recorded against the settings flag stops describing
      // the frame a caller gets from the name.
      final byFlag = renderWith(
        const RenderSettings(bloom: BloomSettings(enabled: false)),
      );
      final byName = renderWith(
        const RenderSettings(disabledPasses: <String>{'bloom'}),
      );

      expect(ran(byName), ran(byFlag));
      expect(ran(byName), isNot(contains('bloom')));
    });

    test('a default frame runs bloom, so the test above is not vacuous', () {
      expect(ran(renderWith(const RenderSettings())), contains('bloom'));
    });

    test('switching one pass off leaves the rest of the chain running', () {
      // The version-skip semantics, seen from the outside: the composite reads
      // the scene colour and still runs, because an inactive link consumes no
      // version and the next reader binds what came before it.
      final result = renderWith(
        const RenderSettings(disabledPasses: <String>{'bloom'}),
      );

      expect(ran(result), contains('composite'));
      expect(ran(result), contains('scene'));
    });

    test('a misspelled pass name is refused, not ignored', () {
      // 'fxaa' is the plausible wrong guess for the node called 'antialias',
      // and the frame a caller would get is exactly the frame they asked to
      // change.
      expect(
        () =>
            renderWith(const RenderSettings(disabledPasses: <String>{'fxaa'})),
        throwsA(
          isA<FrameGraphError>().having(
            (e) => e.message,
            'message',
            allOf(contains('"fxaa"'), contains('antialias')),
          ),
        ),
      );
    });

    test('the scene and the composite refuse to be switched off', () {
      for (final name in <String>['scene', 'composite']) {
        expect(
          () => renderWith(RenderSettings(disabledPasses: <String>{name})),
          throwsA(isA<FrameGraphError>()),
          reason: 'a frame with no picture is a refusal, not a frame',
        );
      }
    });
  });

  group('reflections, registered like every other post node — gfx-38n', () {
    test('with reflections off the node is registered and skipped by name', () {
      // Until this row the renderer registered the node inside
      // `if (s.reflections.enabled)`, so with reflections off there was no
      // node to report on at all — `skipped` could not name it and
      // `disabledPasses: {'reflections'}` would have been a misspelling.
      final result = renderWith(const RenderSettings());

      expect(ran(result), isNot(contains('reflections')));
      expect(
        result.skipped.map((s) => s.name),
        contains('reflections'),
        reason: 'registered and inactive, not absent',
      );
    });

    test(
      'reflections can be switched off by name, which needs it registered',
      () {
        // The acceptance that would have been impossible before the row: a name
        // nothing registers is rejected, so this call throwing would mean the
        // node is still hidden behind the `if`.
        expect(
          () => renderWith(
            const RenderSettings(disabledPasses: <String>{'reflections'}),
          ),
          returnsNormally,
        );
      },
    );
  });

  group('why a pass did not run — gfx-39n', () {
    test('the four answers are told apart on a real frame', () {
      // `culled` gives one answer where there are four. These are the two a
      // caller of this engine actually meets: an effect they switched off, and
      // an effect the graph dropped because nothing consumed it.
      final result = renderWith(
        const RenderSettings(
          bloom: BloomSettings(enabled: false),
          disabledPasses: <String>{'antialias'},
        ),
      );

      expect(result.skipReasonOf('bloom'), PassSkip.settings);
      expect(result.skipReasonOf('antialias'), PassSkip.disabled);
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

      for (final name in RenderSettings.pixelAlteringPasses) {
        expect(
          result.skipReasonOf(name),
          PassSkip.disabled,
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
