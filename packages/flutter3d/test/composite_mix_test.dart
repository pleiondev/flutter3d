import 'package:flutter3d/src/engine/render/composite_mix.dart';
import 'package:flutter3d/src/engine/render/frame_graph.dart';
import 'package:flutter3d/src/engine/render/frame_plan.dart';
import 'package:flutter3d/src/engine/render/frame_resources.dart';
import 'package:flutter3d/src/engine/render/render_node.dart';
import 'package:flutter3d_graphics/flutter3d_graphics.dart';
import 'package:flutter_test/flutter_test.dart';

/// A source that refuses to hand anything out.
///
/// The subject here is [FrameResources.tryTexture], whose entire promise is
/// that it never allocates. A source that throws makes that an assertion rather
/// than something the test takes on trust — and it is why this file needs no
/// device.
final class _NoTextures implements FrameTextureSource {
  const _NoTextures();

  @override
  TextureHandle acquire(RenderTargetSpec spec) =>
      throw StateError('tryTexture must never acquire');

  @override
  void release(TextureHandle texture) =>
      throw StateError('nothing was acquired, so nothing can be released');
}

/// A node with no body, for graphs that are only ever compiled.
final class _Pass extends RenderNode {
  const _Pass(
    this.name, {
    this.reads = const <ResourceId>[],
    this.optionalReads = const <ResourceId>[],
    this.writes = const <ResourceId>[],
    this.isActive = true,
  });

  @override
  final String name;
  @override
  final List<ResourceId> reads;
  @override
  final List<ResourceId> optionalReads;
  @override
  final List<ResourceId> writes;
  @override
  final bool isActive;

  @override
  void execute(NodeFrame frame) =>
      throw StateError('this graph is compiled, never run');
}

/// Every combination of the flags that reach the composite.
Iterable<CompositeMix> everyMix() sync* {
  for (final surface in <bool>[false, true]) {
    for (final pointShadow in <bool>[false, true]) {
      for (final shadowMap in <bool>[false, true]) {
        for (final hasShadowView in <bool>[false, true]) {
          for (final hasGlow in <bool>[false, true]) {
            for (final tonemap in <bool>[false, true]) {
              yield CompositeMix(
                showSurfaceBuffer: surface,
                showPointShadowDebug: pointShadow,
                showShadowMap: shadowMap,
                hasShadowView: hasShadowView,
                hasGlow: hasGlow,
                exposure: 1.5,
                bloomIntensity: 0.8,
                tonemap: tonemap,
              );
            }
          }
        }
      }
    }
  }
}

CompositeMix mix({
  bool showSurfaceBuffer = false,
  bool showPointShadowDebug = false,
  bool showShadowMap = false,
  bool hasShadowView = true,
  bool hasGlow = true,
  double exposure = 1.5,
  double bloomIntensity = 0.8,
  bool tonemap = true,
}) =>
    CompositeMix(
      showSurfaceBuffer: showSurfaceBuffer,
      showPointShadowDebug: showPointShadowDebug,
      showShadowMap: showShadowMap,
      hasShadowView: hasShadowView,
      hasGlow: hasGlow,
      exposure: exposure,
      bloomIntensity: bloomIntensity,
      tonemap: tonemap,
    );

void main() {
  test('the bloom slot and the bloom intensity never disagree', () {
    // The one invariant the shader cannot enforce and a golden cannot see.
    //
    // flutter_gpu crashes natively — no Dart frame, no stack — when a sampler
    // the compiled shader declares goes unbound, so the composite fills the
    // bloom slot whether or not the frame produced a glow: with bloom culled it
    // binds the scene there instead. The shader then multiplies whatever is in
    // that slot by whatever is in the uniform. Bind the stand-in and leave the
    // intensity where it was and every frame comes out with the scene added to
    // itself, which is a picture, just not the right one.
    for (final m in everyMix()) {
      expect(m.mixesGlowItDoesNotHave, isFalse, reason: '$m');
      if (!m.usesGlow) expect(m.bloomIntensity, 0.0);
    }
  });

  test('a culled bloom takes the glow with it', () {
    // The same fact from the other side: with no glow there is no intensity,
    // whatever the setting said.
    expect(mix(hasGlow: false, bloomIntensity: 0.8).usesGlow, isFalse);
    expect(mix(hasGlow: false, bloomIntensity: 0.8).bloomIntensity, 0.0);
    expect(mix(hasGlow: true, bloomIntensity: 0.8).bloomIntensity, 0.8);
  });

  test('an ordinary frame is exposed and tone mapped', () {
    final m = mix();
    expect(m.view, CompositeView.scene);
    expect(m.exposure, 1.5);
    expect(m.bloomIntensity, 0.8);
    expect(m.tonemap, 1.0);
  });

  test('tone mapping switched off is the only thing it switches off', () {
    final m = mix(tonemap: false);
    expect(m.tonemap, 0.0);
    expect(m.exposure, 1.5);
    expect(m.bloomIntensity, 0.8);
  });

  group('the debug views, which no golden image can check', () {
    // Every one of them replaces the picture *and* turns the three knobs to
    // raw, because a debug buffer holds numbers rather than light: exposure
    // would scale them, the tone mapper would roll the top of the range off,
    // and bloom would add a blurred copy of the scene to them.

    test('showSurfaceBuffer shows the buffer, raw', () {
      final m = mix(showSurfaceBuffer: true);
      expect(m.view, CompositeView.surfaceBuffer);
      expect(m.exposure, 1.0);
      expect(m.bloomIntensity, 0.0);
      expect(m.tonemap, 0.0);
    });

    test('showPointShadowDebug shows the surface buffer too', () {
      // The penumbra estimate rides in that buffer rather than in an
      // attachment of its own, so asking for the estimate is asking for the
      // buffer. Losing this is how the debug view would come back showing the
      // lit scene and looking like the estimate was fine.
      final m = mix(showPointShadowDebug: true);
      expect(m.view, CompositeView.surfaceBuffer);
      expect(m.exposure, 1.0);
      expect(m.bloomIntensity, 0.0);
      expect(m.tonemap, 0.0);
    });

    test('showShadowMap shows the map, raw, and outranks the surface buffer',
        () {
      expect(mix(showShadowMap: true).view, CompositeView.shadowMap);
      expect(mix(showShadowMap: true).exposure, 1.0);
      expect(mix(showShadowMap: true).tonemap, 0.0);
      expect(mix(showShadowMap: true).bloomIntensity, 0.0);
      // Both at once has to resolve to one texture, and the map wins.
      expect(
        mix(showShadowMap: true, showSurfaceBuffer: true).view,
        CompositeView.shadowMap,
      );
    });

    test('a shadow map nobody allocated falls back to the scene', () {
      // And falls back all the way: showing the lit scene *raw* would be a
      // second, quieter wrong picture.
      final m = mix(showShadowMap: true, hasShadowView: false);
      expect(m.view, CompositeView.scene);
      expect(m.exposure, 1.5);
      expect(m.tonemap, 1.0);
      expect(m.bloomIntensity, 0.8);
    });
  });

  group('the composite as a node', () {
    // The graph half of the same story: where the null in `hasGlow` comes from
    // now that the composite reads the glow instead of being handed it.

    const scene = _Pass(
      'scene',
      writes: <ResourceId>[FrameResourceIds.hdrColour],
    );
    const composite = _Pass(
      'composite',
      reads: <ResourceId>[FrameResourceIds.hdrColour],
      optionalReads: <ResourceId>[FrameResourceIds.bloom],
      writes: <ResourceId>[FrameResourceIds.frame],
    );

    CompiledFrameGraph compile({required bool bloom}) => (FrameGraph()
          ..addNode(scene)
          ..addNode(_Pass(
            'bloom',
            reads: const <ResourceId>[FrameResourceIds.hdrColour],
            writes: const <ResourceId>[FrameResourceIds.bloom],
            isActive: bloom,
          ))
          ..addNode(composite))
        .compile(outputs: const <ResourceId>[FrameResourceIds.frame]);

    test('bloom switched off is a culled node, not a branch', () {
      // The point of the step. The composite still runs; nothing else about
      // the frame is conditional.
      final off = compile(bloom: false);
      expect(off.order.map((n) => n.name), <String>['scene', 'composite']);
      expect(off.culled.map((n) => n.name), <String>['bloom']);

      final on = compile(bloom: true);
      expect(on.order.map((n) => n.name),
          <String>['scene', 'bloom', 'composite']);
      expect(on.culled, isEmpty);
    });

    test('the glow of a culled bloom is null rather than a texture', () {
      // Which is the whole mechanism behind `hasGlow: false` above: the
      // composite asks the frame for a resource nobody produced and gets
      // nothing, without allocating anything to say so.
      final graph = compile(bloom: false);
      final resources = FrameResources(
        source: const _NoTextures(),
        graph: graph,
        frameWidth: 640,
        frameHeight: 480,
      );
      resources.beginNode(graph.order.indexOf(composite));
      expect(resources.tryTexture(FrameResourceIds.bloom), isNull);
    });
  });
}
