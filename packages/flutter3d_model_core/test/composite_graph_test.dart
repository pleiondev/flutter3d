/// `CompositeGraph` — `pro-rn-03`: the fixed chain, read off `RenderSettings`
/// and written back, and what one edit reaches.
///
///     dart test test/composite_graph_test.dart
library;

import 'package:flutter3d_core/flutter3d_core.dart'
    show BloomSettings, LookSettings, RenderSettings;
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';

RenderSettings lit() => const RenderSettings(
  tonemap: true,
  bloom: BloomSettings(enabled: true, threshold: 1.1),
);

void main() {
  group('the chain', () {
    test('is seven passes, in order, with two of them fixed', () {
      expect(CompositePass.values, hasLength(7));
      for (var i = 0; i < CompositePass.values.length; i++) {
        expect(CompositePass.values[i].at, i);
      }
      expect(CompositePass.scene.fixed, isTrue);
      expect(CompositePass.output.fixed, isTrue);
      expect(CompositePass.bloom.fixed, isFalse);
      expect(CompositePass.named('bloom'), CompositePass.bloom);
      expect(CompositePass.named('nothing'), isNull);
    });

    test('reads off the settings and writes back the same chain', () {
      final RenderSettings from = lit();
      final CompositeGraph graph = CompositeGraph.of(from);

      expect(graph.isOn(CompositePass.bloom), isTrue);
      expect(graph.isOn(CompositePass.tonemap), isTrue);
      expect(graph.isOn(CompositePass.ambientOcclusion), isFalse);
      // **The row's own round trip.** Mutation: describe the frame in a
      // second value of this file's own and leave the settings behind. There
      // are then two descriptions of one frame and something has to keep
      // them in step.
      final CompositeGraph back = CompositeGraph.of(graph.settings(from));
      expect(back.enabled, graph.enabled);
    });

    test('a look that does nothing reads as a pass that is off', () {
      expect(
        CompositeGraph.of(const RenderSettings()).isOn(CompositePass.look),
        isFalse,
      );
      expect(
        CompositeGraph.of(
          const RenderSettings(look: LookSettings(contrast: 1.2)),
        ).isOn(CompositePass.look),
        isTrue,
      );
    });

    test('and the fixed passes cannot be switched off', () {
      final CompositeGraph graph = CompositeGraph.of(lit())
          .withPass(CompositePass.scene, on: false)
          .withPass(CompositePass.output, on: false);
      expect(graph.isOn(CompositePass.scene), isTrue);
      expect(graph.isOn(CompositePass.output), isTrue);
    });
  });

  group('switching a pass', () {
    test('keeps its numbers, so switching it back brings them with it', () {
      final RenderSettings from = lit();
      final CompositeGraph off = CompositeGraph.of(
        from,
      ).withPass(CompositePass.bloom, on: false);
      final RenderSettings without = off.settings(from);

      expect(without.bloom.enabled, isFalse);
      // **Mutation: write a default `BloomSettings` when the pass goes off.**
      // A person who had tuned the threshold loses it by unticking a box,
      // which is the one thing a switch must never do.
      expect(without.bloom.threshold, closeTo(1.1, 1e-9));

      final RenderSettings on = off
          .withPass(CompositePass.bloom, on: true)
          .settings(without);
      expect(on.bloom.enabled, isTrue);
      expect(on.bloom.threshold, closeTo(1.1, 1e-9));
    });
  });

  group('what an edit reaches', () {
    test('editing bloom marks the post branch and nothing before it', () {
      final RenderSettings from = lit();
      final (:settings, :graph) = renderPost(
        from,
        CompositeGraph.of(from),
        bloom: const BloomSettings(enabled: true, threshold: 0.4),
      );

      expect(settings.bloom.threshold, closeTo(0.4, 1e-9));
      // **The row's own "editing bloom marks only the post branch".**
      // Mutation: mark the whole chain. A renderer then redraws the scene,
      // the ambient occlusion and the reflections for every frame of a
      // slider drag — a frame's worth of geometry for a number that cannot
      // change any of them.
      expect(graph.dirty, contains(CompositePass.bloom));
      expect(graph.dirty, contains(CompositePass.tonemap));
      expect(graph.dirty, contains(CompositePass.output));
      expect(graph.dirty, isNot(contains(CompositePass.scene)));
      expect(graph.dirty, isNot(contains(CompositePass.ambientOcclusion)));
      expect(graph.dirty, isNot(contains(CompositePass.reflections)));
    });

    test('and a graph nobody edited has a clean branch', () {
      expect(CompositeGraph.of(lit()).dirty, isEmpty);
    });

    test('editing the look reaches less than editing bloom', () {
      final RenderSettings from = lit();
      final (settings: _, :graph) = renderPost(
        from,
        CompositeGraph.of(from),
        look: const LookSettings(saturation: 1.3),
      );
      expect(graph.dirty, contains(CompositePass.look));
      expect(graph.dirty, isNot(contains(CompositePass.bloom)));
      expect(graph.dirty.length, lessThan(CompositePass.values.length));
    });

    test('switching a pass dirties from that pass on', () {
      final CompositeGraph graph = CompositeGraph.of(
        lit(),
      ).withPass(CompositePass.ambientOcclusion, on: true);
      expect(graph.dirty, contains(CompositePass.ambientOcclusion));
      expect(graph.dirty, contains(CompositePass.bloom));
      expect(graph.dirty, isNot(contains(CompositePass.scene)));
    });

    test('and one call can edit two passes at once', () {
      final RenderSettings from = lit();
      final (:settings, :graph) = renderPost(
        from,
        CompositeGraph.of(from),
        bloom: const BloomSettings(enabled: false),
        tonemap: false,
      );
      expect(settings.tonemap, isFalse);
      expect(graph.dirty, contains(CompositePass.bloom));
    });
  });

  test('it prints the chain it stands for', () {
    expect(CompositeGraph.of(lit()).toString(), contains('scene → bloom'));
  });
}
