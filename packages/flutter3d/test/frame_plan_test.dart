import 'package:flutter_test/flutter_test.dart';

import 'package:flutter3d/src/engine/render/frame_plan.dart';

void main() {
  List<String> order({
    bool directionalShadows = true,
    bool pointShadows = true,
    bool reflections = false,
    bool bloom = true,
    int overlays = 0,
  }) =>
      describeFrame(
        directionalShadows: directionalShadows,
        pointShadows: pointShadows,
        reflections: reflections,
        bloom: bloom,
        overlays: overlays,
      ).order.map((n) => n.name).toList();

  surfaceBufferAgreementTests();

  test('the default frame comes out in the order the renderer runs today', () {
    // The check that matters before anything is moved: the graph, given only
    // what each pass touches, arrives at the sequence `render()` currently
    // hard-codes. If it did not, the migration would be changing the frame
    // rather than restructuring it.
    expect(
      order(),
      <String>[
        'directional shadows',
        'point shadows',
        'scene',
        'bloom',
        'composite',
      ],
    );
  });

  test('shadows come before the scene that samples them', () {
    final result = order();
    expect(result.indexOf('directional shadows'), lessThan(result.indexOf('scene')));
    expect(result.indexOf('point shadows'), lessThan(result.indexOf('scene')));
  });

  test('reflections run before bloom, so a reflected light still glows', () {
    final result = order(reflections: true);
    expect(result.indexOf('reflections'), lessThan(result.indexOf('bloom')));
  });

  test('overlays draw after the scene and before the post chain', () {
    final result = order(overlays: 2);
    expect(result.indexOf('scene'), lessThan(result.indexOf('overlay 0')));
    expect(result.indexOf('overlay 0'), lessThan(result.indexOf('overlay 1')));
    expect(result.indexOf('overlay 1'), lessThan(result.indexOf('bloom')));
  });

  group('what the switches cull', () {
    test('bloom off drops its pass and keeps the picture', () {
      // The composite must survive: it declares only the colour it always
      // needs, and treats a missing glow the way the shader does. A composite
      // that read the bloom would be culled with it and the frame would go
      // black.
      final result = order(bloom: false);
      expect(result, isNot(contains('bloom')));
      expect(result, contains('composite'));
      expect(result, contains('scene'));
    });

    test('shadows off drop their passes and keep the scene', () {
      final result = order(directionalShadows: false, pointShadows: false);
      expect(result, isNot(contains('directional shadows')));
      expect(result, isNot(contains('point shadows')));
      expect(result, contains('scene'));
    });

    test('reflections are absent unless asked for', () {
      expect(order(), isNot(contains('reflections')));
      expect(order(reflections: true),
          contains('reflections'));
    });

    test('the surface buffer is attached only when something reads it', () {
      // What `RenderSettings.needsSurfaceBuffer` computes by hand from three
      // flags today. The scene always declares the write; whether a texture is
      // ever asked for is decided by whether a surviving pass reads it.
      expect(describeFrame().isConsumed(FrameResourceIds.surfaceBuffer), isFalse);
      expect(
        describeFrame(reflections: true)
            .isConsumed(FrameResourceIds.surfaceBuffer),
        isTrue,
      );
    });

    test('everything off still produces a frame', () {
      final result = order(
        directionalShadows: false,
        pointShadows: false,
        bloom: false,
      );
      expect(result, <String>['scene', 'composite']);
    });
  });
}

/// The plan's answer and the hand-computed one must agree on every
/// combination, because the renderer now asks the plan and the old getter is
/// still public API. Four booleans is sixteen cases and they are free to walk,
/// which is a better argument than picking two and hoping.
void surfaceBufferAgreementTests() {
  test('the graph agrees with the flag it replaces, on every combination', () {
    for (final surfaceBuffer in <bool>[false, true]) {
      for (final showSurfaceBuffer in <bool>[false, true]) {
        for (final showPointShadowDebug in <bool>[false, true]) {
          for (final reflections in <bool>[false, true]) {
            final byHand = surfaceBuffer ||
                showSurfaceBuffer ||
                showPointShadowDebug ||
                reflections;
            final byGraph = describeFrame(
              reflections: reflections,
              showSurfaceBuffer: showSurfaceBuffer || showPointShadowDebug,
              explicitSurfaceBuffer: surfaceBuffer,
            ).isConsumed(FrameResourceIds.surfaceBuffer);

            expect(byGraph, byHand,
                reason: 'surfaceBuffer=$surfaceBuffer '
                    'showSurfaceBuffer=$showSurfaceBuffer '
                    'showPointShadowDebug=$showPointShadowDebug '
                    'reflections=$reflections');
          }
        }
      }
    }
  });
}
