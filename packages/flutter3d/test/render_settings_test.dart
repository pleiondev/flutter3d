/// `RenderSettings.copyWith` must not lose a field.
///
/// It lost six: `surfaceBuffer`, `showSurfaceBuffer`, `showShadowMap`,
/// `showPointShadowDebug`, `reflections` and `fog`. Changing the exposure
/// through `copyWith` therefore also switched reflections and fog off and
/// turned three debug views off with them — a bug that does what was asked and
/// something else besides, so it reads as the feature never having worked.
///
/// The round trip below is deliberately written the tedious way, field by
/// field, rather than through an `operator ==` on `RenderSettings`. Value
/// equality there would need a decision about `highlighted`, which is a
/// `List<SceneNode>` and whose identity-versus-value semantics have
/// consequences elsewhere. This test needs no such decision.
library;

import 'package:flutter3d/src/engine/render/debug_draw.dart';
import 'package:flutter3d/src/engine/render/renderer.dart';
import 'package:flutter3d/src/engine/scene/scene_node.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('an argument-less copyWith changes nothing', () {
    // Every field non-default, so a dropped one shows as a reverted value
    // rather than as a coincidence.
    final highlighted = <SceneNode>[SceneNode(name: 'lit')];
    final original = RenderSettings(
      specular: 0.25,
      exposure: 2.75,
      wireframe: true,
      backfaceCulling: false,
      debug: const DebugDrawOptions(bounds: true, axes: true),
      highlighted: highlighted,
      tonemap: false,
      bloom: const BloomSettings(enabled: false, intensity: 0.125),
      shadows: const ShadowSettings(enabled: false, resolution: 256),
      surfaceBuffer: true,
      showSurfaceBuffer: true,
      showShadowMap: true,
      showPointShadowDebug: true,
      reflections: const ReflectionSettings(enabled: true),
      fog: FogSettings(color: Vector3(0.1, 0.2, 0.3), density: 0.05),
      anisotropy: 8,
    );

    final copy = original.copyWith();

    expect(copy.specular, original.specular);
    expect(copy.exposure, original.exposure);
    expect(copy.wireframe, original.wireframe);
    expect(copy.backfaceCulling, original.backfaceCulling);
    expect(copy.debug, same(original.debug));
    expect(copy.highlighted, same(original.highlighted));
    expect(copy.tonemap, original.tonemap);
    expect(copy.bloom, same(original.bloom));
    expect(copy.shadows, same(original.shadows));
    expect(
      copy.surfaceBuffer,
      original.surfaceBuffer,
      reason: 'surfaceBuffer was one of the six',
    );
    expect(
      copy.showSurfaceBuffer,
      original.showSurfaceBuffer,
      reason: 'showSurfaceBuffer was one of the six',
    );
    expect(
      copy.showShadowMap,
      original.showShadowMap,
      reason: 'showShadowMap was one of the six',
    );
    expect(
      copy.showPointShadowDebug,
      original.showPointShadowDebug,
      reason: 'showPointShadowDebug was one of the six',
    );
    expect(
      copy.reflections,
      same(original.reflections),
      reason: 'reflections was one of the six',
    );
    expect(copy.fog, same(original.fog), reason: 'fog was one of the six');
    expect(
      copy.anisotropy,
      original.anisotropy,
      reason:
          'anisotropy dropped by copyWith is a setting that goes back to '
          'one tap the moment a game changes its exposure',
    );
  });

  test('anisotropy is one tap unless asked for', () {
    // Every sampler the engine bound before the setting existed bound with
    // one tap, and the default has to keep it that way: a default above one
    // moves every textured golden in the three sets at once.
    expect(const RenderSettings().anisotropy, 1);
    expect(const RenderSettings().copyWith(anisotropy: 16).anisotropy, 16);
  });

  test('anisotropy below one is refused where it is written', () {
    // Mutation: drop the constructor's assert. Zero then reaches the
    // renderer, which reads it as one tap and draws — the same rule
    // `SamplerOptions` asserts, held here so the two agree on what a count
    // of taps is.
    expect(() => RenderSettings(anisotropy: 0), throwsAssertionError);
    expect(() => RenderSettings(anisotropy: -4), throwsAssertionError);
  });

  test('copyWith replaces what it is given and nothing else', () {
    const original = RenderSettings(
      exposure: 1.0,
      reflections: ReflectionSettings(enabled: true),
    );

    final copy = original.copyWith(exposure: 3.0);

    expect(copy.exposure, 3.0);
    expect(
      copy.reflections.enabled,
      isTrue,
      reason:
          'changing the exposure switched reflections off, which is the '
          'shape of the bug this file exists for',
    );
  });

  test('the shadow resolution has two ceilings, and both are named', () {
    // **One number, two legal ranges, and neither was written down.** The
    // cascade pass clamped to 256–4096 and the cube atlas to 128–1024, in two
    // files, as literals — which reads as one of them being a typo. It is not:
    // the cube atlas holds six faces of four lights side by side, so the tile
    // size that gives a cascade a 4096-pixel texture would give the atlas a
    // 24,576-pixel one.
    expect(
      ShadowSettings.maxCubeTile * 6,
      lessThanOrEqualTo(ShadowSettings.maxResolution * 6 ~/ 2),
      reason: 'the cube ceiling stopped being the lower of the two',
    );
    expect(ShadowSettings.minCubeTile, lessThan(ShadowSettings.minResolution));
    expect(ShadowSettings.maxCubeTile, lessThan(ShadowSettings.maxResolution));

    // And the shipped default sits inside both, which is what stops a game
    // that changes nothing from being clamped by either.
    const settings = ShadowSettings();
    expect(
      settings.resolution,
      inInclusiveRange(
        ShadowSettings.minResolution,
        ShadowSettings.maxResolution,
      ),
    );
    expect(
      settings.resolution,
      greaterThanOrEqualTo(ShadowSettings.minCubeTile),
    );
  });
}
